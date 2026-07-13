# shopware-ai-proxy

Cloudflare Worker that powers the app's **AI Shop Assistant**. It keeps the
Anthropic API key server-side, verifies that the caller has an active App
Store subscription, and forwards the conversation to Claude.

```
iOS app ──(messages + shop MCP URL + short-lived token + signed transaction)──▶ this worker
                                                                                    │
                                              Anthropic API ◀──────────────────────┘
                                                    │ (MCP connector)
                                          merchant shop /api/_mcp
                                          (Shopware 6.7.11+, MCP_SERVER=1)
```

The model operates the shop through [Shopware's built-in MCP server](https://developer.shopware.com/docs/products/tools/mcp-server/):
this worker hands the shop's `/api/_mcp` URL and a short-lived Admin API
bearer token (minted on the device, ~10 min lifetime) to the Anthropic MCP
connector, which talks to the shop directly. The shop must be publicly
reachable. The worker validates that `mcp_url` is an https `.../api/_mcp`
endpoint so the connector can't be pointed anywhere else.

## Endpoints

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/v1/chat` | Body `{ messages, mcp_url, mcp_token }`. Requires header `X-App-Transaction` with the StoreKit 2 signed transaction (JWS). Returns `{ content, stop_reason }`. |
| `GET` | `/health` | Liveness check. |

## Subscription verification

The `X-App-Transaction` JWS is verified end-to-end in the worker:

1. Each certificate in the `x5c` chain is signature-checked against its issuer.
2. The chain must terminate in the pinned **Apple Root CA - G3**.
3. The JWS signature is verified with the leaf certificate's key.
4. The payload must match `APPLE_BUNDLE_ID` + `SUBSCRIPTION_PRODUCT_ID`, be
   unrevoked, and not expired.

Transactions signed by Xcode's **local StoreKit configuration** (simulator
testing) are *not* signed by Apple's chain, so for local development set
`SKIP_ENTITLEMENT_CHECK = "true"` in `wrangler.toml` (or `wrangler dev --var`).
Never deploy with the check disabled.

## Deploy

```bash
cd server/ai-proxy
npm install
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY   # paste your key from console.anthropic.com
npx wrangler deploy
```

The deploy prints your worker URL, e.g.
`https://shopware-ai-proxy.<your-subdomain>.workers.dev`. Put that URL into
`AIProxyConfig.defaultURLString` in
`ShopwareApp/AI/AIChatService.swift` before shipping the app.

## Local development

```bash
npx wrangler dev --var SKIP_ENTITLEMENT_CHECK:true
```

Then point the app at your machine: in the app's UserDefaults set
`aiProxyURL` to `http://localhost:8787` (e.g. via a breakpoint or a debug
build tweak), or temporarily change `AIProxyConfig.defaultURLString`.

## Configuration

| Variable | Where | Purpose |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | secret | Your Anthropic API key — pays for the model usage your subscribers generate. |
| `APPLE_BUNDLE_ID` | `wrangler.toml` | Must match the app's bundle id. |
| `SUBSCRIPTION_PRODUCT_ID` | `wrangler.toml` | Must match the auto-renewable product id. |
| `ANTHROPIC_MODEL` | `wrangler.toml` | Defaults to `claude-opus-4-8`. |
| `SKIP_ENTITLEMENT_CHECK` | `wrangler.toml` | Dev only. |

## Cost & abuse notes

- The system prompt is sent with `cache_control` so repeated requests hit the
  prompt cache.
- `max_tokens` is capped at 4096 and conversations at 200 messages / request.
- Consider adding [Cloudflare rate limiting](https://developers.cloudflare.com/waf/rate-limiting-rules/)
  per IP in front of `/v1/chat` before launch, and monitor usage in the
  Anthropic console so a heavy subscriber can't outspend their 4 €.
