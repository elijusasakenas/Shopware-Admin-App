import type { Env } from "./types";

const APPLE_ROOT_CA_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
const APPLE_APP_STORE_LEAF_OID = "060a2a864886f76364060b01";
const APPLE_WWDR_INTERMEDIATE_OID = "06092a864886f76364060201";
const MAX_JWS_LENGTH = 32_768;

interface TransactionPayload {
  appAppleId?: number;
  bundleId?: string;
  environment?: "Production" | "Sandbox";
  expiresDate?: number;
  originalTransactionId?: string;
  productId?: string;
  revocationDate?: number;
  signedDate?: number;
}

export interface VerifiedTransaction {
  subject: string;
  environment: "Production" | "Sandbox";
}

export async function verifyAppStoreTransaction(jws: string, env: Env): Promise<VerifiedTransaction> {
  if (jws.length > MAX_JWS_LENGTH) throw new Error("transaction is too large");
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("malformed transaction");
  const [headerB64, payloadB64, signatureB64] = parts;

  let header: { alg?: string; x5c?: string[] };
  try {
    header = JSON.parse(textDecode(base64URLDecode(headerB64)));
  } catch {
    throw new Error("malformed transaction");
  }
  if (header.alg !== "ES256") throw new Error("unexpected algorithm");
  if (!header.x5c || header.x5c.length !== 3) throw new Error("unexpected certificate chain");
  if (header.x5c.some((certificate) => certificate.length > 8_192)) throw new Error("certificate is too large");
  const chain = header.x5c.map(base64Decode);

  const rootHash = hex(new Uint8Array(await crypto.subtle.digest("SHA-256", chain[2])));
  if (rootHash !== APPLE_ROOT_CA_G3_SHA256) throw new Error("untrusted certificate chain");
  if (!hex(chain[0]).includes(APPLE_APP_STORE_LEAF_OID)) throw new Error("unexpected signing certificate");
  if (!hex(chain[1]).includes(APPLE_WWDR_INTERMEDIATE_OID)) throw new Error("unexpected intermediate certificate");

  for (const certificate of chain) assertCertificateIsCurrentlyValid(certificate);
  for (let index = 0; index < chain.length - 1; index++) {
    if (!(await verifyCertificateSignature(chain[index], chain[index + 1]))) throw new Error("broken certificate chain");
  }

  const leafKey = await importCertificateKey(chain[0]);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    leafKey,
    base64URLDecode(signatureB64),
    new TextEncoder().encode(`${headerB64}.${payloadB64}`),
  );
  if (!valid) throw new Error("invalid signature");

  let payload: TransactionPayload;
  try {
    payload = JSON.parse(textDecode(base64URLDecode(payloadB64))) as TransactionPayload;
  } catch {
    throw new Error("malformed transaction payload");
  }
  const expectedEnvironment = env.APPLE_ENVIRONMENT ?? "Production";
  if (payload.environment !== expectedEnvironment) throw new Error("wrong App Store environment");
  if (payload.bundleId !== env.APPLE_BUNDLE_ID) throw new Error("wrong app");
  if (expectedEnvironment === "Production") {
    if (!env.APPLE_APP_ID) throw new Error("server App Store app ID is not configured");
    if (String(payload.appAppleId) !== env.APPLE_APP_ID) throw new Error("wrong App Store app ID");
  }
  if (payload.productId !== env.SUBSCRIPTION_PRODUCT_ID) throw new Error("wrong product");
  if (payload.revocationDate) throw new Error("subscription revoked");
  if (!payload.expiresDate || payload.expiresDate < Date.now()) throw new Error("subscription expired");
  if (!payload.originalTransactionId || payload.originalTransactionId.length > 128) throw new Error("missing transaction identity");
  if (payload.signedDate && payload.signedDate > Date.now() + 300_000) throw new Error("transaction is signed in the future");
  return { subject: payload.originalTransactionId, environment: expectedEnvironment };
}

interface TLV {
  tag: number;
  contentStart: number;
  contentEnd: number;
  start: number;
}

function readTLV(bytes: Uint8Array, offset: number): TLV {
  if (offset < 0 || offset + 2 > bytes.length) throw new Error("malformed certificate");
  const tag = bytes[offset];
  let cursor = offset + 1;
  let length = bytes[cursor++];
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4 || cursor + count > bytes.length) throw new Error("malformed certificate");
    length = 0;
    for (let index = 0; index < count; index++) length = length * 256 + bytes[cursor++];
  }
  if (cursor + length > bytes.length) throw new Error("malformed certificate");
  return { tag, contentStart: cursor, contentEnd: cursor + length, start: offset };
}

function childrenOf(bytes: Uint8Array, tlv: TLV): TLV[] {
  const children: TLV[] = [];
  let cursor = tlv.contentStart;
  while (cursor < tlv.contentEnd) {
    const child = readTLV(bytes, cursor);
    children.push(child);
    cursor = child.contentEnd;
  }
  if (cursor !== tlv.contentEnd) throw new Error("malformed certificate");
  return children;
}

function fullBytes(bytes: Uint8Array, tlv: TLV): Uint8Array {
  return bytes.slice(tlv.start, tlv.contentEnd);
}

function parseCertificate(der: Uint8Array) {
  const outer = readTLV(der, 0);
  if (outer.tag !== 0x30 || outer.contentEnd !== der.length) throw new Error("malformed certificate");
  const certificateParts = childrenOf(der, outer);
  if (certificateParts.length !== 3) throw new Error("malformed certificate");
  const [tbs, signatureAlgorithm, signatureBits] = certificateParts;
  const oid = childrenOf(der, signatureAlgorithm)[0];
  const oidHex = hex(fullBytes(der, oid));
  const hash = oidHex === "06082a8648ce3d040302" ? "SHA-256" : oidHex === "06082a8648ce3d040303" ? "SHA-384" : null;
  if (!hash) throw new Error("unsupported certificate signature algorithm");
  const tbsChildren = childrenOf(der, tbs);
  const hasVersion = tbsChildren[0]?.tag === 0xa0;
  const validity = tbsChildren[hasVersion ? 4 : 3];
  const spki = tbsChildren[hasVersion ? 6 : 5];
  if (!validity || !spki || signatureBits.tag !== 0x03) throw new Error("malformed certificate");
  return {
    tbsBytes: fullBytes(der, tbs),
    hash,
    derSignature: der.slice(signatureBits.contentStart + 1, signatureBits.contentEnd),
    spki: fullBytes(der, spki),
    validity: childrenOf(der, validity),
  };
}

function assertCertificateIsCurrentlyValid(der: Uint8Array): void {
  const validity = parseCertificate(der).validity;
  if (validity.length !== 2) throw new Error("malformed certificate validity");
  const notBefore = parseASN1Time(der, validity[0]);
  const notAfter = parseASN1Time(der, validity[1]);
  const now = Date.now();
  if (now < notBefore || now > notAfter) throw new Error("certificate is not currently valid");
}

function parseASN1Time(bytes: Uint8Array, tlv: TLV): number {
  const value = textDecode(bytes.slice(tlv.contentStart, tlv.contentEnd));
  let year: number;
  let rest: string;
  if (tlv.tag === 0x17 && /^\d{12}Z$/.test(value)) {
    const shortYear = Number(value.slice(0, 2));
    year = shortYear >= 50 ? 1900 + shortYear : 2000 + shortYear;
    rest = value.slice(2);
  } else if (tlv.tag === 0x18 && /^\d{14}Z$/.test(value)) {
    year = Number(value.slice(0, 4));
    rest = value.slice(4);
  } else {
    throw new Error("unsupported certificate time");
  }
  const month = Number(rest.slice(0, 2)) - 1;
  const day = Number(rest.slice(2, 4));
  const hour = Number(rest.slice(4, 6));
  const minute = Number(rest.slice(6, 8));
  const second = Number(rest.slice(8, 10));
  return Date.UTC(year, month, day, hour, minute, second);
}

function curveOf(spki: Uint8Array): { curve: "P-256" | "P-384"; size: number } {
  const value = hex(spki);
  if (value.includes("06082a8648ce3d030107")) return { curve: "P-256", size: 32 };
  if (value.includes("06052b81040022")) return { curve: "P-384", size: 48 };
  throw new Error("unsupported certificate key type");
}

async function importSPKI(spki: Uint8Array): Promise<{ key: CryptoKey; size: number }> {
  const { curve, size } = curveOf(spki);
  const key = await crypto.subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: curve }, false, ["verify"]);
  return { key, size };
}

async function importCertificateKey(certificate: Uint8Array): Promise<CryptoKey> {
  return (await importSPKI(parseCertificate(certificate).spki)).key;
}

async function verifyCertificateSignature(certificate: Uint8Array, issuer: Uint8Array): Promise<boolean> {
  const parsed = parseCertificate(certificate);
  const issuerKey = await importSPKI(parseCertificate(issuer).spki);
  return crypto.subtle.verify(
    { name: "ECDSA", hash: parsed.hash },
    issuerKey.key,
    derSignatureToRaw(parsed.derSignature, issuerKey.size),
    parsed.tbsBytes,
  );
}

function derSignatureToRaw(der: Uint8Array, size: number): Uint8Array {
  const parts = childrenOf(der, readTLV(der, 0));
  if (parts.length !== 2 || parts.some((part) => part.tag !== 0x02)) throw new Error("malformed signature");
  const raw = new Uint8Array(size * 2);
  raw.set(trimInteger(der.slice(parts[0].contentStart, parts[0].contentEnd), size), 0);
  raw.set(trimInteger(der.slice(parts[1].contentStart, parts[1].contentEnd), size), size);
  return raw;
}

function trimInteger(bytes: Uint8Array, size: number): Uint8Array {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  const trimmed = bytes.slice(start);
  if (trimmed.length > size) throw new Error("malformed signature");
  const result = new Uint8Array(size);
  result.set(trimmed, size - trimmed.length);
  return result;
}

function base64Decode(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function base64URLDecode(value: string): Uint8Array {
  return base64Decode(value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (value.length % 4)) % 4));
}

function textDecode(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}
