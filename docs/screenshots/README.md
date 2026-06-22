# Screenshots

The main [README](../../README.md) references these images. To populate them,
add PNGs with the following names to this folder:

| File | Screen |
| --- | --- |
| `connect.png` | The connect / credential-entry screen |
| `dashboard.png` | The main dashboard (KPIs, charts, orders) |
| `order-detail.png` | An order detail with status transitions |
| `shop-switcher.png` | The dashboard header shop switcher menu |

## How to capture

1. Run the app on a simulator (iPhone 15 / 6.7" gives clean App Store-sized
   shots) or on a device, connected to a **demo** Shopware shop.
2. Take a screenshot:
   - Simulator: `Cmd+S`, or `xcrun simctl io booted screenshot connect.png`.
   - Device: side button + volume up, then AirDrop to your Mac.
3. Save it here with the matching name above.

## Rules

- **Never** commit screenshots containing real customer data, live shop URLs,
  access keys, or anything sensitive. Use a throwaway demo shop.
- Keep images reasonably sized (portrait, ideally ≤ 500 KB each).
- PNG preferred for crisp UI.
