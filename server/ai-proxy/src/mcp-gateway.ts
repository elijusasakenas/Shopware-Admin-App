import { actionFingerprint, isExplicitDryRun, isWriteTool } from "./approvals";
import { openToken, sha256 } from "./crypto-tokens";
import { HTTPError, readJSON, readResponseText, securityHeaders } from "./http";
import type { CapabilityPayload, Env } from "./types";

interface JSONRPCRequest {
  jsonrpc?: unknown;
  id?: unknown;
  method?: unknown;
  params?: { name?: unknown; arguments?: unknown };
}

export function validateMcpURL(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 2048) return null;
  try {
    const url = new URL(value);
    const hostname = url.hostname.toLowerCase();
    if (url.protocol !== "https:" || !url.pathname.endsWith("/api/_mcp")) return null;
    if (url.search || url.hash || url.username || url.password || url.port) return null;
    if (
      hostname === "localhost" || hostname.endsWith(".localhost") || hostname.endsWith(".local") ||
      hostname.endsWith(".internal") || /^\d{1,3}(\.\d{1,3}){3}$/.test(hostname) || hostname.includes(":")
    ) return null;
    return url.toString();
  } catch {
    return null;
  }
}

export async function verifyMcpEndpoint(mcpURL: string, token: string): Promise<void> {
  const response = await fetch(mcpURL, {
    method: "POST",
    headers: {
      "Accept": "application/json, text/event-stream",
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: "shopware-app-preflight",
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "ShopwareApp AI gateway", version: "1.0" },
      },
    }),
    // Workers does not implement RequestRedirect "error". Manual mode keeps
    // redirects visible so the gateway can reject them without forwarding a
    // Shopware bearer token to a different destination.
    redirect: "manual",
  });
  if (isRedirect(response.status)) throw new HTTPError(400, "The Shopware MCP endpoint must not redirect.");
  const text = await readResponseText(response);
  if (!response.ok) throw new HTTPError(400, `Shopware MCP preflight failed (${response.status}).`);
  if (!text.includes('"jsonrpc"') || !text.includes('"result"')) {
    throw new HTTPError(400, "The URL did not return a valid MCP initialize response.");
  }
}

export async function handleMcpGateway(request: Request, env: Env): Promise<Response> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new HTTPError(401, "Missing MCP capability.");
  const capability = await openToken<CapabilityPayload>(authorization.slice(7), env.CAPABILITY_SECRET);
  if (capability.kind !== "mcp-capability" || capability.expiresAt < Date.now()) {
    throw new HTTPError(401, "MCP capability expired.");
  }
  if (!validateMcpURL(capability.upstreamURL)) throw new HTTPError(401, "Invalid MCP capability.");

  let body: Uint8Array | undefined;
  if (request.method === "POST") {
    const rpc = await readJSON<JSONRPCRequest>(request, 262_144);
    if (rpc.method === "tools/call") {
      const name = rpc.params?.name;
      if (typeof name !== "string" || name.length > 300) throw new HTTPError(400, "Invalid MCP tool call.");
      const input = rpc.params?.arguments ?? {};
      if (isWriteTool(name) && !isExplicitDryRun(input)) {
        const fingerprint = await actionFingerprint(name, input);
        const grant = capability.approvalGrants[fingerprint];
        if (!grant) return blockedToolResponse(rpc.id, name);
        const limiter = env.USAGE_LIMITER.getByName(await sha256(capability.subject));
        if (!(await limiter.consumeApproval(grant, Date.now()))) return blockedToolResponse(rpc.id, name);
      }
    }
    body = new TextEncoder().encode(JSON.stringify(rpc));
  }

  const headers = new Headers();
  headers.set("Authorization", `Bearer ${capability.upstreamToken}`);
  headers.set("Accept", request.headers.get("accept") ?? "application/json, text/event-stream");
  if (body) headers.set("Content-Type", "application/json");
  for (const name of ["Mcp-Session-Id", "MCP-Protocol-Version", "Last-Event-ID"]) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }
  const upstream = await fetch(capability.upstreamURL, {
    method: request.method,
    headers,
    body,
    redirect: "manual",
  });
  if (isRedirect(upstream.status)) {
    await upstream.body?.cancel();
    throw new HTTPError(502, "The Shopware MCP endpoint attempted to redirect.");
  }
  const responseHeaders = new Headers();
  for (const name of ["content-type", "mcp-session-id", "retry-after"]) {
    const value = upstream.headers.get(name);
    if (value) responseHeaders.set(name, value);
  }
  for (const [key, value] of Object.entries(securityHeaders())) responseHeaders.set(key, value);
  return new Response(upstream.body, { status: upstream.status, headers: responseHeaders });
}

function isRedirect(status: number): boolean {
  return status >= 300 && status < 400;
}

function blockedToolResponse(id: unknown, name: string): Response {
  return Response.json({
    jsonrpc: "2.0",
    id: id ?? null,
    result: {
      content: [{
        type: "text",
        text: `The ${name} write was blocked by the Shopware App approval gateway. Native user approval is required before retrying this exact action.`,
      }],
      isError: true,
    },
  }, { headers: securityHeaders() });
}
