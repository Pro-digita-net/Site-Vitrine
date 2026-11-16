import { createHash, randomBytes } from "node:crypto";

/** Jeton opaque : 32 octets aléatoires (43 caractères base64url). Seul son SHA-256 est stocké. */
export const generateToken = () => randomBytes(32).toString("base64url");
export const hashToken = (token: string) => createHash("sha256").update(token, "utf8").digest();

export function bearer(header: string | undefined): string | null {
  const match = /^Bearer ([A-Za-z0-9_-]{43,128})$/.exec(header ?? "");
  return match ? match[1]! : null;
}

export const PERMISSIONS = [
  "directory.read", "directory.write", "catalog.read", "catalog.write", "documents.read", "documents.write",
  "requests.read", "requests.write", "integrations.read", "integrations.write", "audit.read",
] as const;
export type Permission = (typeof PERMISSIONS)[number];
