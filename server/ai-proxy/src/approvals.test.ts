import { describe, expect, it } from "vitest";
import { actionFingerprint, extractApprovalActions, isExplicitDryRun, isWriteTool, stableStringify } from "./approvals";
import { validateMcpURL } from "./mcp-gateway";
import { formatVerificationError, productionAppID } from "./app-store";

describe("write approval policy", () => {
  it("fails closed for writes and unknown custom tools", () => {
    expect(isWriteTool("product-update")).toBe(true);
    expect(isWriteTool("state_transition")).toBe(true);
    expect(isWriteTool("custom_magic")).toBe(true);
    expect(isWriteTool("product-search")).toBe(false);
    expect(isWriteTool("order_get")).toBe(false);
  });

  it("only treats explicit safe flags as a dry run", () => {
    expect(isExplicitDryRun({ dryRun: true })).toBe(true);
    expect(isExplicitDryRun({ commit: false })).toBe(true);
    expect(isExplicitDryRun({ dryRun: false })).toBe(false);
    expect(isExplicitDryRun({})).toBe(false);
  });

  it("binds approval to canonical arguments but not execution controls", async () => {
    const first = await actionFingerprint("product-update", { id: "1", stock: 3, dryRun: true });
    const second = await actionFingerprint("product-update", { stock: 3, id: "1", commit: true });
    const changed = await actionFingerprint("product-update", { stock: 4, id: "1" });
    expect(first).toBe(second);
    expect(changed).not.toBe(first);
    expect(stableStringify({ z: 1, a: 2 })).toBe('{"a":2,"z":1}');
  });

  it("deduplicates actions and redacts secrets in summaries", async () => {
    const actions = await extractApprovalActions([
      { type: "mcp_tool_use", name: "product-update", input: { id: "1", token: "secret" } },
      { type: "mcp_tool_use", name: "product-update", input: { token: "secret", id: "1" } },
      { type: "mcp_tool_use", name: "product-search", input: { term: "shoe" } },
    ]);
    expect(actions).toHaveLength(1);
    expect(actions[0].summary).toContain("[redacted]");
    expect(actions[0].summary).not.toContain("secret");
  });
});

describe("MCP endpoint validation", () => {
  it("only accepts a public-looking HTTPS Shopware MCP path", () => {
    expect(validateMcpURL("https://shop.example.com/api/_mcp")).toBe("https://shop.example.com/api/_mcp");
    expect(validateMcpURL("http://shop.example.com/api/_mcp")).toBeNull();
    expect(validateMcpURL("https://localhost/api/_mcp")).toBeNull();
    expect(validateMcpURL("https://127.0.0.1/api/_mcp")).toBeNull();
    expect(validateMcpURL("https://shop.example.com/anything")).toBeNull();
    expect(validateMcpURL("https://shop.example.com/api/_mcp?redirect=x")).toBeNull();
  });
});

describe("App Store environment binding", () => {
  it("requires a safe numeric app ID in production only", () => {
    expect(() => productionAppID("Production", undefined)).toThrow();
    expect(() => productionAppID("Production", "not-a-number")).toThrow();
    expect(productionAppID("Production", "1234567890")).toBe(1_234_567_890);
    expect(productionAppID("Sandbox", undefined)).toBeUndefined();
  });

  it("surfaces Apple VerificationException status when message is empty", () => {
    expect(formatVerificationError({ status: 4 })).toBe("Apple verification failed (INVALID_ENVIRONMENT)");
    expect(formatVerificationError(new Error("wrong product"))).toBe("wrong product");
    expect(formatVerificationError({})).toBe("Apple verification failed");
  });
});
