import { describe, expect, it } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { USAGE_LIMITER_SCHEMA, UsageStore, type UsageLimits, type UsageSql } from "./usage-store";

const limits: UsageLimits = { perMinute: 20, perDay: 500, tokensPerMonth: 2_000_000 };

describe("UsageLimiter reservation ledger", () => {
  it("settles unused reserved tokens back off the monthly bucket", async () => {
    const { store, tokensIn } = openStore();
    const now = Date.UTC(2026, 7, 27, 12);

    const reserved = await store.reserve(now, limits, 1_000);
    expect(reserved.allowed).toBe(true);
    expect(reserved.reservationID).toMatch(/^[0-9a-f-]{36}$/);
    expect(tokensIn("month", now)).toBe(1_000);
    expect(tokensIn("day", now)).toBe(1_000);

    expect(await store.settleTokens(reserved.reservationID!, 120)).toBe(true);
    expect(tokensIn("month", now)).toBe(120);
    expect(tokensIn("day", now)).toBe(120);
    expect(await store.settleTokens(reserved.reservationID!, 50)).toBe(false);
  });

  it("rejects unknown or malformed reservation IDs", async () => {
    const { store } = openStore();
    expect(await store.settleTokens("not-a-uuid", 10)).toBe(false);
    expect(await store.settleTokens("00000000-0000-0000-0000-000000000000", 10)).toBe(false);
  });

  it("consumes an approval grant only once", async () => {
    const { store } = openStore();
    const grant = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee:abc123";
    expect(await store.consumeApproval(grant, 1_000)).toBe(true);
    expect(await store.consumeApproval(grant, 1_001)).toBe(false);
    expect(await store.consumeApproval("short", 1_000)).toBe(false);
  });

  it("blocks a reserve that would exceed the monthly token allowance", async () => {
    const { store } = openStore();
    const now = Date.UTC(2026, 7, 27, 12);
    const tight: UsageLimits = { perMinute: 20, perDay: 500, tokensPerMonth: 500 };

    const first = await store.reserve(now, tight, 400);
    expect(first.allowed).toBe(true);
    const second = await store.reserve(now, tight, 200);
    expect(second.allowed).toBe(false);
    expect(second.reason).toBe("Monthly token allowance reached.");
  });
});

function openStore() {
  const db = new DatabaseSync(":memory:");
  db.exec(USAGE_LIMITER_SCHEMA);
  const sql: UsageSql = {
    exec(query: string, ...bindings: Array<string | number | boolean | null>) {
      const statement = db.prepare(query);
      if (/^\s*SELECT/i.test(query)) {
        return { toArray: () => statement.all(...(bindings as never[])) as Array<Record<string, string | number | boolean | null>> };
      }
      statement.run(...(bindings as never[]));
      return { toArray: () => [] };
    },
  };
  const store = new UsageStore(sql, (closure) => {
    db.exec("BEGIN");
    try {
      closure();
      db.exec("COMMIT");
    } catch (error) {
      db.exec("ROLLBACK");
      throw error;
    }
  });

  return {
    store,
    tokensIn(kind: "day" | "month", now: number): number {
      const key = kind === "month"
        ? monthKey(now)
        : `day:${Math.floor(now / 86_400_000) * 86_400_000}`;
      return Number(sql.exec(
        "SELECT tokens FROM usage_buckets WHERE bucket = ?",
        key,
      ).toArray()[0]?.tokens ?? 0);
    },
  };
}

function monthKey(now: number): string {
  const date = new Date(now);
  return `month:${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}
