import { extractApprovalActions } from "./approvals";
import { verifyAppStoreTransaction } from "./app-store";
import { openToken, sealToken, sha256 } from "./crypto-tokens";
import { errorResponse, HTTPError, jsonResponse, logEvent, readJSON, readResponseText } from "./http";
import { handleMcpGateway, validateMcpURL, verifyMcpEndpoint } from "./mcp-gateway";
import type { ApprovalChallenge, ApprovalPayload, CapabilityPayload, Env } from "./types";
export { UsageLimiter } from "./usage-limiter";

const SYSTEM_PROMPT = `You are the AI assistant inside a Shopware merchant app. Use the connected Shopware MCP server instead of guessing and look up entities before acting.

Write operations are protected by a native approval gateway. First explain the exact proposed change. You may use an explicit dry-run when the tool supports it. A commit without approval will be blocked. After the user approves in the app, retry the exact same tool name and arguments once. Never claim a change succeeded unless its tool result confirms success.

Be concise and practical. Answer in the user's language. Prefer readable summaries over raw data. If a request is ambiguous, show candidates and ask the user to choose.`;
const MAX_MESSAGES = 120;
const MAX_MCP_TOKEN = 8_192;
const MAX_CLIENT_ID = 128;

interface ChatBody {
  messages?: unknown;
  mcp_url?: unknown;
  mcp_token?: unknown;
  client_id?: unknown;
  approval_token?: unknown;
}

interface CapabilityBody {
  mcp_url?: unknown;
  mcp_token?: unknown;
  client_id?: unknown;
  approval_token?: unknown;
}

interface ApprovalBody {
  content?: unknown;
  mcp_url?: unknown;
  client_id?: unknown;
  approval_token?: unknown;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const requestID = crypto.randomUUID();
    const startedAt = Date.now();
    let response: Response;
    try {
      const url = new URL(request.url);
      if (request.method === "GET" && url.pathname === "/health") {
        response = jsonResponse({ ok: true, enabled: featureEnabled(env) }, {}, requestID);
      } else if (request.method === "GET" && url.pathname === "/v1/config") {
        response = jsonResponse({ enabled: featureEnabled(env) }, {}, requestID);
      } else if (request.method === "POST" && url.pathname === "/v1/chat") {
        response = await handleChat(request, env, requestID);
      } else if (request.method === "POST" && url.pathname === "/v1/capability") {
        response = await handleDirectCapability(request, env, requestID);
      } else if (request.method === "POST" && url.pathname === "/v1/approval") {
        response = await handleDirectApproval(request, env, requestID);
      } else if (["GET", "POST", "DELETE"].includes(request.method) && url.pathname === "/v1/mcp") {
        response = await handleMcpGateway(request, env);
      } else {
        response = errorResponse(404, "Not found.", requestID);
      }
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const publicMessage = error instanceof HTTPError ? error.message : "Unexpected server error.";
      logEvent("error", "request_failed", { requestID, status, error: String(error) });
      response = errorResponse(status, publicMessage, requestID);
    }
    logEvent("info", "request_completed", {
      requestID,
      method: request.method,
      path: new URL(request.url).pathname,
      status: response.status,
      durationMs: Date.now() - startedAt,
    });
    return response;
  },
} satisfies ExportedHandler<Env>;

async function handleChat(request: Request, env: Env, requestID: string): Promise<Response> {
  assertFeatureEnabled(env);
  const body = await readJSON<ChatBody>(request);
  const validated = validateCommonBody(body);
  assertMessages(body.messages);

  const subject = await entitlementSubject(request, env, validated.clientID);
  const limiter = env.USAGE_LIMITER.getByName(await sha256(subject));
  const reservation = await limiter.reserve(Date.now(), {
    perMinute: envNumber(env.MAX_REQUESTS_PER_MINUTE, 20, 1, 300),
    perDay: envNumber(env.MAX_REQUESTS_PER_DAY, 500, 1, 50_000),
    tokensPerMonth: envNumber(env.MAX_TOKENS_PER_MONTH, 2_000_000, 1_000, 100_000_000),
  });
  if (!reservation.allowed) {
    return Response.json(
      { error: { message: reservation.reason ?? "Usage limit reached.", request_id: requestID } },
      { status: 429, headers: { "Cache-Control": "no-store", "Retry-After": String(reservation.retryAfter) } },
    );
  }

  await verifyMcpEndpoint(validated.mcpURL, validated.mcpToken);
  const approvalGrants = await resolveApproval(
    body.approval_token,
    env,
    validated.clientID,
    new URL(validated.mcpURL).host,
    subject,
  );
  const capability = await createCapability(request, env, validated, subject, approvalGrants);
  const anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "anthropic-beta": "mcp-client-2025-11-20",
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
    },
    body: JSON.stringify({
      model: env.ANTHROPIC_MODEL || "claude-opus-4-8",
      max_tokens: 4096,
      system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
      mcp_servers: [{
        type: "url",
        name: "shopware",
        url: capability.url,
        authorization_token: capability.token,
      }],
      tools: [{ type: "mcp_toolset", mcp_server_name: "shopware" }],
      messages: body.messages,
    }),
  });
  const responseText = await readResponseText(anthropicResponse, 2_097_152);
  let result: Record<string, unknown>;
  try {
    result = JSON.parse(responseText) as Record<string, unknown>;
  } catch {
    throw new HTTPError(502, "The model returned an invalid response.");
  }
  if (!anthropicResponse.ok) {
    const upstreamMessage = isRecord(result.error) && typeof result.error.message === "string"
      ? result.error.message : "Upstream model error.";
    throw new HTTPError([429, 529].includes(anthropicResponse.status) ? 429 : 502, upstreamMessage);
  }

  const usage = isRecord(result.usage) ? result.usage : {};
  const totalTokens = tokenNumber(usage.input_tokens) + tokenNumber(usage.output_tokens) +
    tokenNumber(usage.cache_creation_input_tokens) + tokenNumber(usage.cache_read_input_tokens);
  await limiter.recordTokens(Date.now(), totalTokens);
  const approval = await createApprovalChallenge(
    result.content,
    env,
    validated.clientID,
    new URL(validated.mcpURL).host,
    subject,
    new Set(Object.keys(approvalGrants)),
  );
  return jsonResponse({
    content: result.content,
    stop_reason: result.stop_reason ?? null,
    usage: result.usage ?? null,
    approval,
  }, {}, requestID);
}

/** BYOK requests keep the Anthropic key on-device; this endpoint only creates
 * the short-lived MCP gateway capability used by the direct model request. */
async function handleDirectCapability(request: Request, env: Env, requestID: string): Promise<Response> {
  assertFeatureEnabled(env);
  await enforcePublicEndpointLimit(request, env);
  const body = await readJSON<CapabilityBody>(request, 32_768);
  const validated = validateCommonBody(body);
  const subject = `byok:${validated.clientID}`;
  await verifyMcpEndpoint(validated.mcpURL, validated.mcpToken);
  const approvalGrants = await resolveApproval(
    body.approval_token,
    env,
    validated.clientID,
    new URL(validated.mcpURL).host,
    subject,
  );
  const capability = await createCapability(request, env, validated, subject, approvalGrants);
  return jsonResponse(capability, {}, requestID);
}

async function handleDirectApproval(request: Request, env: Env, requestID: string): Promise<Response> {
  assertFeatureEnabled(env);
  await enforcePublicEndpointLimit(request, env);
  const body = await readJSON<ApprovalBody>(request, 262_144);
  const mcpURL = validateMcpURL(body.mcp_url);
  if (!mcpURL) throw new HTTPError(400, "Invalid mcp_url.");
  if (typeof body.client_id !== "string" || body.client_id.length < 16 || body.client_id.length > MAX_CLIENT_ID ||
      !/^[A-Za-z0-9._-]+$/.test(body.client_id)) throw new HTTPError(400, "Invalid client_id.");
  const subject = `byok:${body.client_id}`;
  const alreadyApproved = await resolveApproval(
    body.approval_token,
    env,
    body.client_id,
    new URL(mcpURL).host,
    subject,
  );
  const approval = await createApprovalChallenge(
    body.content,
    env,
    body.client_id,
    new URL(mcpURL).host,
    subject,
    new Set(Object.keys(alreadyApproved)),
  );
  return jsonResponse({ approval }, {}, requestID);
}

async function entitlementSubject(request: Request, env: Env, clientID: string): Promise<string> {
  if ((env.SKIP_ENTITLEMENT_CHECK as string) === "true") return `development:${clientID}`;
  const jws = request.headers.get("X-App-Transaction");
  if (!jws) throw new HTTPError(401, "Missing subscription. Subscribe in the app to use the assistant.");
  try {
    return (await verifyAppStoreTransaction(jws, env)).subject;
  } catch (error) {
    throw new HTTPError(401, `Subscription check failed: ${(error as Error).message}`);
  }
}

function validateCommonBody(body: CapabilityBody): { mcpURL: string; mcpToken: string; clientID: string } {
  const mcpURL = validateMcpURL(body.mcp_url);
  if (!mcpURL) throw new HTTPError(400, "Invalid mcp_url. A public HTTPS /api/_mcp endpoint is required.");
  if (typeof body.mcp_token !== "string" || body.mcp_token.length < 1 || body.mcp_token.length > MAX_MCP_TOKEN) {
    throw new HTTPError(400, "Invalid mcp_token.");
  }
  if (typeof body.client_id !== "string" || body.client_id.length < 16 || body.client_id.length > MAX_CLIENT_ID ||
      !/^[A-Za-z0-9._-]+$/.test(body.client_id)) {
    throw new HTTPError(400, "Invalid client_id.");
  }
  return { mcpURL, mcpToken: body.mcp_token, clientID: body.client_id };
}

function assertMessages(messages: unknown): void {
  if (!Array.isArray(messages) || messages.length < 1 || messages.length > MAX_MESSAGES) {
    throw new HTTPError(400, "Invalid messages.");
  }
  for (const message of messages) {
    if (!isRecord(message) || !["user", "assistant"].includes(String(message.role)) || !Array.isArray(message.content)) {
      throw new HTTPError(400, "Invalid message shape.");
    }
  }
}

async function createCapability(
  request: Request,
  env: Env,
  input: { mcpURL: string; mcpToken: string; clientID: string },
  subject: string,
  approvalGrants: Record<string, string>,
): Promise<{ url: string; token: string }> {
  const payload: CapabilityPayload = {
    kind: "mcp-capability",
    upstreamURL: input.mcpURL,
    upstreamToken: input.mcpToken,
    approvalGrants,
    subject,
    clientID: input.clientID,
    expiresAt: Date.now() + 5 * 60_000,
  };
  return {
    url: `${new URL(request.url).origin}/v1/mcp`,
    token: await sealToken(payload, env.CAPABILITY_SECRET),
  };
}

async function resolveApproval(
  value: unknown,
  env: Env,
  clientID: string,
  shopHost: string,
  subject: string,
): Promise<Record<string, string>> {
  if (value == null) return {};
  if (typeof value !== "string") throw new HTTPError(400, "Invalid approval token.");
  const approval = await openToken<ApprovalPayload>(value, env.CAPABILITY_SECRET);
  if (approval.kind !== "approval" || approval.expiresAt < Date.now() || approval.clientID !== clientID ||
      approval.shopHost !== shopHost || approval.subject !== subject || approval.approved.length > 8) {
    throw new HTTPError(401, "Approval does not match this shop or has expired.");
  }
  return Object.fromEntries(approval.approved.map((fingerprint) => [fingerprint, `${approval.approvalID}:${fingerprint}`]));
}

async function createApprovalChallenge(
  content: unknown,
  env: Env,
  clientID: string,
  shopHost: string,
  subject: string,
  alreadyApproved: Set<string>,
): Promise<ApprovalChallenge | null> {
  const actions = (await extractApprovalActions(content)).filter((action) => !alreadyApproved.has(action.fingerprint));
  if (actions.length === 0) return null;
  const expiresAt = Date.now() + 5 * 60_000;
  const payload: ApprovalPayload = {
    kind: "approval",
    clientID,
    shopHost,
    subject,
    approvalID: crypto.randomUUID(),
    approved: actions.map((action) => action.fingerprint),
    expiresAt,
  };
  return { token: await sealToken(payload, env.CAPABILITY_SECRET), actions, expires_at: expiresAt };
}

function featureEnabled(env: Env): boolean {
  return (env.AI_FEATURE_ENABLED as string) !== "false";
}

function assertFeatureEnabled(env: Env): void {
  if (!featureEnabled(env)) throw new HTTPError(503, "The AI assistant is temporarily disabled.");
}

function envNumber(value: string | undefined, fallback: number, minimum: number, maximum: number): number {
  const parsed = Number(value ?? fallback);
  return Number.isFinite(parsed) ? Math.min(maximum, Math.max(minimum, Math.trunc(parsed))) : fallback;
}

function tokenNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.trunc(value)) : 0;
}

async function enforcePublicEndpointLimit(request: Request, env: Env): Promise<void> {
  const address = request.headers.get("CF-Connecting-IP") ?? "local-development";
  const limiter = env.USAGE_LIMITER.getByName(await sha256(`public:${address}`));
  const result = await limiter.reserve(Date.now(), {
    perMinute: 60,
    perDay: 5_000,
    tokensPerMonth: 100_000_000,
  });
  if (!result.allowed) throw new HTTPError(429, result.reason ?? "Gateway rate limit reached.");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
