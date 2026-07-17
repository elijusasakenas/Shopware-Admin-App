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
  const environment = (env.APPLE_ENVIRONMENT as "Production" | "Sandbox" | undefined) ?? "Production";
  const appAppleID = productionAppID(environment, env.APPLE_APP_ID);
  const cacheKey = `${environment}:${env.APPLE_BUNDLE_ID}:${appAppleID ?? "sandbox"}`;
  let verifier = verifierCache.get(cacheKey);
  if (!verifier) {
    const { Environment, SignedDataVerifier } = await appleLibrary();
    verifier = new SignedDataVerifier(
      [Buffer.from(APPLE_ROOT_CA_G3_BASE64, "base64")],
      true,
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
