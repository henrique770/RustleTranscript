#!/usr/bin/env bash
# Regenerates client-macos/Resources/AppIcon.icns from the SwiftUI mark (Brand.swift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/client-macos"
swift build --package-path "$CLIENT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$(swift build --package-path "$CLIENT" --show-bin-path)/RustleTranscript" --icon "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$CLIENT/Resources/AppIcon.icns"
echo "Wrote $CLIENT/Resources/AppIcon.icns"
