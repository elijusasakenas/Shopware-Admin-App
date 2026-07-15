import { sha256 } from "./crypto-tokens";
import type { ApprovalAction } from "./types";

const READ_WORDS = new Set([
  "aggregate", "count", "describe", "fetch", "find", "get", "inspect", "list", "preview",
  "query", "read", "schema", "search", "status", "validate",
]);
const WRITE_WORDS = new Set([
  "activate", "change", "clear", "commit", "configure", "create", "deactivate", "delete",
  "execute", "import", "patch", "remove", "set", "sync", "toggle", "transition", "update",
  "upload", "write",
]);
const CONTROL_KEYS = new Set([
  "approve", "approved", "commit", "confirm", "confirmed", "dryRun", "dry_run", "execute",
]);

export function isWriteTool(name: string): boolean {
  const words = name.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
  if (words.some((word) => WRITE_WORDS.has(word))) return true;
  if (words.some((word) => READ_WORDS.has(word))) return false;
  // Unknown custom tools fail closed. A merchant can explicitly expose a
  // read verb in its tool name to make the intent machine-verifiable.
  return true;
}

export function isExplicitDryRun(input: unknown): boolean {
  if (!isRecord(input)) return false;
  return input.dry_run === true || input.dryRun === true || input.commit === false || input.execute === false;
}

export async function actionFingerprint(tool: string, input: unknown): Promise<string> {
  return sha256(`${tool}\n${stableStringify(stripControlFields(input))}`);
}

export async function extractApprovalActions(content: unknown): Promise<ApprovalAction[]> {
  if (!Array.isArray(content)) return [];
  const actions: ApprovalAction[] = [];
  const seen = new Set<string>();
  for (const block of content) {
    if (!isRecord(block) || block.type !== "mcp_tool_use" || typeof block.name !== "string") continue;
    if (!isWriteTool(block.name)) continue;
    const fingerprint = await actionFingerprint(block.name, block.input ?? {});
    if (seen.has(fingerprint)) continue;
    seen.add(fingerprint);
    actions.push({ fingerprint, tool: block.name, summary: summarizeAction(block.name, block.input ?? {}) });
  }
  return actions.slice(0, 8);
}

export function summarizeAction(tool: string, input: unknown): string {
  const safe = redact(input);
  const detail = stableStringify(safe);
  return detail === "{}" ? tool : `${tool}: ${detail.slice(0, 600)}`;
}

export function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const object = value as Record<string, unknown>;
  return `{${Object.keys(object).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(object[key])}`).join(",")}}`;
}

function stripControlFields(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stripControlFields);
  if (!isRecord(value)) return value;
  return Object.fromEntries(
    Object.entries(value)
      .filter(([key]) => !CONTROL_KEYS.has(key))
      .map(([key, child]) => [key, stripControlFields(child)]),
  );
}

function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (!isRecord(value)) return value;
  return Object.fromEntries(Object.entries(value).map(([key, child]) => {
    const lower = key.toLowerCase();
    if (["authorization", "password", "secret", "token", "apikey", "api_key"].some((part) => lower.includes(part))) {
      return [key, "[redacted]"];
    }
    return [key, redact(child)];
  }));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
