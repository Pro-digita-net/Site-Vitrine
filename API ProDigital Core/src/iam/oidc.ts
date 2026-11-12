import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import { AppError, unauthorized } from "../shared/errors.js";

export interface VerifiedIdentity { issuer: string; subject: string; email: string | null; emailVerified: boolean; givenName: string | null; familyName: string | null }
export type IdentityVerifier = (idToken: string) => Promise<VerifiedIdentity>;

/**
 * Vérifie un ID token OpenID Connect émis par le fournisseur d'identité configuré (signature via JWKS,
 * émetteur, audience, expiration). Le schéma ne stocke aucun mot de passe : l'authentification
 * primaire est déléguée au fournisseur, l'API n'émet ensuite que des jetons opaques.
 */
export function createOidcVerifier(cfg: { issuer: string; audience: string; jwksUri: string }): IdentityVerifier {
  let keys: JWTVerifyGetKey | undefined;
  const resolveKeys = async () => {
    if (keys) return keys;
    let uri = cfg.jwksUri;
    if (!uri) {
      const response = await fetch(`${cfg.issuer.replace(/\/$/, "")}/.well-known/openid-configuration`, { signal: AbortSignal.timeout(5000) });
      uri = ((await response.json()) as { jwks_uri?: string }).jwks_uri ?? "";
    }
    return (keys = createRemoteJWKSet(new URL(uri), { timeoutDuration: 5000 }));
  };
  return async (idToken) => {
    if (!cfg.issuer || !cfg.audience) throw new AppError(503, "not_configured", "Fournisseur d'identité non configuré (OIDC_ISSUER, OIDC_AUDIENCE).");
    if (typeof idToken !== "string" || idToken.length > 8192) throw unauthorized();
    let getKey: JWTVerifyGetKey;
    try { getKey = await resolveKeys(); } catch { throw new AppError(503, "unavailable", "Fournisseur d'identité injoignable."); }
    try {
      const { payload } = await jwtVerify(idToken, getKey, {
        issuer: cfg.issuer, audience: cfg.audience, algorithms: ["RS256", "PS256", "ES256", "EdDSA"],
        requiredClaims: ["sub", "exp", "iat"], clockTolerance: 30, maxTokenAge: "1h",
      });
      const str = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim().slice(0, 254) : null);
      return { issuer: cfg.issuer, subject: String(payload.sub).slice(0, 255), email: str(payload.email)?.toLowerCase() ?? null,
        emailVerified: payload.email_verified === true, givenName: str(payload.given_name), familyName: str(payload.family_name) };
    } catch { throw unauthorized(); }
  };
}
