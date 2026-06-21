# Contributing to ShopwareApp

Thanks for your interest in improving ShopwareApp! This is a native SwiftUI
dashboard for the Shopware 6 Admin API. Contributions of all sizes are welcome.

## Getting started

1. **Requirements**
   - Xcode 16 or newer
   - iOS 16+ / macOS 13+ targets (the app uses Swift Charts)
   - A Shopware 6.5+ instance with an Admin API integration for manual testing
     (see the [Shopware Setup](README.md#shopware-setup) section of the README)

2. **Build & run**
   - Open `ShopwareApp.xcodeproj` in Xcode and run the `ShopwareApp` scheme on an
     iOS Simulator, a device, or "My Mac".
   - From the command line you can compile without code signing:
     ```sh
     xcodebuild build -scheme ShopwareApp \
       -destination 'platform=macOS' \
       CODE_SIGNING_ALLOWED=NO
     ```

3. **Project layout**

   The app is organized by responsibility. Please add new files to the matching
   folder so the project stays navigable:

   | Folder | Contents |
   | --- | --- |
   | `ShopwareApp/App/` | App entry point and root routing view |
   | `ShopwareApp/Models/` | Plain data models (orders, products, customers, …) |
   | `ShopwareApp/Networking/` | `ShopwareAdminClient`, errors, JSON parsing helpers |
   | `ShopwareApp/Storage/` | Keychain credential storage |
   | `ShopwareApp/ViewModels/` | Observable state (`ShopwareDashboardViewModel`) |
   | `ShopwareApp/Views/` | SwiftUI screens, charts, and reusable components |
   | `ShopwareApp/Theme/` | Colors, button styles, animations |
   | `ShopwareApp/Extensions/` | Small Foundation/SwiftUI extensions |

   The Xcode project uses synchronized folder groups, so files added to these
   directories are picked up automatically — no `.xcodeproj` editing required.

## Pull request guidelines

To keep the app stable and useful, please:

- **Open an issue or discussion first** for large UI, architecture, or API
  changes, so we can agree on the approach before you invest time.
- **Keep pull requests focused** on a single fix or feature.
- **Match the existing SwiftUI style.** Keep the app usable on iPhone, iPad, and
  macOS where possible (note the `#if !os(macOS)` guards already in the views).
- **Never commit secrets.** No Shopware credentials, access keys, screenshots
  containing secrets, provisioning profiles, or local build artifacts.
- **Test against a real Shopware integration** when your change touches
  authentication, permissions, or Admin API requests.
- **Document new permissions.** If a feature needs a new Shopware permission, add
  it to the permissions table in the [README](README.md#shopware-setup).
- **Explain user impact and validation steps** in the pull request description.

## Verifying your change

Before opening a PR:

- Make sure the project builds (`xcodebuild build` as shown above, or in Xcode).
- Run the app and exercise the screens your change touches.
- If you added pure, side-effect-free logic (parsing, date math, formatting),
  consider adding a unit test for it.

## Reporting bugs

When filing an issue, please include:

- Your Shopware version and the device/OS you ran the app on.
- Steps to reproduce, what you expected, and what happened instead.
- Any error message shown in the app (the app surfaces Admin API and network
  errors with actionable detail).

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
