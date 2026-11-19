/**
 * Writes the throwaway keypair the contract fixture uses. Run once; the files
 * are committed on purpose (they never protect anything real).
 */
const keyPair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keyPair.privateKey));
const spki = new Uint8Array(await crypto.subtle.exportKey("spki", keyPair.publicKey));

const pem = (label: string, bytes: Uint8Array) => {
  const body = btoa(String.fromCharCode(...bytes)).replace(/(.{64})/g, "$1\n");
  return `-----BEGIN ${label}-----\n${body}\n-----END ${label}-----\n`;
};

const root = new URL("../../../", import.meta.url);
await Bun.write(new URL("contract/keys/test-private.pem", root), pem("PRIVATE KEY", pkcs8));
await Bun.write(new URL("contract/keys/test-public.pem", root), pem("PUBLIC KEY", spki));
console.log("wrote contract/keys/test-{private,public}.pem");
