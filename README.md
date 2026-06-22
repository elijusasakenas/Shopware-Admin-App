# ShopwareApp

Open-source native iOS/macOS dashboard for the Shopware 6 Admin API, styled after the Shopware administration.

## Screenshots

<!--
  Drop PNGs into docs/screenshots/ with these names and they'll show up here.
  Recommended: 1290×2796 (iPhone 6.7") portrait, or trimmed device frames.
  Use a demo shop — never commit screenshots that contain real customer data,
  shop URLs, or API keys.
-->

| Connect | Dashboard | Order detail | Shop switcher |
| :---: | :---: | :---: | :---: |
| ![Connect screen](docs/screenshots/connect.png) | ![Dashboard](docs/screenshots/dashboard.png) | ![Order detail](docs/screenshots/order-detail.png) | ![Shop switcher](docs/screenshots/shop-switcher.png) |

> Screenshots are not committed yet. See [docs/screenshots/README.md](docs/screenshots/README.md) for how to add them.

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

## Project structure

The app is organized by responsibility under `ShopwareApp/`:

| Folder | Contents |
| --- | --- |
| `App/` | App entry point and root routing view |
| `Models/` | Plain data models (orders, products, customers, …) |
| `Networking/` | `ShopwareAdminClient`, errors, JSON parsing helpers |
| `Storage/` | Keychain credential storage |
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
