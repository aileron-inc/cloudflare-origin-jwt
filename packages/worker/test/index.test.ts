import { describe, expect, test } from "bun:test";

import { importPrivateKey, originTokenHeaders, signOriginToken, base64url } from "../src/index";

const privatePem = await Bun.file(new URL("../../../contract/keys/test-private.pem", import.meta.url)).text();
const publicPem = await Bun.file(new URL("../../../contract/keys/test-public.pem", import.meta.url)).text();
const key = await importPrivateKey(privatePem);

const publicKey = async () => {
  const body = publicPem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const bytes = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("raw", bytes.slice(-32), { name: "Ed25519" }, false, ["verify"]);
};

const claims = { iss: "hairbook-gateway", aud: "salonpage", nowSeconds: 1_700_000_000, ttlSeconds: 60 };

describe("signOriginToken", () => {
  test("produces a token the origin can verify", async () => {
    const token = await signOriginToken(key, { ...claims, sub: "H0001", flags: { page_published: 1 } });
    const [header, payload, signature] = token.split(".");
    const signingInput = new TextEncoder().encode(`${header}.${payload}`);

    const ok = await crypto.subtle.verify(
      { name: "Ed25519" },
      await publicKey(),
      Uint8Array.from(atob(signature.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0)),
      signingInput,
    );

    expect(ok).toBe(true);
    expect(JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")))).toEqual({
      iss: "hairbook-gateway",
      aud: "salonpage",
      sub: "H0001",
      iat: 1_700_000_000,
      exp: 1_700_000_060,
      flags: { page_published: 1 },
    });
  });

  test("is deterministic for the same key and claims", async () => {
    const first = await signOriginToken(key, claims);
    const second = await signOriginToken(key, claims);
    expect(first).toBe(second);
  });

  test("keeps the header minimal", async () => {
    const token = await signOriginToken(key, claims);
    const header = JSON.parse(atob(token.split(".")[0].replace(/-/g, "+").replace(/_/g, "/")));
    expect(header).toEqual({ alg: "EdDSA", typ: "JWT" });
  });

  test("names the key when a kid is given", async () => {
    const token = await signOriginToken(key, { ...claims, kid: "2026-11" });
    const header = JSON.parse(atob(token.split(".")[0].replace(/-/g, "+").replace(/_/g, "/")));
    expect(header).toEqual({ alg: "EdDSA", typ: "JWT", kid: "2026-11" });
  });

  test("omits sub and flags when they are not given", async () => {
    const token = await signOriginToken(key, claims);
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    expect(Object.keys(payload)).toEqual(["iss", "aud", "iat", "exp"]);
  });
});

describe("originTokenHeaders", () => {
  test("uses the header the gem reads", () => {
    expect(originTokenHeaders("token")).toEqual({ "X-Cf-Origin-Jwt": "token" });
  });
});

describe("base64url", () => {
  test("has no padding and no plus or slash", () => {
    const encoded = base64url(new Uint8Array([251, 255, 254, 0, 1]));
    expect(encoded).not.toContain("=");
    expect(encoded).not.toContain("+");
    expect(encoded).not.toContain("/");
  });
});
