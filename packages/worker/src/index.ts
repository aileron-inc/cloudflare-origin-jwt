/**
 * Signs the origin token that cloudflare-origin-jwt verifies.
 *
 * The gateway runs at the Cloudflare edge, so the private key lives in a Worker
 * secret and the origin only ever holds the public half. Signatures are Ed25519
 * (deterministic), so the same key and claims always produce the same token.
 */

export type FlagValue = string | number | boolean;
export type Flags = Record<string, FlagValue>;

export type OriginTokenInput = {
  /** Token issuer the origin checks. */
  iss: string;
  /** Audience the origin checks, normally one per app. */
  aud: string;
  /** Optional subject, for example the salon id. */
  sub?: string;
  /** Data the origin reads from the claims, such as salon flags. */
  flags?: Flags;
  /** Lifetime in seconds. Keep it short: 60 is a good default. */
  ttlSeconds?: number;
  /** Current time in seconds, injectable for tests. */
  nowSeconds?: number;
};

export const ORIGIN_TOKEN_HEADER = "X-Cf-Origin-Jwt";
export const DEFAULT_TTL_SECONDS = 60;

const encoder = new TextEncoder();

export function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function segment(value: unknown): string {
  return base64url(encoder.encode(JSON.stringify(value)));
}

/** Import a PKCS#8 PEM private key (Ed25519) into WebCrypto. */
export async function importPrivateKey(pkcs8Pem: string): Promise<CryptoKey> {
  const body = pkcs8Pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bytes = Uint8Array.from(atob(body), (char) => char.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", bytes, { name: "Ed25519" }, false, ["sign"]);
}

export async function signOriginToken(
  privateKey: CryptoKey,
  input: OriginTokenInput,
): Promise<string> {
  const now = input.nowSeconds ?? Math.floor(Date.now() / 1000);
  const ttl = input.ttlSeconds ?? DEFAULT_TTL_SECONDS;

  // Key order is fixed on purpose: the token has to be byte-identical across
  // runs so the contract fixture can be regenerated and compared.
  const payload: Record<string, unknown> = { iss: input.iss, aud: input.aud };
  if (input.sub !== undefined) payload.sub = input.sub;
  payload.iat = now;
  payload.exp = now + ttl;
  if (input.flags !== undefined) payload.flags = input.flags;

  const signingInput = `${segment({ alg: "EdDSA", typ: "JWT" })}.${segment(payload)}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "Ed25519" }, privateKey, encoder.encode(signingInput)),
  );
  return `${signingInput}.${base64url(signature)}`;
}

/** Headers to attach to the request the gateway forwards to the origin. */
export function originTokenHeaders(token: string): Record<string, string> {
  return { [ORIGIN_TOKEN_HEADER]: token };
}
