# ShopwareApp

Open-source native iOS/macOS dashboard for the Shopware 6 Admin API, styled after the Shopware administration.

## Features

### Dashboard
- KPIs: orders today, revenue today, products, customers
- Orders and revenue bar charts (Swift Charts) with date ranges: 30 / 14 / 7 days, 24 hours, yesterday
- Sales channel selector — every metric, chart, and list filters per channel
- Today's orders list with currency-aware formatting
- Top products of the last 30 days (terms aggregation on order line items)
- Low stock alerts (active products with stock ≤ 10)
- Pull-to-refresh

### Order management
- Order detail with line items and customer info
- Change **order**, **payment**, and **delivery** status — valid transitions are loaded live from Shopware's state machine

### AI Shop Assistant (subscription)
- Chat with an AI assistant that operates the shop through
  [Shopware's built-in MCP server](https://developer.shopware.com/docs/products/tools/mcp-server/)
- Reads and manages products, orders, promotions, media, and configuration
  using Shopware's own tools — every request is checked against Shopware ACL,
  and writes need an exact, one-time native approval before they can commit
- Requires **Shopware 6.7.11.0+** with the `MCP_SERVER` feature flag enabled;
  the app detects this and guides the merchant otherwise
- Two ways to use it: a monthly auto-renewable subscription (StoreKit 2, model
  calls go through a small proxy you deploy — see
  [server/ai-proxy](server/ai-proxy/README.md)), **or** the merchant brings
  their own Anthropic API key — stored in the device Keychain; model requests
  go directly to Anthropic while MCP calls still use the approval gateway

### Shop settings
- Maintenance mode toggle per sales channel
- Marketing: activate/deactivate promotions (with their codes) instantly
- Newsletter signups with opt-in status
- New customer registrations (account vs. guest)
- Shop status page: Shopware version, storefront availability checks with response times, and the shop log (`log_entry`)

## Requirements

- iOS 16+ / macOS 13+ (Swift Charts)
- Shopware 6.5+ (developed against 6.7)

## Shopware Setup

Create an integration in the Shopware Administration:

1. Open `Settings > System > Integrations`.
2. Create a new integration.
3. Copy the access key and secret access key.
4. Grant the permissions listed below — or administrator access for full functionality.

Permissions used:

| Feature | Permission |
| --- | --- |
| Dashboard, orders, charts | Orders: read |
| Products, low stock | Products: read |
| Customers, registrations | Customers: read |
| Currency formatting | Currencies: read |
| Status changes | Orders: edit, state machine transitions |
| Maintenance toggle | Sales channels: edit |
| Promotions | Promotions: read/edit |
| Newsletter | Newsletter recipients: read |
| Shop log | Log entries: read |

Note: on Shopware 6.7 the "Administration" toggle was removed from the integrations UI. Either assign the permissions above through ACL roles, or set the integration's `admin` flag.

## Security

This app connects directly from the device to the Shopware Admin API. Keychain protects saved credentials on the device, but direct Admin API credentials in a distributed mobile app are still sensitive.

For production or public distribution, use a small backend proxy:

- Store the Shopware integration secret server-side.
- Authenticate mobile users separately.
- Expose only the mobile dashboard endpoints needed.
- Add audit logs and rate limits.

## AI assistant setup

**Shop requirements:** Shopware **6.7.11.0 or newer** with the MCP server
enabled (`MCP_SERVER=1` in the shop's `.env`). The shop must be reachable from
the internet. MCP calls pass through a short-lived Cloudflare approval gateway,
which authenticates to the shop with an Admin API token minted on the device.
The integration's Shopware permissions bound what the assistant can do, and
write calls are blocked until the exact tool arguments receive native approval.

The AI chat also needs two things you own:

1. **The proxy** — deploy [server/ai-proxy](server/ai-proxy/README.md) (a
   Cloudflare Worker) with your Anthropic API key, then put the worker URL
   into `AIProxyConfig.defaultURLString` in `ShopwareApp/AI/AIChatService.swift`.
   The key never ships in the app; the worker verifies the caller's App Store
   subscription before forwarding any request.
2. **The subscription** — create an auto-renewable subscription with product id
   `com.asakenas.shopwareapp.ai.monthly` in App Store Connect (the fallback UI
   price is €10/month; StoreKit displays the configured regional price). For simulator testing, select
   `ShopwareApp/Configuration/ShopwareAI.storekit` under
   Edit Scheme → Run → Options → StoreKit Configuration, and purchases work
   locally without App Store Connect.

AI messages and relevant Shopware results are processed by Anthropic. The
gateway does not persist conversations or credentials; it stores only
per-subscription usage/approval counters. Shop tokens are short-lived.

## Project structure

The app is organized by responsibility under `ShopwareApp/`:

| Folder | Contents |
| --- | --- |
| `AI/` | AI assistant: chat models, proxy/gateway client |
| `App/` | App entry point and root routing view |
| `Models/` | Plain data models (orders, products, customers, …) |
| `Networking/` | `ShopwareAdminClient`, errors, JSON parsing helpers |
| `Storage/` | Keychain credential storage |
| `Store/` | StoreKit 2 subscription for the AI assistant |
| `ViewModels/` | Observable state (`ShopwareDashboardViewModel`) |
| `Views/` | SwiftUI screens, charts, and reusable components |
| `Theme/` | Colors, button styles, animations |
| `Extensions/` | Small Foundation/SwiftUI extensions |

The Xcode project uses synchronized folder groups, so files added to these
directories are picked up automatically.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for how to build,
where code lives, and the pull request checklist. In short: open an issue before
large changes, keep PRs focused, never commit secrets, and test Admin API changes
against a real Shopware integration.

## License

MIT
