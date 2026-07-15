import { HTTPError } from "./http";

const encoder = new TextEncoder();

export async function sealToken(payload: object, secret: string): Promise<string> {
  if (secret.length < 32) throw new HTTPError(503, "Capability secret is not configured securely.");
  const key = await deriveKey(secret);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = encoder.encode(JSON.stringify(payload));
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, plaintext);
  return `v1.${base64URL(iv)}.${base64URL(new Uint8Array(encrypted))}`;
}

export async function openToken<T>(token: string, secret: string): Promise<T> {
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== "v1" || token.length > 20_000) {
    throw new HTTPError(401, "Invalid capability token.");
  }
  try {
    const key = await deriveKey(secret);
    const plaintext = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: base64URLDecode(parts[1]) },
      key,
      base64URLDecode(parts[2]),
    );
    return JSON.parse(new TextDecoder().decode(plaintext)) as T;
  } catch (error) {
    if (error instanceof HTTPError) throw error;
    throw new HTTPError(401, "Invalid or expired capability token.");
  }
}

async function deriveKey(secret: string): Promise<CryptoKey> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(secret));
  return crypto.subtle.importKey("raw", digest, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

export async function sha256(value: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64URLDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (value.length % 4)) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
