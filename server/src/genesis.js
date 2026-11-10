// Transmission à Genesis CRM via l'endpoint d'ingestion existant
// POST /api/sales/public/leads (jeton de service, Idempotency-Key — PR #28,
// migration 015). Logique reprise du backend `local-apps/site` (genesis-client.ts),
// limitée au chemin officiel par jeton : le jeton reste côté serveur.

import { config } from "./config.js";
import { detailValue } from "./submission.js";
import { genesisComment } from "./summary.js";

export const GENESIS_LEADS_PATH = "/api/sales/public/leads";

export class GenesisError extends Error {
  /** @param {boolean} retryable false : inutile de réessayer sans intervention (données ou configuration). */
  constructor(message, { status, retryable }) {
    super(message);
    this.status = status;
    this.retryable = retryable;
  }
}

/** Corps envoyé à Genesis — déterministe : une relance renvoie exactement le même contenu. */
export function genesisPayload(row) {
  return {
    given_name: row.given_name,
    family_name: row.family_name,
    email: row.email,
    subject: `${row.subject} — ${row.company || `${row.given_name} ${row.family_name}`}`.slice(0, 200),
    message: genesisComment(row),
    budget_band: detailValue(row, "budget") ?? undefined,
    source: "site_web",
    channel: "site_web",
  };
}

/** Clé d'idempotence stable par demande : Genesis renvoie le même lead en cas de relance. */
export const genesisIdempotencyKey = (row) => `site-vitrine:${row.id}`;

/** Crée (ou retrouve) la demande dans Genesis ; renvoie l'id du lead. */
export async function pushToGenesis(row) {
  const { url, serviceToken, timeoutMs } = config.genesis;
  if (!serviceToken) {
    throw new GenesisError("GENESIS_SERVICE_TOKEN non configuré", { retryable: true });
  }

  let response;
  try {
    response = await fetch(`${url}${GENESIS_LEADS_PATH}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: `Bearer ${serviceToken}`,
        "Idempotency-Key": genesisIdempotencyKey(row),
      },
      body: JSON.stringify(genesisPayload(row)),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    const reason = error?.cause?.code || error?.name || "erreur réseau";
    throw new GenesisError(`Genesis injoignable (${reason})`, { retryable: true });
  }

  const raw = await response.text();
  let data = null;
  try {
    data = raw ? JSON.parse(raw) : null;
  } catch {
    data = null;
  }
  const remoteMessage = data?.error?.message || raw.slice(0, 200);

  if (response.status === 200 || response.status === 201) {
    const id = data?.lead?.id;
    if (typeof id !== "string" || !id) {
      throw new GenesisError(`Réponse Genesis sans identifiant de lead (HTTP ${response.status})`, { status: response.status, retryable: true });
    }
    return id;
  }
  // Données refusées ou conflit d'idempotence : réessayer à l'identique ne changera rien.
  if (response.status === 400 || response.status === 409 || response.status === 413 || response.status === 422) {
    throw new GenesisError(`Genesis a refusé la demande (HTTP ${response.status}) : ${remoteMessage}`, { status: response.status, retryable: false });
  }
  // 401/403 : jeton à corriger côté configuration ; 404 : endpoint absent ; 5xx : panne.
  // On réessaie avec délai croissant, la demande reste en attente sans être perdue.
  throw new GenesisError(`Genesis a répondu HTTP ${response.status} : ${remoteMessage}`, { status: response.status, retryable: true });
}
