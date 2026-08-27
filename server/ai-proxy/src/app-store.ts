import type { SignedDataVerifier as AppleSignedDataVerifier } from "@apple/app-store-server-library";
import { Buffer } from "node:buffer";
import type { Env } from "./types";

// Apple Root CA - G3, DER encoded. Apple publishes this trust anchor at
// https://www.apple.com/certificateauthority/ and uses it in the official
// library's verification examples.
const APPLE_ROOT_CA_G3_BASE64 = "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";
const MAX_JWS_LENGTH = 32_768;
const verifierCache = new Map<string, AppleSignedDataVerifier>();
let appleLibraryPromise: Promise<typeof import("@apple/app-store-server-library")> | undefined;

/**
 * The Apple library loads jsrsasign, which performs random initialization at
 * module evaluation time. Workers prohibit that operation in global scope,
 * so defer evaluation until an actual request is being handled. The promise
 * is safe to reuse across requests because it contains no request data.
 */
function appleLibrary(): Promise<typeof import("@apple/app-store-server-library")> {
  appleLibraryPromise ??= import("@apple/app-store-server-library");
  return appleLibraryPromise;
}

export interface VerifiedTransaction {
  subject: string;
  environment: "Production" | "Sandbox";
}

export async function verifyAppStoreTransaction(jws: string, env: Env): Promise<VerifiedTransaction> {
  if (jws.length > MAX_JWS_LENGTH) throw new Error("transaction is too large");
  const preferred = (env.APPLE_ENVIRONMENT as "Production" | "Sandbox" | undefined) ?? "Production";
  const alternate: "Production" | "Sandbox" = preferred === "Production" ? "Sandbox" : "Production";

  try {
    return await verifyInEnvironment(jws, env, preferred);
  } catch (error) {
    // TestFlight and StoreKit testing always mint Sandbox transactions, even
    // when talking to a Production-configured Worker. Retry once in the other
    // environment when Apple reports an environment mismatch.
    if (!isInvalidEnvironment(error)) throw new Error(formatVerificationError(error));
    try {
      return await verifyInEnvironment(jws, env, alternate);
    } catch (retryError) {
      throw new Error(formatVerificationError(retryError));
    }
  }
}

async function verifyInEnvironment(
  jws: string,
  env: Env,
  environment: "Production" | "Sandbox",
): Promise<VerifiedTransaction> {
  const appAppleID = productionAppID(environment, env.APPLE_APP_ID);
  // Cache key includes online-check mode so flipping it does not reuse a stale verifier.
  const cacheKey = `${environment}:${env.APPLE_BUNDLE_ID}:${appAppleID ?? "sandbox"}:offline`;
  let verifier = verifierCache.get(cacheKey);
  if (!verifier) {
    const { Environment, SignedDataVerifier } = await appleLibrary();
    // Online OCSP revocation checks are unreliable in Cloudflare Workers
    // (fetch/OCSP parsing surfaces as RETRYABLE_VERIFICATION_FAILURE). Chain
    // signature verification against Apple Root CA G3 still runs; subscription
    // expiry is enforced below with Date.now().
    verifier = new SignedDataVerifier(
      [Buffer.from(APPLE_ROOT_CA_G3_BASE64, "base64")],
      false,
      environment === "Production" ? Environment.PRODUCTION : Environment.SANDBOX,
      env.APPLE_BUNDLE_ID,
      appAppleID,
    );
    verifierCache.set(cacheKey, verifier);
  }

  const payload = await verifier.verifyAndDecodeTransaction(jws);
  if (payload.productId !== env.SUBSCRIPTION_PRODUCT_ID) throw new Error("wrong product");
  if (payload.revocationDate) throw new Error("subscription revoked");
  if (!payload.expiresDate || payload.expiresDate < Date.now()) throw new Error("subscription expired");
  if (!payload.originalTransactionId || payload.originalTransactionId.length > 128) {
    throw new Error("missing transaction identity");
  }
  return { subject: payload.originalTransactionId, environment };
}

export function productionAppID(environment: "Production" | "Sandbox", value: string | undefined): number | undefined {
  if (environment === "Sandbox") return undefined;
  if (!value || !/^\d{1,15}$/.test(value)) throw new Error("server App Store app ID is not configured");
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) throw new Error("invalid App Store app ID");
  return parsed;
}

/** Apple's VerificationException calls `super()` with no message. */
export function formatVerificationError(error: unknown): string {
  if (error instanceof Error && error.message) return error.message;
  if (error && typeof error === "object" && "status" in error) {
    const status = Number((error as { status: unknown }).status);
    const names: Record<number, string> = {
      1: "VERIFICATION_FAILURE",
      2: "RETRYABLE_VERIFICATION_FAILURE",
      3: "INVALID_APP_IDENTIFIER",
      4: "INVALID_ENVIRONMENT",
      5: "INVALID_CHAIN_LENGTH",
      6: "INVALID_CERTIFICATE",
      7: "FAILURE",
    };
    return `Apple verification failed (${names[status] ?? `status ${status}`})`;
  }
  return "Apple verification failed";
}

function isInvalidEnvironment(error: unknown): boolean {
  return Boolean(
    error &&
      typeof error === "object" &&
      "status" in error &&
      Number((error as { status: unknown }).status) === 4,
  );
}
