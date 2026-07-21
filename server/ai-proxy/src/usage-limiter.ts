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

export interface UsageLimits {
  perMinute: number;
  perDay: number;
  tokensPerMonth: number;
}

export interface ReservationResult {
  allowed: boolean;
  retryAfter: number;
  reason?: string;
  reservationID?: string;
}

interface BucketRow extends Record<string, SqlStorageValue> {
  requests: number;
  tokens: number;
}

interface TokenReservationRow extends Record<string, SqlStorageValue> {
  reservation_id: string;
  day_bucket: string;
  month_bucket: string;
  tokens: number;
  expires_at: number;
}

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
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS usage_buckets (
          bucket TEXT PRIMARY KEY,
          requests INTEGER NOT NULL DEFAULT 0,
          tokens INTEGER NOT NULL DEFAULT 0,
          expires_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS usage_expiry ON usage_buckets(expires_at);
        CREATE TABLE IF NOT EXISTS approval_uses (
          approval_id TEXT PRIMARY KEY,
          used_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS token_reservations (
          reservation_id TEXT PRIMARY KEY,
          day_bucket TEXT NOT NULL,
          month_bucket TEXT NOT NULL,
          tokens INTEGER NOT NULL,
          expires_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS token_reservation_expiry ON token_reservations(expires_at);
        CREATE TABLE IF NOT EXISTS app_attest_challenges (
          challenge TEXT PRIMARY KEY,
          client_id TEXT NOT NULL,
          purpose TEXT NOT NULL,
          expires_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS app_attest_challenge_expiry ON app_attest_challenges(expires_at);
        CREATE TABLE IF NOT EXISTS app_attest_keys (
          key_id TEXT PRIMARY KEY,
          client_id TEXT NOT NULL,
          public_key TEXT NOT NULL,
          receipt TEXT NOT NULL,
          sign_count INTEGER NOT NULL DEFAULT 0,
          environment TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          last_used_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS app_attest_key_client ON app_attest_keys(client_id);
      `);
    });
  }

  async reserve(now: number, limits: UsageLimits, estimatedTokens = 0): Promise<ReservationResult> {
    this.releaseExpiredTokenReservations(now);
    const safeTokens = Math.max(0, Math.min(Math.trunc(estimatedTokens), 1_000_000));
    const minute = bucket("minute", now, 60_000);
    const day = bucket("day", now, 86_400_000);
    const month = monthBucket(now);
    const rows = [minute, day, month].map((item) => ({
      ...item,
      row: this.ctx.storage.sql.exec<BucketRow>(
        "SELECT requests, tokens FROM usage_buckets WHERE bucket = ?",
        item.key,
      ).toArray()[0] ?? { requests: 0, tokens: 0 },
    }));

    if (rows[0].row.requests >= limits.perMinute) {
      return { allowed: false, retryAfter: secondsUntil(rows[0].expiresAt, now), reason: "Minute request limit reached." };
    }
    if (rows[1].row.requests >= limits.perDay) {
      return { allowed: false, retryAfter: secondsUntil(rows[1].expiresAt, now), reason: "Daily request limit reached." };
    }
    if (rows[2].row.tokens + safeTokens > limits.tokensPerMonth) {
      return { allowed: false, retryAfter: secondsUntil(rows[2].expiresAt, now), reason: "Monthly token allowance reached." };
    }

    const reservationID = safeTokens > 0 ? crypto.randomUUID() : undefined;
    this.ctx.storage.transactionSync(() => {
      for (const item of rows) {
        const tokens = item.key === day.key || item.key === month.key ? safeTokens : 0;
        this.ctx.storage.sql.exec(
          `INSERT INTO usage_buckets(bucket, requests, tokens, expires_at) VALUES (?, 1, ?, ?)
           ON CONFLICT(bucket) DO UPDATE SET requests = requests + 1, tokens = tokens + excluded.tokens`,
          item.key,
          tokens,
          item.expiresAt,
        );
      }
      if (reservationID) {
        this.ctx.storage.sql.exec(
          `INSERT INTO token_reservations(reservation_id, day_bucket, month_bucket, tokens, expires_at)
           VALUES (?, ?, ?, ?, ?)`,
          reservationID,
          day.key,
          month.key,
          safeTokens,
          now + 15 * 60_000,
        );
      }
    });
    this.ctx.storage.sql.exec("DELETE FROM usage_buckets WHERE expires_at < ?", now - 86_400_000);
    return { allowed: true, retryAfter: 0, reservationID };
  }

  async settleTokens(reservationID: string, actualTokens: number): Promise<boolean> {
    if (!/^[0-9a-f-]{36}$/.test(reservationID)) return false;
    const reservation = this.ctx.storage.sql.exec<TokenReservationRow>(
      `SELECT reservation_id, day_bucket, month_bucket, tokens, expires_at
       FROM token_reservations WHERE reservation_id = ?`,
      reservationID,
    ).toArray()[0];
    if (!reservation) return false;
    const safeActual = Math.max(0, Math.min(Math.trunc(actualTokens), 1_000_000));
    const adjustment = safeActual - reservation.tokens;
    this.ctx.storage.transactionSync(() => {
      for (const key of [reservation.day_bucket, reservation.month_bucket]) {
        this.ctx.storage.sql.exec("UPDATE usage_buckets SET tokens = MAX(0, tokens + ?) WHERE bucket = ?", adjustment, key);
      }
      this.ctx.storage.sql.exec("DELETE FROM token_reservations WHERE reservation_id = ?", reservationID);
    });
    return true;
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
    if (!/^[a-f0-9:-]{36,140}$/.test(approvalID)) return false;
    const exists = this.ctx.storage.sql.exec<{ value: number }>(
      "SELECT 1 AS value FROM approval_uses WHERE approval_id = ?",
      approvalID,
    ).toArray().length > 0;
    if (exists) return false;
    this.ctx.storage.sql.exec("INSERT INTO approval_uses(approval_id, used_at) VALUES (?, ?)", approvalID, now);
    this.ctx.storage.sql.exec("DELETE FROM approval_uses WHERE used_at < ?", now - 86_400_000);
    return true;
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

  private releaseExpiredTokenReservations(now: number): void {
    const expired = this.ctx.storage.sql.exec<TokenReservationRow>(
      `SELECT reservation_id, day_bucket, month_bucket, tokens, expires_at
       FROM token_reservations WHERE expires_at < ?`,
      now,
    ).toArray();
    for (const reservation of expired) {
      this.ctx.storage.transactionSync(() => {
        for (const key of [reservation.day_bucket, reservation.month_bucket]) {
          this.ctx.storage.sql.exec(
            "UPDATE usage_buckets SET tokens = MAX(0, tokens - ?) WHERE bucket = ?",
            reservation.tokens,
            key,
          );
        }
        this.ctx.storage.sql.exec("DELETE FROM token_reservations WHERE reservation_id = ?", reservation.reservation_id);
      });
    }
  }
}

function validClientID(value: string): boolean {
  return value.length >= 16 && value.length <= 128 && /^[A-Za-z0-9._-]+$/.test(value);
}

function bucket(prefix: string, now: number, duration: number): { key: string; expiresAt: number } {
  const start = Math.floor(now / duration) * duration;
  return { key: `${prefix}:${start}`, expiresAt: start + duration };
}

function monthBucket(now: number): { key: string; expiresAt: number } {
  const date = new Date(now);
  const year = date.getUTCFullYear();
  const month = date.getUTCMonth();
  return {
    key: `month:${year}-${String(month + 1).padStart(2, "0")}`,
    expiresAt: Date.UTC(year, month + 1, 1),
  };
}

function secondsUntil(timestamp: number, now: number): number {
  return Math.max(1, Math.ceil((timestamp - now) / 1000));
}
