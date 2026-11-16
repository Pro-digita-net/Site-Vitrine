// Outils d'exploitation :
//   npm run migrate                      applique les migrations du schéma `site`
//   npm run ops -- list [n]              dernières demandes et statut des opérations
//   npm run ops -- show <id>             détail et historique d'une demande
//   npm run ops -- retry [<id>]          relance les opérations en échec (toutes ou une demande)
//   npm run ops -- drain                 exécute immédiatement les opérations dues

import { closePool, migrate } from "./db.js";
import { events, getSubmission, listRecent, operationStatus, requeue } from "./store.js";
import { drain } from "./worker.js";

const [command = "list", arg] = process.argv.slice(2);
const quiet = { info: () => {}, warn: () => {}, error: (d, m) => console.error(m, d) };

try {
  if (command === "migrate") {
    await migrate();
    console.log("Schéma `site` à jour.");
  } else if (command === "list") {
    console.table((await listRecent(Number(arg) || 20)).map((r) => ({
      id: r.id, reçue: r.created_at.toISOString(), contact: `${r.given_name} ${r.family_name}`,
      sujet: r.subject, email: r.email_status, crm: r.crm_status, erreur: r.last_error ?? "",
    })));
  } else if (command === "show" && arg) {
    const row = await getSubmission(arg);
    if (!row) throw new Error(`Demande introuvable : ${arg}`);
    console.log({ ...row, request_hash: undefined, natural_key: undefined });
    console.table(await operationStatus(arg));
    console.table(await events(arg));
  } else if (command === "retry") {
    const rows = await requeue(arg ?? null);
    console.log(`${rows.length} opération(s) replanifiée(s).`);
    console.log(`${await drain(quiet)} opération(s) exécutée(s).`);
  } else if (command === "drain") {
    console.log(`${await drain(quiet)} opération(s) exécutée(s).`);
  } else {
    console.log("Commandes : migrate | list [n] | show <id> | retry [<id>] | drain");
    process.exitCode = 1;
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await closePool();
}
