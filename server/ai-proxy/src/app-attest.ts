import { Buffer } from "node:buffer";
import { verifyAssertion, verifyAttestation } from "node-app-attest";
import type { Env } from "./types";

export const APP_ATTEST_CHALLENGE_TTL_MS = 5 * 60_000;
export const APP_ATTEST_MAX_KEYS_PER_CLIENT = 10;
export type AppAttestPurpose = "attestation" | "chat";

export interface AppAttestRegistration {
  keyID: string;
  publicKey: string;
  receipt: string;
  environment: "development" | "production";
}

export function appAttestRequired(env: Env): boolean {
  return (env.APP_ATTEST_REQUIRED as string | undefined) !== "false";
}

export function appAttestConfiguration(env: Env): {
  bundleIdentifier: string;
  teamIdentifier: string;
  allowDevelopmentEnvironment: boolean;
} {
  const bundleIdentifier = env.APPLE_BUNDLE_ID?.trim();
  const teamIdentifier = env.APPLE_TEAM_ID?.trim();
  if (!bundleIdentifier || !teamIdentifier) {
    throw new Error("App Attest server configuration is incomplete.");
  }
  return {
    bundleIdentifier,
    teamIdentifier,
    allowDevelopmentEnvironment: (env.APP_ATTEST_ALLOW_DEVELOPMENT as string | undefined) === "true",
  };
}

export function validAppAttestKeyID(value: unknown): value is string {
  return typeof value === "string" && value.length >= 40 && value.length <= 128 &&
    /^[A-Za-z0-9+/_=-]+$/.test(value);
}

export function validAppAttestChallenge(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9_-]{43}$/.test(value);
}

export function decodeAppAttestObject(value: unknown, maximumBytes = 65_536): Buffer {
  if (typeof value !== "string" || value.length < 16 || value.length > Math.ceil(maximumBytes * 4 / 3) + 4 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    throw new Error("Invalid App Attest object encoding.");
  }
  const decoded = Buffer.from(value, "base64");
  if (decoded.byteLength < 1 || decoded.byteLength > maximumBytes) {
    throw new Error("Invalid App Attest object size.");
  }
  return decoded;
}

export function verifyAppAttestation(
  attestation: Buffer,
  challenge: string,
  keyID: string,
  env: Env,
): AppAttestRegistration {
  const result = verifyAttestation({
    attestation,
    challenge,
    keyId: keyID,
    ...appAttestConfiguration(env),
  }) as { keyId: string; publicKey: string; receipt: Buffer; environment: string };
  if (result.keyId !== keyID || typeof result.publicKey !== "string" ||
      !["development", "production"].includes(result.environment)) {
    throw new Error("Invalid App Attest verification result.");
  }
  return {
    keyID,
    publicKey: result.publicKey,
    receipt: Buffer.from(result.receipt).toString("base64"),
    environment: result.environment as "development" | "production",
  };
}

export function verifyAppAssertion(
  assertion: Buffer,
  payload: Uint8Array,
  publicKey: string,
  previousSignCount: number,
  env: Env,
): number {
  const result = verifyAssertion({
    assertion,
    payload: Buffer.from(payload),
    publicKey,
    signCount: previousSignCount,
    ...appAttestConfiguration(env),
  }) as { signCount: number };
  if (!Number.isSafeInteger(result.signCount) || result.signCount <= previousSignCount) {
    throw new Error("Invalid App Attest assertion counter.");
  }
  return result.signCount;
}

export async function appAttestPayload(
  method: string,
  path: string,
  challenge: string,
  body: Uint8Array,
): Promise<Uint8Array> {
  const bodyHash = new Uint8Array(await crypto.subtle.digest("SHA-256", body));
  const encodedHash = base64URLEncode(bodyHash);
  return new TextEncoder().encode(
    `shopware-ai-app-attest-v1\n${method.toUpperCase()}\n${path}\n${challenge}\n${encodedHash}`,
  );
}

export function base64URLEncode(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
