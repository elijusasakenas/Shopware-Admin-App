/**
 * shopware-ai-proxy — Cloudflare Worker
 *
 * Sits between the iOS app and the Anthropic API so the API key never ships
 * inside the app. Each request must carry the user's signed App Store
 * transaction (JWS) in the `X-App-Transaction` header; the worker verifies
 * the signature chain against Apple's root certificate and checks that the
 * subscription is active before forwarding the chat to the model.
 *
 * The model operates the shop through Shopware's built-in MCP server
 * (Shopware 6.7.11+, `/api/_mcp`): the app sends the shop's MCP URL and a
 * short-lived Admin API bearer token, and this worker hands them to the
 * Anthropic MCP connector, which talks to the shop directly. The token
 * expires after ~10 minutes and never persists here.
 */

export interface Env {
  /** Secret — set with `wrangler secret put ANTHROPIC_API_KEY`. */
  ANTHROPIC_API_KEY: string;
  APPLE_BUNDLE_ID: string;
  SUBSCRIPTION_PRODUCT_ID: string;
  ANTHROPIC_MODEL?: string;
  /**
   * "true" disables the App Store check — required for local development,
   * because transactions from Xcode's local StoreKit configuration are not
   * signed by Apple's production chain. NEVER enable in production.
   */
  SKIP_ENTITLEMENT_CHECK?: string;
}

const SYSTEM_PROMPT = `You are the AI assistant inside a Shopware merchant app. The user is a shop owner managing their store from their phone.

You are connected to the shop's own MCP server, which exposes Shopware's tools, resources, and prompts. Use them instead of guessing: look up entities before acting on them. Amounts are in the shop's currency.

Changing the shop requires the user's consent. Before any write (create, update, delete, state change, configuration change): state exactly what you are about to change and ask the user to confirm in chat. Where a tool supports dry-run execution, dry-run first and show the outcome. Only commit after the user clearly agrees. If the user declines, accept it and do not retry.

Be concise and practical. Answer in the language the user writes in. When you list data, prefer short readable summaries over raw dumps. If a request is ambiguous (e.g. several products match), show the candidates and ask which one the user means.`;

const MAX_MESSAGES = 200;

/** SHA-256 fingerprint of the "Apple Root CA - G3" certificate, which anchors
 * the chain Apple uses to sign StoreKit 2 transactions. */
const APPLE_ROOT_CA_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/v1/chat") {
      return handleChat(request, env);
    }
    if (request.method === "GET" && url.pathname === "/health") {
      return Response.json({ ok: true });
    }
    return errorResponse(404, "Not found.");
  },
};

async function handleChat(request: Request, env: Env): Promise<Response> {
  // 1. Entitlement: verify the signed App Store transaction.
  if (env.SKIP_ENTITLEMENT_CHECK !== "true") {
    const jws = request.headers.get("X-App-Transaction");
    if (!jws) {
      return errorResponse(401, "Missing subscription. Subscribe in the app to use the assistant.");
    }
    try {
      await verifyAppStoreTransaction(jws, env);
    } catch (error) {
      return errorResponse(401, `Subscription check failed: ${(error as Error).message}`);
    }
  }

  // 2. Validate the chat payload.
  let body: { messages?: unknown; mcp_url?: unknown; mcp_token?: unknown };
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "Invalid JSON body.");
  }
  const { messages, mcp_url, mcp_token } = body;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) {
    return errorResponse(400, "Invalid 'messages'.");
  }
  if (typeof mcp_token !== "string" || mcp_token.length === 0 || mcp_token.length > 8192) {
    return errorResponse(400, "Invalid 'mcp_token'.");
  }
  const mcpURL = validateMcpURL(mcp_url);
  if (!mcpURL) {
    return errorResponse(400, "Invalid 'mcp_url'. Expected the shop's https .../api/_mcp endpoint.");
  }

  // 3. Forward to the Anthropic Messages API with the MCP connector pointed
  //    at the shop's built-in MCP server. Tool calls run server-side there.
  const anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "anthropic-beta": "mcp-client-2025-11-20",
    },
    body: JSON.stringify({
      model: env.ANTHROPIC_MODEL || "claude-opus-4-8",
      max_tokens: 4096,
      system: [
        {
          type: "text",
          text: SYSTEM_PROMPT,
          cache_control: { type: "ephemeral" },
        },
      ],
      mcp_servers: [
        {
          type: "url",
          name: "shopware",
          url: mcpURL,
          authorization_token: mcp_token,
        },
      ],
      tools: [{ type: "mcp_toolset", mcp_server_name: "shopware" }],
      messages,
    }),
  });

  const result = (await anthropicResponse.json()) as Record<string, unknown>;
  if (!anthropicResponse.ok) {
    const message =
      (result?.error as { message?: string } | undefined)?.message ?? "Upstream model error.";
    // 429/529 pass through as 429 so the app shows a retry hint.
    const status = anthropicResponse.status === 429 || anthropicResponse.status === 529 ? 429 : 502;
    return errorResponse(status, message);
  }

  // Return only what the app needs (usage feeds the in-app usage counter).
  return Response.json({
    content: result.content,
    stop_reason: result.stop_reason ?? null,
    usage: result.usage ?? null,
  });
}

function errorResponse(status: number, message: string): Response {
  return Response.json({ error: { message } }, { status });
}

/** Only accept a Shopware MCP endpoint: https, path /api/_mcp. Keeps the
 * connector from being pointed at arbitrary URLs with our subscription. */
function validateMcpURL(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 2048) return null;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol !== "https:") return null;
  if (!url.pathname.endsWith("/api/_mcp")) return null;
  if (url.search || url.hash || url.username || url.password) return null;
  return url.toString();
}

// ---------------------------------------------------------------------------
// App Store transaction verification (StoreKit 2 JWS)
//
// The transaction is a JWS whose x5c header carries the certificate chain
// leaf → intermediate → Apple Root CA G3. We verify:
//   1. every certificate is signed by the next one in the chain,
//   2. the chain terminates in the pinned Apple root,
//   3. the JWS signature matches the leaf certificate's key,
//   4. the payload is our bundle + product and the subscription is active.
// ---------------------------------------------------------------------------

interface TransactionPayload {
  bundleId?: string;
  productId?: string;
  expiresDate?: number;
  revocationDate?: number;
}

async function verifyAppStoreTransaction(jws: string, env: Env): Promise<void> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("malformed transaction");
  const [headerB64, payloadB64, signatureB64] = parts;

  let header: { alg?: string; x5c?: string[] };
  try {
    header = JSON.parse(textDecode(base64UrlDecode(headerB64)));
  } catch {
    throw new Error("malformed transaction");
  }
  if (header.alg !== "ES256") throw new Error("unexpected algorithm");
  if (!header.x5c || header.x5c.length < 2) throw new Error("missing certificate chain");

  const chain = header.x5c.map((cert) => base64Decode(cert));

  // 2. Pin the root.
  const rootHash = hex(new Uint8Array(await crypto.subtle.digest("SHA-256", chain[chain.length - 1] as BufferSource)));
  if (rootHash !== APPLE_ROOT_CA_G3_SHA256) throw new Error("untrusted certificate chain");

  // 1. Verify each certificate against its issuer.
  for (let i = 0; i < chain.length - 1; i++) {
    if (!(await verifyCertificateSignature(chain[i], chain[i + 1]))) {
      throw new Error("broken certificate chain");
    }
  }

  // 3. Verify the JWS signature with the leaf key.
  const leafKey = await importCertificateKey(chain[0]);
  const signedBytes = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const signature = base64UrlDecode(signatureB64);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    leafKey,
    signature as BufferSource,
    signedBytes as BufferSource
  );
  if (!valid) throw new Error("invalid signature");

  // 4. Check the claims.
  const payload = JSON.parse(textDecode(base64UrlDecode(payloadB64))) as TransactionPayload;
  if (payload.bundleId !== env.APPLE_BUNDLE_ID) throw new Error("wrong app");
  if (payload.productId !== env.SUBSCRIPTION_PRODUCT_ID) throw new Error("wrong product");
  if (payload.revocationDate) throw new Error("subscription revoked");
  if (!payload.expiresDate || payload.expiresDate < Date.now()) {
    throw new Error("subscription expired");
  }
}

// --- Minimal DER / X.509 parsing -------------------------------------------

interface TLV {
  tag: number;
  /** offset of the first content byte */
  contentStart: number;
  /** offset after the last content byte */
  contentEnd: number;
  /** offset of the tag byte (start of the full TLV) */
  start: number;
}

function readTLV(bytes: Uint8Array, offset: number): TLV {
  const tag = bytes[offset];
  let cursor = offset + 1;
  let length = bytes[cursor++];
  if (length & 0x80) {
    const byteCount = length & 0x7f;
    length = 0;
    for (let i = 0; i < byteCount; i++) length = (length << 8) | bytes[cursor++];
  }
  return { tag, contentStart: cursor, contentEnd: cursor + length, start: offset };
}

function childrenOf(bytes: Uint8Array, tlv: TLV): TLV[] {
  const result: TLV[] = [];
  let cursor = tlv.contentStart;
  while (cursor < tlv.contentEnd) {
    const child = readTLV(bytes, cursor);
    result.push(child);
    cursor = child.contentEnd;
  }
  return result;
}

function fullBytes(bytes: Uint8Array, tlv: TLV): Uint8Array {
  return bytes.slice(tlv.start, tlv.contentEnd);
}

/** Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signature } */
function parseCertificate(der: Uint8Array) {
  const outer = readTLV(der, 0);
  const [tbs, sigAlg, sigBits] = childrenOf(der, outer);
  const oid = childrenOf(der, sigAlg)[0];
  const oidHex = hex(fullBytes(der, oid));
  // ecdsa-with-SHA256 / ecdsa-with-SHA384
  const hash =
    oidHex === "06082a8648ce3d040302" ? "SHA-256" :
    oidHex === "06082a8648ce3d040303" ? "SHA-384" : null;
  if (!hash) throw new Error("unsupported certificate signature algorithm");

  // BIT STRING: first content byte is the unused-bit count (0 here).
  const derSignature = der.slice(sigBits.contentStart + 1, sigBits.contentEnd);

  // tbsCertificate children: optional [0] version, serial, sigalg, issuer,
  // validity, subject, subjectPublicKeyInfo, ...
  const tbsChildren = childrenOf(der, tbs);
  const spkiIndex = tbsChildren[0].tag === 0xa0 ? 6 : 5;
  const spki = fullBytes(der, tbsChildren[spkiIndex]);

  return { tbsBytes: fullBytes(der, tbs), hash, derSignature, spki };
}

function curveOf(spki: Uint8Array): { curve: "P-256" | "P-384"; size: number } {
  const spkiHex = hex(spki);
  if (spkiHex.includes("06082a8648ce3d030107")) return { curve: "P-256", size: 32 };
  if (spkiHex.includes("06052b81040022")) return { curve: "P-384", size: 48 };
  throw new Error("unsupported certificate key type");
}

async function importSPKI(spki: Uint8Array): Promise<{ key: CryptoKey; size: number }> {
  const { curve, size } = curveOf(spki);
  const key = await crypto.subtle.importKey(
    "spki",
    spki as BufferSource,
    { name: "ECDSA", namedCurve: curve },
    false,
    ["verify"]
  );
  return { key, size };
}

async function importCertificateKey(certDER: Uint8Array): Promise<CryptoKey> {
  return (await importSPKI(parseCertificate(certDER).spki)).key;
}

/** Verifies that `certDER` was signed by `issuerDER`'s key. */
async function verifyCertificateSignature(certDER: Uint8Array, issuerDER: Uint8Array): Promise<boolean> {
  const cert = parseCertificate(certDER);
  const issuer = parseCertificate(issuerDER);
  const { key, size } = await importSPKI(issuer.spki);
  const rawSignature = derSignatureToRaw(cert.derSignature, size);
  return crypto.subtle.verify(
    { name: "ECDSA", hash: cert.hash },
    key,
    rawSignature as BufferSource,
    cert.tbsBytes as BufferSource
  );
}

/** DER ECDSA-Sig-Value (SEQUENCE of two INTEGERs) → raw r||s for WebCrypto. */
function derSignatureToRaw(der: Uint8Array, size: number): Uint8Array {
  const outer = readTLV(der, 0);
  const [r, s] = childrenOf(der, outer);
  const raw = new Uint8Array(size * 2);
  raw.set(trimInteger(der.slice(r.contentStart, r.contentEnd), size), 0);
  raw.set(trimInteger(der.slice(s.contentStart, s.contentEnd), size), size);
  return raw;
}

function trimInteger(bytes: Uint8Array, size: number): Uint8Array {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  const trimmed = bytes.slice(start);
  const padded = new Uint8Array(size);
  padded.set(trimmed, size - trimmed.length);
  return padded;
}

// --- Encoding helpers -------------------------------------------------------

function base64Decode(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64UrlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  return base64Decode(padded + "=".repeat((4 - (padded.length % 4)) % 4));
}

function textDecode(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}
