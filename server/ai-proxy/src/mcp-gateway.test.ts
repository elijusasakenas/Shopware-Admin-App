import { afterEach, describe, expect, it, vi } from "vitest";
import { actionFingerprint } from "./approvals";
import { sealToken } from "./crypto-tokens";
import { handleMcpGateway, clearMcpPreflightCacheForTests, verifyMcpEndpoint } from "./mcp-gateway";
import type { CapabilityPayload, Env } from "./types";

describe("Shopware MCP preflight", () => {
  afterEach(() => {
    clearMcpPreflightCacheForTests();
    vi.unstubAllGlobals();
  });

  it("uses Workers-supported manual redirects and rejects redirect responses", async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(null, {
      status: 302,
      headers: { Location: "https://other.example.com/api/_mcp" },
    }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(verifyMcpEndpoint("https://shop.example.com/api/_mcp", "shop-token"))
      .rejects.toMatchObject({ status: 400, message: "The Shopware MCP endpoint must not redirect." });
    expect(fetchMock).toHaveBeenCalledWith(
      "https://shop.example.com/api/_mcp",
      expect.objectContaining({ redirect: "manual" }),
    );
  });

  it("accepts a valid initialize response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({
      jsonrpc: "2.0",
      id: "shopware-app-preflight",
      result: { protocolVersion: "2025-06-18" },
    })));

    await expect(verifyMcpEndpoint("https://shop.example.com/api/_mcp", "shop-token"))
      .resolves.toBeUndefined();
  });

  it("skips a second initialize when the same endpoint was just verified", async () => {
    const fetchMock = vi.fn().mockResolvedValue(Response.json({
      jsonrpc: "2.0",
      id: "shopware-app-preflight",
      result: { protocolVersion: "2025-06-18" },
    }));
    vi.stubGlobal("fetch", fetchMock);

    await verifyMcpEndpoint("https://shop.example.com/api/_mcp", "shop-token");
    await verifyMcpEndpoint("https://shop.example.com/api/_mcp", "shop-token");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

describe("MCP write gateway", () => {
  const secret = "c".repeat(32);

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("blocks an unapproved write without calling Shopware", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const env = gatewayEnv(secret, async () => true);
    const token = await capabilityToken(secret);

    const response = await handleMcpGateway(toolCall(token, "product-update", { id: "1" }), env);
    const body = await response.json() as { result?: { isError?: boolean; content?: { text?: string }[] } };

    expect(fetchMock).not.toHaveBeenCalled();
    expect(body.result?.isError).toBe(true);
    expect(body.result?.content?.[0]?.text).toContain("blocked");
  });

  it("forwards a write after consuming a matching approval grant", async () => {
    const fetchMock = vi.fn().mockResolvedValue(Response.json({
      jsonrpc: "2.0",
      id: 1,
      result: { content: [{ type: "text", text: "updated" }] },
    }));
    vi.stubGlobal("fetch", fetchMock);
    const consumeApproval = vi.fn().mockResolvedValue(true);
    const env = gatewayEnv(secret, consumeApproval);
    const fingerprint = await actionFingerprint("product-update", { id: "1" });
    const grant = `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee:${fingerprint}`;
    const token = await capabilityToken(secret, { [fingerprint]: grant });

    const response = await handleMcpGateway(toolCall(token, "product-update", { id: "1" }), env);
    const body = await response.json() as { result?: { content?: { text?: string }[] } };

    expect(consumeApproval).toHaveBeenCalledWith(grant, expect.any(Number));
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0][1]).toEqual(expect.objectContaining({
      method: "POST",
      redirect: "manual",
    }));
    expect((fetchMock.mock.calls[0][1].headers as Headers).get("Authorization")).toBe("Bearer shop-token");
    expect(body.result?.content?.[0]?.text).toBe("updated");
  });

  it("blocks a write when the matching grant was already consumed", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const env = gatewayEnv(secret, async () => false);
    const fingerprint = await actionFingerprint("product-update", { id: "1" });
    const token = await capabilityToken(secret, {
      [fingerprint]: `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee:${fingerprint}`,
    });

    const response = await handleMcpGateway(toolCall(token, "product-update", { id: "1" }), env);
    const body = await response.json() as { result?: { isError?: boolean } };

    expect(fetchMock).not.toHaveBeenCalled();
    expect(body.result?.isError).toBe(true);
  });

  it("rejects an expired capability before any upstream call", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const env = gatewayEnv(secret, async () => true);
    const token = await capabilityToken(secret, {}, Date.now() - 1_000);

    await expect(handleMcpGateway(toolCall(token, "product-search", { term: "mug" }), env))
      .rejects.toMatchObject({ status: 401, message: "MCP capability expired." });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("lets an explicit dry-run write skip the approval gate", async () => {
    const fetchMock = vi.fn().mockResolvedValue(Response.json({
      jsonrpc: "2.0",
      id: 1,
      result: { content: [{ type: "text", text: "preview" }] },
    }));
    vi.stubGlobal("fetch", fetchMock);
    const consumeApproval = vi.fn();
    const env = gatewayEnv(secret, consumeApproval);
    const token = await capabilityToken(secret);

    await handleMcpGateway(toolCall(token, "product-update", { id: "1", commit: false }), env);

    expect(consumeApproval).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

async function capabilityToken(
  secret: string,
  approvalGrants: Record<string, string> = {},
  expiresAt = Date.now() + 60_000,
): Promise<string> {
  const payload: CapabilityPayload = {
    kind: "mcp-capability",
    upstreamURL: "https://shop.example.com/api/_mcp",
    upstreamToken: "shop-token",
    approvalGrants,
    subject: "original-transaction-id",
    clientID: "client-1",
    expiresAt,
  };
  return sealToken(payload, secret);
}

function toolCall(token: string, name: string, args: Record<string, unknown>): Request {
  return new Request("https://proxy.example/v1/mcp", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name, arguments: args },
    }),
  });
}

function gatewayEnv(secret: string, consumeApproval: (id: string, now: number) => Promise<boolean>): Env {
  return {
    CAPABILITY_SECRET: secret,
    USAGE_LIMITER: {
      getByName() {
        return { consumeApproval };
      },
    },
  } as unknown as Env;
}
