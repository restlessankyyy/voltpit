#!/usr/bin/env bash
# Build the SwiftUI app and install it on a connected iPhone.
#
# Usage:
#   ./install-device.sh            # auto-pick the first connected iPhone
#   ./install-device.sh <udid>     # target a specific device
#
# Requires Xcode + a device trusted for development. Signing is Automatic with
# the team configured in project.yml (DEVELOPMENT_TEAM=SYB4Q5V288).
set -euo pipefail

cd "$(dirname "$0")"

UDID="${1:-}"
if [[ -z "$UDID" ]]; then
  # Grab the first connected, available device UDID from devicectl.
  UDID="$(xcrun devicectl list devices 2>/dev/null \
    | awk '/available/ && /iPhone/ {print $(NF-2); exit}')"
fi

if [[ -z "$UDID" ]]; then
  echo "No connected iPhone found. Plug in and trust the device, then retry." >&2
  echo "List devices with: xcrun devicectl list devices" >&2
  exit 1
fi

echo "==> Target device: $UDID"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building for device (Debug)"
xcodebuild \
  -project TeslaDash.xcodeproj \
  -scheme TeslaDash \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates \
  build

APP_PATH="build/DerivedData/Build/Products/Debug-iphoneos/TeslaDash.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build product not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Installing $APP_PATH"
xcrun devicectl device install app --device "$UDID" "$APP_PATH"

echo "==> Done. Launch TeslaDash from the home screen."
