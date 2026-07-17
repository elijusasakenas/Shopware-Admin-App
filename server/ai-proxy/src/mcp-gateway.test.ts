import { afterEach, describe, expect, it, vi } from "vitest";
import { verifyMcpEndpoint } from "./mcp-gateway";

describe("Shopware MCP preflight", () => {
  afterEach(() => vi.unstubAllGlobals());

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
});
