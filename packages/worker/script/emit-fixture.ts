/**
 * Regenerates contract/token.jwt from the committed test key and claims.
 * Ed25519 is deterministic, so a diff here means the payload shape changed.
 */
import { importPrivateKey, signOriginToken } from "../src/index";

const root = new URL("../../../", import.meta.url);
const privatePem = await Bun.file(new URL("contract/keys/test-private.pem", root)).text();
const claims = (await Bun.file(new URL("contract/claims.json", root)).json()) as {
  iss: string;
  aud: string;
  sub?: string;
  flags?: Record<string, string | number | boolean>;
  iat: number;
  ttlSeconds: number;
};

const key = await importPrivateKey(privatePem);
const token = await signOriginToken(key, {
  iss: claims.iss,
  aud: claims.aud,
  sub: claims.sub,
  flags: claims.flags,
  nowSeconds: claims.iat,
  ttlSeconds: claims.ttlSeconds,
});

await Bun.write(new URL("contract/token.jwt", root), token + "\n");
console.log(token);
