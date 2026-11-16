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
    throw new GenesisError("Transmission Genesis impossible : GENESIS_SERVICE_TOKEN n’est pas configuré.", { retryable: true });
  }
  if (!url) {
    throw new GenesisError("Transmission Genesis impossible : GENESIS_URL n’est pas configuré.", { retryable: true });
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
    const reason = error?.cause?.code || error?.code || error?.name || "erreur réseau";
    throw new GenesisError(`Genesis injoignable à ${url}${GENESIS_LEADS_PATH} (${reason}).`, { retryable: true });
  }

  const raw = await response.text();
  let data = null;
  try {
    data = raw ? JSON.parse(raw) : null;
  } catch {
    data = null;
  }
  const remoteMessage = clipGenesis(data?.error?.message || data?.message || raw);

  if (response.status === 200 || response.status === 201) {
    const id = data?.lead?.id;
    if (typeof id !== "string" || !id) {
      throw new GenesisError(`Genesis a répondu HTTP ${response.status} sans identifiant de lead.`, { status: response.status, retryable: true });
    }
    return id;
  }
  // Données refusées ou conflit d'idempotence : réessayer à l'identique ne changera rien.
  if (response.status === 400 || response.status === 409 || response.status === 413 || response.status === 422) {
    throw new GenesisError(`Genesis a refusé la demande (HTTP ${response.status}) : ${remoteMessage}.`, { status: response.status, retryable: false });
  }
  if (response.status === 401) {
    throw new GenesisError(`Genesis a refusé le jeton de service (HTTP 401) : ${remoteMessage}.`, { status: 401, retryable: true });
  }
  if (response.status === 403) {
    throw new GenesisError(`Genesis a refusé l’autorisation du jeton de service (HTTP 403) : ${remoteMessage}.`, { status: 403, retryable: true });
  }
  if (response.status === 404) {
    throw new GenesisError(`Genesis n’a pas cet endpoint (HTTP 404, ${GENESIS_LEADS_PATH}) : ${remoteMessage}.`, { status: 404, retryable: true });
  }
  if (response.status === 429) {
    throw new GenesisError(`Genesis limite les envois (HTTP 429) : ${remoteMessage}.`, { status: 429, retryable: true });
  }
  // 5xx ou statut inattendu : panne distante, la demande reste en attente.
  throw new GenesisError(`Genesis a répondu HTTP ${response.status} : ${remoteMessage}.`, { status: response.status, retryable: true });
}

const clipGenesis = (value) => {
  const text = String(value ?? "").replace(/[\r\n]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 200);
  return text || "aucun détail fourni par Genesis";
};
