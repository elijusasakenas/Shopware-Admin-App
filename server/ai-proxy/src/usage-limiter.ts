import { DurableObject } from "cloudflare:workers";
import {
  APP_ATTEST_CHALLENGE_TTL_MS,
  APP_ATTEST_MAX_KEYS_PER_CLIENT,
  base64URLEncode,
  decodeAppAttestObject,
  type AppAttestPurpose,
  validAppAttestChallenge,
  validAppAttestKeyID,
  verifyAppAssertion,
  verifyAppAttestation,
} from "./app-attest";
import type { Env } from "./types";
import { USAGE_LIMITER_SCHEMA, UsageStore, type ReservationResult, type UsageLimits, type UsageSql } from "./usage-store";

export type { ReservationResult, UsageLimits };
export { USAGE_LIMITER_SCHEMA, UsageStore };

interface AppAttestChallengeRow extends Record<string, SqlStorageValue> {
  client_id: string;
  purpose: string;
  expires_at: number;
}

interface AppAttestKeyRow extends Record<string, SqlStorageValue> {
  client_id: string;
  public_key: string;
  sign_count: number;
}

/** One strongly-consistent object per App Store original transaction ID. */
export class UsageLimiter extends DurableObject<Env> {
  private readonly store: UsageStore;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.store = new UsageStore(
      this.ctx.storage.sql as unknown as UsageSql,
      (closure) => this.ctx.storage.transactionSync(closure),
    );
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(USAGE_LIMITER_SCHEMA);
    });
  }

  async reserve(now: number, limits: UsageLimits, estimatedTokens = 0): Promise<ReservationResult> {
    return this.store.reserve(now, limits, estimatedTokens);
  }

  async settleTokens(reservationID: string, actualTokens: number): Promise<boolean> {
    return this.store.settleTokens(reservationID, actualTokens);
  }

  async issueAppAttestChallenge(clientID: string, purpose: AppAttestPurpose, now: number): Promise<{
    challenge: string;
    expiresAt: number;
  }> {
    if (!validClientID(clientID) || !["attestation", "chat"].includes(purpose)) {
      throw new Error("Invalid App Attest challenge request.");
    }
    const random = new Uint8Array(32);
    crypto.getRandomValues(random);
    const challenge = base64URLEncode(random);
    const expiresAt = now + APP_ATTEST_CHALLENGE_TTL_MS;
    this.ctx.storage.sql.exec("DELETE FROM app_attest_challenges WHERE expires_at < ?", now);
    const outstanding = this.ctx.storage.sql.exec<{ count: number }>(
      "SELECT COUNT(*) AS count FROM app_attest_challenges WHERE client_id = ?",
      clientID,
    ).toArray()[0]?.count ?? 0;
    const totalOutstanding = this.ctx.storage.sql.exec<{ count: number }>(
      "SELECT COUNT(*) AS count FROM app_attest_challenges",
    ).toArray()[0]?.count ?? 0;
    if (outstanding >= 20 || totalOutstanding >= 100) {
      throw new Error("Too many outstanding App Attest challenges.");
    }
    this.ctx.storage.sql.exec(
      "INSERT INTO app_attest_challenges(challenge, client_id, purpose, expires_at) VALUES (?, ?, ?, ?)",
      challenge,
      clientID,
      purpose,
      expiresAt,
    );
    return { challenge, expiresAt };
  }

  async registerAppAttestKey(
    clientID: string,
    keyID: string,
    challenge: string,
    attestation: string,
    now: number,
  ): Promise<boolean> {
    if (!validClientID(clientID) || !validAppAttestKeyID(keyID) || !validAppAttestChallenge(challenge)) return false;
    if (!this.consumeAppAttestChallenge(clientID, challenge, "attestation", now)) return false;
    try {
      const existing = this.ctx.storage.sql.exec<{ value: number }>(
        "SELECT 1 AS value FROM app_attest_keys WHERE key_id = ?",
        keyID,
      ).toArray()[0];
      if (existing) return false;
      const count = this.ctx.storage.sql.exec<{ count: number }>(
        "SELECT COUNT(*) AS count FROM app_attest_keys WHERE client_id = ?",
        clientID,
      ).toArray()[0]?.count ?? 0;
      if (count >= APP_ATTEST_MAX_KEYS_PER_CLIENT) return false;
      const verified = verifyAppAttestation(decodeAppAttestObject(attestation), challenge, keyID, this.env);
      this.ctx.storage.sql.exec(
        `INSERT INTO app_attest_keys(key_id, client_id, public_key, receipt, sign_count, environment, created_at, last_used_at)
         VALUES (?, ?, ?, ?, 0, ?, ?, ?)`,
        keyID,
        clientID,
        verified.publicKey,
        verified.receipt,
        verified.environment,
        now,
        now,
      );
      return true;
    } catch {
      return false;
    }
  }

  async hasAppAttestKey(clientID: string, keyID: string): Promise<boolean> {
    if (!validClientID(clientID) || !validAppAttestKeyID(keyID)) return false;
    return this.ctx.storage.sql.exec<{ value: number }>(
      "SELECT 1 AS value FROM app_attest_keys WHERE key_id = ? AND client_id = ?",
      keyID,
      clientID,
    ).toArray().length > 0;
  }

  async verifyAppAttestAssertion(
    clientID: string,
    keyID: string,
    challenge: string,
    assertion: string,
    payload: Uint8Array,
    now: number,
  ): Promise<boolean> {
    if (!validClientID(clientID) || !validAppAttestKeyID(keyID) || !validAppAttestChallenge(challenge)) return false;
    if (!this.consumeAppAttestChallenge(clientID, challenge, "chat", now)) return false;
    const key = this.ctx.storage.sql.exec<AppAttestKeyRow>(
      "SELECT client_id, public_key, sign_count FROM app_attest_keys WHERE key_id = ?",
      keyID,
    ).toArray()[0];
    if (!key || key.client_id !== clientID) return false;
    try {
      const signCount = verifyAppAssertion(
        decodeAppAttestObject(assertion),
        payload,
        key.public_key,
        key.sign_count,
        this.env,
      );
      this.ctx.storage.sql.exec(
        "UPDATE app_attest_keys SET sign_count = ?, last_used_at = ? WHERE key_id = ?",
        signCount,
        now,
        keyID,
      );
      return true;
    } catch {
      return false;
    }
  }

  async consumeApproval(approvalID: string, now: number): Promise<boolean> {
    return this.store.consumeApproval(approvalID, now);
  }

  private consumeAppAttestChallenge(
    clientID: string,
    challenge: string,
    purpose: AppAttestPurpose,
    now: number,
  ): boolean {
    const row = this.ctx.storage.sql.exec<AppAttestChallengeRow>(
      "SELECT client_id, purpose, expires_at FROM app_attest_challenges WHERE challenge = ?",
      challenge,
    ).toArray()[0];
    this.ctx.storage.sql.exec("DELETE FROM app_attest_challenges WHERE challenge = ?", challenge);
    return row?.client_id === clientID && row.purpose === purpose && row.expires_at >= now;
  }
}

function validClientID(value: string): boolean {
  return value.length >= 16 && value.length <= 128 && /^[A-Za-z0-9._-]+$/.test(value);
}
