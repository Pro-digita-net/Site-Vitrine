// Exécution des opérations d'une demande (e-mail, Genesis), avec relances.
// Chaque opération est indépendante : l'échec de l'une ne bloque pas l'autre.
// Sûr avec plusieurs instances (FOR UPDATE SKIP LOCKED + bail `locked_until`).

import { config } from "./config.js";
import { sendNotification } from "./email.js";
import { pushToGenesis } from "./genesis.js";
import { claimDueOperations, getSubmission, markFailed, markSucceeded } from "./store.js";

const handlers = {
  email: (row) => sendNotification(row),
  crm: (row) => pushToGenesis(row),
};

export function nextRetryAt(attempts, retryable = true) {
  const delays = config.worker.backoffSeconds;
  if (!retryable || attempts > delays.length) return null;
  return new Date(Date.now() + delays[attempts - 1] * 1000);
}

export async function runOperation({ submission_id: id, kind, attempts }, log) {
  const row = await getSubmission(id);
  if (!row) {
    await markFailed(id, kind, new Error(`Demande ${id} introuvable : l’opération ${kind} ne peut pas partir.`), null);
    log.warn?.({ id, kind }, "Opération abandonnée : demande introuvable");
    return;
  }
  const handler = handlers[kind];
  if (!handler) {
    const error = new Error(`Opération « ${kind} » inconnue : seuls email et crm sont prévus.`);
    error.retryable = false;
    await markFailed(id, kind, error, null);
    log.warn?.({ id, kind }, "Opération abandonnée : type inconnu");
    return;
  }
  try {
    const externalId = await handler(row);
    await markSucceeded(id, kind, externalId ?? null);
    log.info?.({ id, kind, attempts, externalId }, "Opération réussie");
  } catch (error) {
    const retryAt = nextRetryAt(attempts, error?.retryable !== false);
    await markFailed(id, kind, error, retryAt);
    log.warn?.({ id, kind, attempts, error: error?.message, retryAt }, retryAt ? "Opération en échec, relance planifiée" : "Opération abandonnée");
  }
}

/** Traite tout ce qui est dû ; renvoie le nombre d'opérations exécutées. */
export async function drain(log = console) {
  let total = 0;
  for (;;) {
    const due = await claimDueOperations(10, config.worker.leaseMs);
    if (!due.length) return total;
    await Promise.all(due.map((op) => runOperation(op, log)));
    total += due.length;
  }
}

export function startWorker(log = console) {
  let running = false;
  let again = false;
  let stopped = false;

  const tick = async () => {
    if (stopped) return;
    if (running) {
      again = true;
      return;
    }
    running = true;
    try {
      do {
        again = false;
        await drain(log);
      } while (again && !stopped);
    } catch (error) {
      log.error?.({ error: error?.message }, "Worker : traitement interrompu, nouvel essai au prochain cycle");
    } finally {
      running = false;
    }
  };

  const timer = setInterval(tick, config.worker.pollMs);
  timer.unref();
  void tick();
  return {
    /** Déclenche un traitement immédiat (après l'enregistrement d'une demande). */
    kick: () => void tick(),
    stop: async () => {
      stopped = true;
      clearInterval(timer);
      while (running) await new Promise((resolve) => setTimeout(resolve, 50));
    },
  };
}
