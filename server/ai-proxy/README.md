# shopware-ai-proxy

Cloudflare Worker for the app's AI Shop Assistant. It verifies StoreKit
subscriptions, applies persistent usage limits, calls Anthropic for subscribed
users, and acts as a capability-based gateway in front of Shopware MCP.

```text
iOS app ── messages/JWS/App Attest assertion ──> /v1/chat ──> Anthropic
                                      └─ encrypted 5-minute MCP capability
Anthropic ── MCP call ──> /v1/mcp ──> merchant /api/_mcp
                              └─ unapproved writes are blocked
```

BYOK model requests go from the device directly to Anthropic. The device gets
only a short-lived MCP capability from `/v1/capability`; its Anthropic API key
is never sent to this Worker.

## Security model

- Production StoreKit JWS claims must match the Apple environment, bundle ID,
  App Store app ID, product, active expiry, and original transaction ID.
- Paid chat requests require a fresh, one-time server challenge and an Apple
  App Attest assertion over the exact request body. App Attest keys, assertion
  counters, and challenges are bound to the verified subscription's Durable
  Object, so a captured StoreKit JWS or chat request cannot simply be replayed.
- The certificate chain is bounded, validity-checked, Apple-extension-checked,
  signature-checked, and anchored to the pinned Apple Root CA G3.
- Every Shopware endpoint must be public-looking HTTPS, end in `/api/_mcp`, and
  pass a real MCP `initialize` preflight.
- MCP capabilities are AES-GCM encrypted, expire after five minutes, and hide
  the upstream Shopware token from the model provider.
- Read tools pass through. Unknown or write-like tools fail closed. Explicit
  dry-runs may run, but commits require an exact name/argument fingerprint from
  the native confirmation. Approval is bound to the client, shop, entitlement,
  and is consumed once through a Durable Object.
- One Durable Object per original transaction atomically reserves tokens before
  an Anthropic request, then reconciles the reservation to actual usage. This
  prevents concurrent requests from racing past the monthly allowance. It
  stores counters and App Attest public data, not conversations or credentials.
- Request bodies and upstream responses are size-bounded. Logs contain request
  metadata and IDs, never prompts, Shopware tokens, or API keys.
- `AI_FEATURE_ENABLED=false` is the production kill switch.

The gateway is an additional boundary, not a substitute for least-privilege
Shopware integration roles, short-lived tokens, Cloudflare account security,
and monitoring.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/v1/app-attest/challenge` | Issues a one-time, subscription-bound App Attest challenge. |
| `POST` | `/v1/app-attest/register` | Verifies and registers an Apple App Attest key. |
| `POST` | `/v1/chat` | Subscription model request. Requires the transaction JWS and App Attest assertion headers. |
| `POST` | `/v1/capability` | Creates a BYOK MCP capability; never receives the Anthropic key. |
| `POST` | `/v1/approval` | Converts proposed BYOK MCP actions into a native approval challenge. |
| `GET/POST/DELETE` | `/v1/mcp` | Capability-authenticated Streamable HTTP MCP gateway. |
| `GET` | `/v1/config` | Remote feature flag. |
| `GET` | `/health` | Liveness and enabled state. |

Chat bodies include `messages`, `mcp_url`, `mcp_token`, `client_id`, and an
optional `approval_token`. Successful chat responses include `content`,
`stop_reason`, `usage`, and an optional `approval` challenge.

## Configure and deploy

```bash
cd server/ai-proxy
npm ci
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put CAPABILITY_SECRET
npx wrangler secret put APPLE_APP_ID
npm run typecheck
npm run types:check
npm test
npx wrangler deploy --dry-run
npx wrangler deploy
```

Generate `CAPABILITY_SECRET` with at least 32 random bytes and enter it only at
Wrangler's interactive prompt. `APPLE_APP_ID` is the numeric App Store Connect
app ID. It is configured as a secret so deploys cannot accidentally remove a
dashboard-only variable. Never put either value in the repository.

`wrangler.jsonc` defines the bundle/product IDs, production StoreKit
environment, Apple team ID, App Attest policy, model, quotas, observability,
Durable Object binding, and initial SQLite migration. Review these before
deployment. A first deployment creates the `UsageLimiter` Durable Object class.

Before archiving the app, enable the App Attest capability for
`com.asakenas.shopwareapp` in Certificates, Identifiers & Profiles and refresh
the provisioning profiles. Debug builds use the development App Attest
environment; Release builds use production. The production Worker deliberately
rejects development attestations.

For an already-live older app, stage the rollout: first deploy this Worker with
`APP_ATTEST_REQUIRED=false`, release the App Attest-capable app, then switch the
flag to `true` after the old version is no longer allowed to use subscription
AI. App Attest endpoints remain available in optional mode, and any supplied
assertion is still verified. Do not leave production in optional mode.

App Attest is unavailable on Mac hardware and simulators. With
`APP_ATTEST_REQUIRED=true`, the included subscription-backed AI service fails
closed on those devices; BYOK remains available because the user's provider key
never enters this Worker.

After deployment, set `AIProxyConfig.defaultURLString` in
`ShopwareApp/AI/AIChatService.swift` to the Worker URL.

## Local development

Use `.dev.vars` for fake/local secrets (it is gitignored). App Attest itself
requires a physical supported Apple device. For a development-signed app, run:

```bash
npx wrangler dev --var SKIP_ENTITLEMENT_CHECK:true --var APP_ATTEST_ALLOW_DEVELOPMENT:true
```

Debug builds may set the `aiProxyURL` UserDefaults key to
`http://localhost:8787`. Release builds ignore that override and always require
the compiled HTTPS Worker URL. Never deploy with `SKIP_ENTITLEMENT_CHECK=true`.

## Verification

```bash
npm run typecheck
npm test
npx wrangler deploy --dry-run
```

The MCP integration targets Shopware 6.7.11+ and remains dependent on its
experimental `MCP_SERVER` feature flag. Keep the remote kill switch available
and test against each Shopware update before enabling it broadly.
