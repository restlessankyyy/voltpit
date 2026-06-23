# Voltpit: iPhone app

Native SwiftUI app: a full-screen Apple map that follows your heading with a
big Tesla-style speedometer and gear / battery / power readouts overlaid. It
connects to the backend WebSocket and updates in realtime.

## Prerequisites

- macOS with **Xcode 16+** and an iOS **simulator runtime installed**
  (Xcode → Settings → Components → install an iOS Simulator).
- **XcodeGen**: `brew install xcodegen`

## Setup

```bash
cd ios

# 1. Generate the Xcode project from project.yml.
xcodegen generate

# 2. Open and run.
open TeslaDash.xcodeproj
```

Pick an iPhone simulator (or your device) and Run.

## Pointing at the backend

- **Simulator:** the default `ws://localhost:8080/stream` works as-is.
- **Physical iPhone:** the phone can't reach `localhost`. Tap the gear icon in
  the app and set the URL to your Mac's LAN IP, e.g. `ws://192.168.1.20:8080/stream`.
  Find your IP with `ipconfig getifaddr en0`. (App Transport Security already
  allows local-network `ws://` for development.)

## Structure

| Path | Role |
| --- | --- |
| [`TeslaDash/App/`](TeslaDash/App/) | App entry and config. |
| [`TeslaDash/Models/`](TeslaDash/Models/) | `VehicleState` decoded from the backend. |
| [`TeslaDash/Networking/`](TeslaDash/Networking/) | `VehicleStream` WebSocket client with auto-reconnect. |
| [`TeslaDash/Views/`](TeslaDash/Views/) | `DashboardView`, `MapView` (Apple MapKit), `SpeedometerView`, components. |
| [`project.yml`](project.yml) | XcodeGen project definition (target, SPM deps, settings). |

## How the realtime UI works

`VehicleStream` (an `ObservableObject`) holds a `URLSessionWebSocketTask`,
decodes each `vehicle_state` message, and publishes it. `DashboardView` observes
it and drives:

- **Speedometer**: large number + arc gauge fill.
- **Map**: camera recenters on the car and rotates so travel is "up"; a blue
  arrow marks position.
- **Pills**: connection (Live/Asleep/Offline), gear `P R N D`, power kW, battery %.

If the socket drops it reconnects with exponential backoff, so a flaky cellular
connection in the car self-heals.

## Notes

- Deployment target is iOS 17. The map uses Apple **MapKit**, so no API key or
  billing is required.
- `TeslaDash.xcodeproj/` is gitignored; regenerate
  the project anytime with `xcodegen generate`.
