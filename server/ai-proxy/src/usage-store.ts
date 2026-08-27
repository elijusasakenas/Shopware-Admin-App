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

export const USAGE_LIMITER_SCHEMA = `
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
      `;

type SqlValue = string | number | boolean | null;

export interface UsageSql {
  exec(query: string, ...bindings: SqlValue[]): { toArray(): Array<Record<string, SqlValue>> };
}

interface BucketRow extends Record<string, SqlValue> {
  requests: number;
  tokens: number;
}

interface TokenReservationRow extends Record<string, SqlValue> {
  reservation_id: string;
  day_bucket: string;
  month_bucket: string;
  tokens: number;
  expires_at: number;
}

/** SQLite ledger used by the Durable Object, extracted so Vitest can drive it. */
export class UsageStore {
  constructor(
    private readonly sql: UsageSql,
    private readonly transactionSync: (closure: () => void) => void,
  ) {}

  async reserve(now: number, limits: UsageLimits, estimatedTokens = 0): Promise<ReservationResult> {
    this.releaseExpiredTokenReservations(now);
    const safeTokens = Math.max(0, Math.min(Math.trunc(estimatedTokens), 1_000_000));
    const minute = bucket("minute", now, 60_000);
    const day = bucket("day", now, 86_400_000);
    const month = monthBucket(now);
    const rows = [minute, day, month].map((item) => ({
      ...item,
      row: (this.sql.exec(
        "SELECT requests, tokens FROM usage_buckets WHERE bucket = ?",
        item.key,
      ).toArray()[0] ?? { requests: 0, tokens: 0 }) as BucketRow,
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
    this.transactionSync(() => {
      for (const item of rows) {
        const tokens = item.key === day.key || item.key === month.key ? safeTokens : 0;
        this.sql.exec(
          `INSERT INTO usage_buckets(bucket, requests, tokens, expires_at) VALUES (?, 1, ?, ?)
           ON CONFLICT(bucket) DO UPDATE SET requests = requests + 1, tokens = tokens + excluded.tokens`,
          item.key,
          tokens,
          item.expiresAt,
        );
      }
      if (reservationID) {
        this.sql.exec(
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
    this.sql.exec("DELETE FROM usage_buckets WHERE expires_at < ?", now - 86_400_000);
    return { allowed: true, retryAfter: 0, reservationID };
  }

  async settleTokens(reservationID: string, actualTokens: number): Promise<boolean> {
    if (!/^[0-9a-f-]{36}$/.test(reservationID)) return false;
    const reservation = this.sql.exec(
      `SELECT reservation_id, day_bucket, month_bucket, tokens, expires_at
       FROM token_reservations WHERE reservation_id = ?`,
      reservationID,
    ).toArray()[0] as TokenReservationRow | undefined;
    if (!reservation) return false;
    const safeActual = Math.max(0, Math.min(Math.trunc(actualTokens), 1_000_000));
    const adjustment = safeActual - reservation.tokens;
    this.transactionSync(() => {
      for (const key of [reservation.day_bucket, reservation.month_bucket]) {
        this.sql.exec("UPDATE usage_buckets SET tokens = MAX(0, tokens + ?) WHERE bucket = ?", adjustment, key);
      }
      this.sql.exec("DELETE FROM token_reservations WHERE reservation_id = ?", reservationID);
    });
    return true;
  }

  async consumeApproval(approvalID: string, now: number): Promise<boolean> {
    if (!/^[a-f0-9:-]{36,140}$/.test(approvalID)) return false;
    const exists = this.sql.exec(
      "SELECT 1 AS value FROM approval_uses WHERE approval_id = ?",
      approvalID,
    ).toArray().length > 0;
    if (exists) return false;
    this.sql.exec("INSERT INTO approval_uses(approval_id, used_at) VALUES (?, ?)", approvalID, now);
    this.sql.exec("DELETE FROM approval_uses WHERE used_at < ?", now - 86_400_000);
    return true;
  }

  private releaseExpiredTokenReservations(now: number): void {
    const expired = this.sql.exec(
      `SELECT reservation_id, day_bucket, month_bucket, tokens, expires_at
       FROM token_reservations WHERE expires_at < ?`,
      now,
    ).toArray() as TokenReservationRow[];
    for (const reservation of expired) {
      this.transactionSync(() => {
        for (const key of [reservation.day_bucket, reservation.month_bucket]) {
          this.sql.exec(
            "UPDATE usage_buckets SET tokens = MAX(0, tokens - ?) WHERE bucket = ?",
            reservation.tokens,
            key,
          );
        }
        this.sql.exec("DELETE FROM token_reservations WHERE reservation_id = ?", reservation.reservation_id);
      });
    }
  }
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
