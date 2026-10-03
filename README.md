# Homeboard

Homeboard is a SwiftUI living-room dashboard for iPad. It brings together a flip clock, animated weather and sky, world clocks, nearby flight activity, headlines, a guest Wi-Fi QR code, and optional Apple Home light controls.

## Privacy

This repository contains no Wi-Fi password, Apple Home accessories, Apple Account information, signing certificate, or personal Home data. Guest Wi-Fi details are entered locally in the app and stay on that iPad. Apple Home access always uses the home the person has already authorized in iOS.

## Requirements

- macOS with Xcode
- iPad running iOS 18.6 or later (or an iOS 18.6 simulator)
- An Apple Account for installing on a personal iPad
- Apple Home configured on the iPad, only if Home controls are wanted

## Run it

1. Clone or download this repository, then open `FlightWalliPad.xcodeproj` in Xcode.
2. Select the **FlightWalliPad** target, then open **Signing & Capabilities**.
3. Select your own Personal Team.
4. Change the Bundle Identifier from `com.example.Homeboard` to one that is unique to you, such as `com.yourname.Homeboard`.
5. Connect an iPad or select an iPad simulator, then press Run.
6. If installing on an iPad, enable Developer Mode and trust your developer certificate when iPadOS asks.

## Personalize

Open the gear icon in Homeboard to change the welcome message, temperature unit, world clocks, and flight-view location/range. Guest Wi-Fi credentials are configured only from the Wi-Fi Connect card in the app.

The weather and sky experience currently uses Boston as its sample location. The airport view is independently configurable in Settings.

## Data sources

Homeboard uses public weather, astronomical, RSS, and community ADS-B services. Their availability and coverage can vary, so flight activity and headlines are best-effort rather than safety-critical information.

## Contributing

Please do not commit personal Home data, credentials, signing files, or Xcode user-state files. The included `.gitignore` excludes the common local files, but always review changes before pushing.
