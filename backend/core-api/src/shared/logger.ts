// Journal JSON sur stdout. Les champs sensibles sont retirés quel que soit l'appelant.
const SECRET = /token|secret|password|authorization|cookie|vault/i;

function clean(value: unknown, depth = 0): unknown {
  if (value instanceof Error) return { name: value.name, message: value.message, code: (value as { code?: unknown }).code };
  if (!value || typeof value !== "object" || depth > 3) return value;
  if (Array.isArray(value)) return value.slice(0, 20).map((v) => clean(v, depth + 1));
  return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, SECRET.test(k) ? "[masqué]" : clean(v, depth + 1)]));
}

const write = (level: string, service: string) => (fields: Record<string, unknown>, msg: string) => {
  if (process.env.LOG_LEVEL === "silent") return;
  process.stdout.write(JSON.stringify({ time: new Date().toISOString(), level, service, msg, ...(clean(fields) as object) }) + "\n");
};

export const createLogger = (service: string) => ({ info: write("info", service), warn: write("warn", service), error: write("error", service) });
export type Logger = ReturnType<typeof createLogger>;
