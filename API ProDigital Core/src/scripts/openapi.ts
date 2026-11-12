// Écrit le document OpenAPI dérivé du code : node dist/scripts/openapi.js > openapi.json
import { buildOpenApi } from "../core/openapi.js";
import { resources } from "../core/resources/index.js";

process.stdout.write(JSON.stringify(buildOpenApi(resources), null, 2) + "\n");
