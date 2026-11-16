import type { Config } from "../config.js";
import type { Pool } from "../shared/db.js";
import type { Metrics } from "../shared/http.js";
import type { Logger } from "../shared/logger.js";
import { createMailer, DeliveryError, resolveSecret, sendWebhook } from "./adapters.js";

interface OutboxJob { organization_id: string; id: string; event_type: string; payload: Record<string, unknown>; attempts: number }
interface DeliveryJob { organization_id: string; id: string; channel: string; recipient: string; template: string; payload: Record<string, unknown>; attempts: number }
class Permanent extends DeliveryError {}
// Le message conservé en base ne provient que d'erreurs maîtrisées ; le reste est réduit à un code.
const describe = (error: unknown) => (error instanceof DeliveryError ? error.message : `Erreur interne (${(error as { code?: string })?.code ?? (error as Error)?.name ?? "inconnue"})`).slice(0, 500);

/**
 * Workers de l'outbox et des notifications (compte pd_core_worker).
 * Réservation par bail avec FOR UPDATE SKIP LOCKED : plusieurs instances ne traitent jamais la même ligne ;
 * un bail expiré (arrêt brutal) est repris. La clôture vérifie le numéro de tentative (jeton de garde).
 */
export class Worker {
  private mail: ReturnType<typeof createMailer>;
  private timer?: NodeJS.Timeout; private running?: Promise<unknown>; private stopped = false;
  constructor(private pool: Pool, private cfg: Config["worker"], private log: Logger, private metrics?: Metrics) { this.mail = createMailer(cfg); }

  private retryAt(attempts: number): Date | null {
    const delay = this.cfg.backoffSeconds[attempts - 1];
    return delay ? new Date(Date.now() + delay * 1000) : null;
  }

  // ───────────── Outbox ─────────────
  async drainOutbox(): Promise<number> {
    const { rows } = await this.pool.query<OutboxJob>(
      `UPDATE integration.outbox AS o SET status = 'running', attempts = o.attempts + 1, locked_until = clock_timestamp() + ($2::int * interval '1 millisecond')
        WHERE (o.organization_id, o.id) IN (
          SELECT organization_id, id FROM integration.outbox
           WHERE (status = 'pending' AND available_at <= clock_timestamp()) OR (status = 'running' AND locked_until < clock_timestamp())
           ORDER BY available_at LIMIT $1 FOR UPDATE SKIP LOCKED)
        RETURNING o.organization_id, o.id, o.event_type, o.payload, o.attempts`, [this.cfg.batch, this.cfg.leaseMs]);
    for (const job of rows) {
      const guard = [job.organization_id, job.id, job.attempts];
      try {
        await this.dispatch(job);
        await this.pool.query("UPDATE integration.outbox SET status = 'succeeded', locked_until = NULL, last_error = NULL WHERE organization_id = $1 AND id = $2 AND status = 'running' AND attempts = $3", guard);
        this.metrics?.inc("outbox_succeeded_total");
      } catch (error) {
        const retry = error instanceof Permanent ? null : this.retryAt(job.attempts);
        await this.pool.query(
          `UPDATE integration.outbox SET status = $4, locked_until = NULL, last_error = $5, available_at = COALESCE($6, available_at)
            WHERE organization_id = $1 AND id = $2 AND status = 'running' AND attempts = $3`, [...guard, retry ? "pending" : "failed", describe(error), retry]);
        this.metrics?.inc(retry ? "outbox_retried_total" : "outbox_failed_total");
        this.log.warn({ outbox_id: job.id, event_type: job.event_type, attempts: job.attempts, retry: !!retry, error: describe(error) }, "événement outbox non abouti");
      }
    }
    return rows.length;
  }

  /** Diffuse un événement aux connexions activées de SON organisation uniquement. */
  private async dispatch(job: OutboxJob) {
    if (job.event_type !== "web.request.created") throw new Permanent("Type d'événement non pris en charge");
    const { rows } = await this.pool.query<{ id: string; provider: string; vault_reference: string | null }>(
      `SELECT c.id, c.provider, s.vault_reference FROM integration.connections c
         LEFT JOIN integration.connection_secrets s ON s.organization_id = c.organization_id AND s.connection_id = c.id
        WHERE c.organization_id = $1 AND c.status = 'enabled' AND c.provider IN ('webhook', 'email') ORDER BY c.id`, [job.organization_id]);
    for (const connection of rows) {
      if (!connection.vault_reference) throw new DeliveryError("Connexion activée sans secret enregistré");
      const secret = await resolveSecret(this.cfg, connection.vault_reference);
      if (connection.provider === "webhook") {
        const externalId = await sendWebhook(this.cfg, secret, { id: job.id, type: job.event_type, organization_id: job.organization_id, data: job.payload });
        if (externalId) await this.pool.query(
          `INSERT INTO integration.external_references (organization_id, connection_id, entity_type, local_id, external_id) VALUES ($1, $2, 'web.request', $3, $4)
           ON CONFLICT (organization_id, connection_id, entity_type, external_id) DO NOTHING`, [job.organization_id, connection.id, job.payload.request_id, externalId]);
      } else {
        if (typeof secret.to !== "string" || !/^[^\s@]+@[^\s@]+$/.test(secret.to)) throw new DeliveryError("Secret e-mail incomplet (to)");
        // Une seule notification par événement et destinataire, même après une nouvelle tentative.
        await this.pool.query(
          `INSERT INTO notifications.deliveries (organization_id, channel, recipient, template, payload)
           SELECT $1, 'email', $2, 'web_request_created', $3::jsonb
            WHERE NOT EXISTS (SELECT FROM notifications.deliveries WHERE organization_id = $1 AND recipient = $2 AND payload->>'outbox_id' = $4)`,
          [job.organization_id, secret.to, JSON.stringify({ outbox_id: job.id, request_id: job.payload.request_id, subject: job.payload.subject }), job.id]);
      }
    }
  }

  // ───────────── Notifications ─────────────
  async drainDeliveries(): Promise<number> {
    // La table n'a pas de colonne de bail : pendant l'envoi, next_attempt_at porte l'échéance de reprise.
    const { rows } = await this.pool.query<DeliveryJob>(
      `UPDATE notifications.deliveries AS d SET status = 'running', attempts = d.attempts + 1, next_attempt_at = clock_timestamp() + ($2::int * interval '1 millisecond')
        WHERE (d.organization_id, d.id) IN (
          SELECT organization_id, id FROM notifications.deliveries WHERE status IN ('pending', 'running') AND next_attempt_at <= clock_timestamp()
           ORDER BY next_attempt_at LIMIT $1 FOR UPDATE SKIP LOCKED)
        RETURNING d.organization_id, d.id, d.channel, d.recipient, d.template, d.payload, d.attempts`, [this.cfg.batch, this.cfg.leaseMs]);
    for (const job of rows) {
      const guard = [job.organization_id, job.id, job.attempts];
      try {
        if (job.channel !== "email") throw new Permanent("Canal non pris en charge");
        await this.mail(job.recipient, job.template, job.payload);
        await this.pool.query("UPDATE notifications.deliveries SET status = 'succeeded', delivered_at = clock_timestamp(), last_error = NULL WHERE organization_id = $1 AND id = $2 AND status = 'running' AND attempts = $3", guard);
        this.metrics?.inc("deliveries_succeeded_total");
      } catch (error) {
        const retry = error instanceof Permanent ? null : this.retryAt(job.attempts);
        await this.pool.query(
          `UPDATE notifications.deliveries SET status = $4, last_error = $5, next_attempt_at = COALESCE($6, clock_timestamp())
            WHERE organization_id = $1 AND id = $2 AND status = 'running' AND attempts = $3`, [...guard, retry ? "pending" : "failed", describe(error), retry]);
        this.metrics?.inc(retry ? "deliveries_retried_total" : "deliveries_failed_total");
        this.log.warn({ delivery_id: job.id, attempts: job.attempts, retry: !!retry, error: describe(error) }, "notification non aboutie");
      }
    }
    return rows.length;
  }

  async drain() { return (await this.drainOutbox()) + (await this.drainDeliveries()); }

  start() {
    const tick = () => {
      this.running = this.drain().catch((error) => { this.log.error({ error }, "cycle du worker en échec"); return 0; })
        .then((n) => { if (!this.stopped) this.timer = setTimeout(tick, n >= this.cfg.batch ? 0 : this.cfg.pollMs); });
    };
    tick();
  }
  async stop() { this.stopped = true; clearTimeout(this.timer); await this.running; }

  // ───────────── Exploitation (CLI) ─────────────
  readonly ops = {
    list: async (table: "outbox" | "deliveries", status?: string) => (await this.pool.query(
      table === "outbox"
        ? "SELECT organization_id, id, event_type, status, attempts, available_at, last_error, created_at FROM integration.outbox WHERE ($1::text IS NULL OR status = $1) ORDER BY created_at DESC LIMIT 50"
        : "SELECT organization_id, id, channel, template, status, attempts, next_attempt_at, last_error, created_at FROM notifications.deliveries WHERE ($1::text IS NULL OR status = $1) ORDER BY created_at DESC LIMIT 50",
      [status ?? null])).rows,
    retry: async (table: "outbox" | "deliveries", id: string) => (await this.pool.query(
      table === "outbox"
        ? "UPDATE integration.outbox SET status = 'pending', available_at = clock_timestamp(), locked_until = NULL WHERE id = $1 AND status = 'failed'"
        : "UPDATE notifications.deliveries SET status = 'pending', next_attempt_at = clock_timestamp() WHERE id = $1 AND status = 'failed'", [id])).rowCount,
    setSecretReference: async (organizationId: string, connectionId: string, reference: string) => (await this.pool.query(
      `INSERT INTO integration.connection_secrets (organization_id, connection_id, vault_reference) VALUES ($1, $2, $3)
       ON CONFLICT (organization_id, connection_id) DO UPDATE SET vault_reference = EXCLUDED.vault_reference`, [organizationId, connectionId, reference])).rowCount,
  };
}
