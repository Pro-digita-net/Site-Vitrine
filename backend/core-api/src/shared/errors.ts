/** Erreur applicative : seule source des réponses d'erreur JSON. */
export class AppError extends Error {
  constructor(public status: number, public code: string, message: string, public details?: unknown) { super(message); }
}
export const badRequest = (message: string, details?: unknown) => new AppError(400, "invalid_request", message, details);
export const unauthorized = () => new AppError(401, "unauthorized", "Authentification requise ou jeton invalide.");
export const forbidden = (message = "Opération non autorisée.") => new AppError(403, "forbidden", message);
export const notFound = () => new AppError(404, "not_found", "Ressource introuvable.");
export const conflict = (message: string, code = "conflict") => new AppError(409, code, message);
export const unprocessable = (message: string, details?: unknown) => new AppError(422, "unprocessable", message, details);

/** Traduit une erreur PostgreSQL sans jamais exposer son texte (noms de contraintes, valeurs). */
export function fromPgError(error: unknown): AppError | null {
  const code = (error as { code?: unknown } | null)?.code;
  if (typeof code !== "string" || !/^[0-9A-Z]{5}$/.test(code)) return null;
  if (code === "23505") return conflict("Une ressource identique existe déjà.", "duplicate");
  if (code === "23503") return unprocessable("Une ressource référencée est introuvable.");
  if (code.startsWith("23")) return unprocessable("Les données ne respectent pas les règles du référentiel.");
  if (code === "42501") return forbidden();
  if (code === "P0002") return notFound();
  if (code.startsWith("22")) return badRequest("Valeur invalide.");
  if (code === "40001" || code === "40P01") return conflict("Modification concurrente : réessayer.", "concurrent_update");
  if (code === "57014") return new AppError(504, "timeout", "Délai de traitement dépassé.");
  if (code.startsWith("08") || code.startsWith("53") || code.startsWith("57")) return new AppError(503, "unavailable", "Service momentanément indisponible.");
  return null;
}
