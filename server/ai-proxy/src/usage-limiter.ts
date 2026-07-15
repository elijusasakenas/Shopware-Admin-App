import { DurableObject } from "cloudflare:workers";
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
}

interface BucketRow extends Record<string, SqlStorageValue> {
  requests: number;
  tokens: number;
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
      `);
    });
  }

  async reserve(now: number, limits: UsageLimits): Promise<ReservationResult> {
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
    if (rows[2].row.tokens >= limits.tokensPerMonth) {
      return { allowed: false, retryAfter: secondsUntil(rows[2].expiresAt, now), reason: "Monthly token allowance reached." };
    }

    for (const item of rows) {
      this.ctx.storage.sql.exec(
        `INSERT INTO usage_buckets(bucket, requests, tokens, expires_at) VALUES (?, 1, 0, ?)
         ON CONFLICT(bucket) DO UPDATE SET requests = requests + 1`,
        item.key,
        item.expiresAt,
      );
    }
    this.ctx.storage.sql.exec("DELETE FROM usage_buckets WHERE expires_at < ?", now - 86_400_000);
    return { allowed: true, retryAfter: 0 };
  }

  async recordTokens(now: number, tokens: number): Promise<void> {
    const safeTokens = Math.max(0, Math.min(Math.trunc(tokens), 1_000_000));
    for (const item of [bucket("day", now, 86_400_000), monthBucket(now)]) {
      this.ctx.storage.sql.exec(
        `INSERT INTO usage_buckets(bucket, requests, tokens, expires_at) VALUES (?, 0, ?, ?)
         ON CONFLICT(bucket) DO UPDATE SET tokens = tokens + excluded.tokens`,
        item.key,
        safeTokens,
        item.expiresAt,
      );
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
