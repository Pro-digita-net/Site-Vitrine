import { getPool, withTransaction } from "./db.js";
import { naturalKey, requestHash } from "./submission.js";

export const OPERATIONS = ["email", "crm"];
const DUPLICATE_WINDOW = "24 hours";

export class ConflictError extends Error {}

/**
 * Enregistre une demande et planifie ses opérations, en une transaction.
 * - même Idempotency-Key + même contenu → demande existante (aucun doublon)
 * - même Idempotency-Key + contenu différent → ConflictError
 * - même e-mail/sujet/message dans les 24 h → demande existante
 * @returns {{ row, created: boolean }}
 */
export async function createSubmission(submission, idempotencyKey) {
  const hash = requestHash(submission);
  const natural = naturalKey(submission);

  return withTransaction(async (client) => {
    // Sérialise les envois concurrents d'un même contenu ou d'une même clé.
    await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [natural]);
    await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1, 1))", [idempotencyKey]);

    const byKey = await client.query("SELECT * FROM site.contact_submissions WHERE idempotency_key = $1", [idempotencyKey]);
    if (byKey.rows[0]) {
      if (byKey.rows[0].request_hash !== hash) {
        throw new ConflictError("Cette clé d'envoi a déjà servi pour une autre demande.");
      }
      return { row: byKey.rows[0], created: false };
    }

    const byContent = await client.query(
      `SELECT * FROM site.contact_submissions
        WHERE natural_key = $1 AND created_at > clock_timestamp() - $2::interval
        ORDER BY created_at LIMIT 1`,
      [natural, DUPLICATE_WINDOW],
    );
    if (byContent.rows[0]) {
      await client.query(
        "INSERT INTO site.contact_events (submission_id, kind, event, detail) VALUES ($1, 'submission', 'duplicate_ignored', $2)",
        [byContent.rows[0].id, "Nouvel envoi identique dans les 24 h : rattaché à la demande existante."],
      );
      return { row: byContent.rows[0], created: false };
    }

    const inserted = await client.query(
      `INSERT INTO site.contact_submissions
         (idempotency_key, request_hash, natural_key, given_name, family_name, email, company, subject, subject_group, details, message)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, $11)
       RETURNING *`,
      [
        idempotencyKey, hash, natural,
        submission.given_name, submission.family_name, submission.email, submission.company,
        submission.subject, submission.subject_group, JSON.stringify(submission.details), submission.message,
      ],
    );
    const row = inserted.rows[0];
    await client.query(
      `INSERT INTO site.contact_operations (submission_id, kind)
       SELECT $1, unnest($2::text[])`,
      [row.id, OPERATIONS],
    );
    await client.query(
      "INSERT INTO site.contact_events (submission_id, kind, event) VALUES ($1, 'submission', 'recorded')",
      [row.id],
    );
    return { row, created: true };
  });
}

/** Réserve les opérations à exécuter (en attente, ou bloquées après un arrêt brutal). */
export async function claimDueOperations(limit, leaseMs) {
  const { rows } = await getPool().query(
    `UPDATE site.contact_operations AS op
        SET status = 'running',
            attempts = op.attempts + 1,
            locked_until = clock_timestamp() + ($2::int * interval '1 millisecond'),
            updated_at = clock_timestamp()
      WHERE (op.submission_id, op.kind) IN (
              SELECT submission_id, kind FROM site.contact_operations
               WHERE (status = 'pending' AND next_attempt_at <= clock_timestamp())
                  OR (status = 'running' AND locked_until < clock_timestamp())
               ORDER BY next_attempt_at
               LIMIT $1
               FOR UPDATE SKIP LOCKED)
      RETURNING op.submission_id, op.kind, op.attempts`,
    [limit, leaseMs],
  );
  return rows;
}

export async function getSubmission(id) {
  const { rows } = await getPool().query("SELECT * FROM site.contact_submissions WHERE id = $1", [id]);
  return rows[0] ?? null;
}

export async function markSucceeded(id, kind, externalId) {
  await withTransaction(async (client) => {
    await client.query(
      `UPDATE site.contact_operations
          SET status = 'succeeded', external_id = $3, last_error = NULL, locked_until = NULL,
              completed_at = clock_timestamp(), updated_at = clock_timestamp()
        WHERE submission_id = $1 AND kind = $2`,
      [id, kind, externalId],
    );
    await client.query(
      "INSERT INTO site.contact_events (submission_id, kind, event, detail) VALUES ($1, $2, 'succeeded', $3)",
      [id, kind, externalId],
    );
  });
}

/** Échec d'une tentative : nouvelle tentative planifiée, ou abandon si `retryAt` est null. */
export async function markFailed(id, kind, error, retryAt) {
  const message = String(error?.message ?? error).slice(0, 1000);
  await withTransaction(async (client) => {
    await client.query(
      `UPDATE site.contact_operations
          SET status = $3, last_error = $4, locked_until = NULL,
              next_attempt_at = COALESCE($5, next_attempt_at), updated_at = clock_timestamp()
        WHERE submission_id = $1 AND kind = $2`,
      [id, kind, retryAt ? "pending" : "failed", message, retryAt],
    );
    await client.query(
      "INSERT INTO site.contact_events (submission_id, kind, event, detail) VALUES ($1, $2, $3, $4)",
      [id, kind, retryAt ? "retry_scheduled" : "failed", retryAt ? `${message} — nouvelle tentative le ${retryAt.toISOString()}` : message],
    );
  });
}

/** Relance manuelle des opérations non abouties d'une demande (ou de toutes). */
export async function requeue(id = null) {
  const { rows } = await getPool().query(
    `UPDATE site.contact_operations
        SET status = 'pending', next_attempt_at = clock_timestamp(), locked_until = NULL, updated_at = clock_timestamp()
      WHERE status IN ('failed', 'pending') AND ($1::uuid IS NULL OR submission_id = $1)
      RETURNING submission_id, kind`,
    [id],
  );
  for (const row of rows) {
    await getPool().query(
      "INSERT INTO site.contact_events (submission_id, kind, event, detail) VALUES ($1, $2, 'manual_retry', NULL)",
      [row.submission_id, row.kind],
    );
  }
  return rows;
}

export async function operationStatus(id) {
  const { rows } = await getPool().query(
    `SELECT kind, status, attempts, next_attempt_at, last_error, external_id, completed_at
       FROM site.contact_operations WHERE submission_id = $1 ORDER BY kind`,
    [id],
  );
  return rows;
}

export async function listRecent(limit = 20) {
  const { rows } = await getPool().query(
    `SELECT s.id, s.created_at, s.given_name, s.family_name, s.email, s.subject,
            max(o.status) FILTER (WHERE o.kind = 'email') AS email_status,
            max(o.status) FILTER (WHERE o.kind = 'crm') AS crm_status,
            max(o.last_error) FILTER (WHERE o.status <> 'succeeded') AS last_error
       FROM site.contact_submissions s
       JOIN site.contact_operations o ON o.submission_id = s.id
      GROUP BY s.id ORDER BY s.created_at DESC LIMIT $1`,
    [limit],
  );
  return rows;
}

export async function events(id) {
  const { rows } = await getPool().query(
    "SELECT at, kind, event, detail FROM site.contact_events WHERE submission_id = $1 ORDER BY at, id",
    [id],
  );
  return rows;
}
