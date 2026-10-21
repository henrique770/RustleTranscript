#!/usr/bin/env bash
# Builds the Swift client and wraps it in RustleTranscript.app so macOS can grant it the Microphone
# and System Audio Recording permissions.
# Signs with "RustleTranscript Local Signing" (scripts/create-signing-cert.sh) when present, so the
# permissions survive rebuilds; falls back to an ad-hoc signature otherwise.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/client-macos"
APP="$ROOT/build/RustleTranscript.app"
# Assembled and signed outside the checkout: in an iCloud-synced folder (Documents, Desktop) the
# File Provider re-adds Finder info to the bundle, which codesign rejects ("detritus not allowed").
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE="$STAGE_DIR/RustleTranscript.app"

# SwiftPM's module cache stores absolute paths: after the folder is moved or renamed, start clean.
if [ -f "$CLIENT/.build/.root" ] && [ "$(cat "$CLIENT/.build/.root")" != "$CLIENT" ]; then
  rm -rf "$CLIENT/.build"
fi
swift build -c release --package-path "$CLIENT"
echo "$CLIENT" > "$CLIENT/.build/.root"
BIN="$(swift build -c release --package-path "$CLIENT" --show-bin-path)/RustleTranscript"

mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/RustleTranscript"
# Figtree + EB Garamond (SIL OFL), registered through ATSApplicationFontsPath.
cp -R "$CLIENT/Resources/Fonts" "$STAGE/Contents/Resources/Fonts"
# Same mark as the sidebar logo (regenerate with scripts/make-icon.sh).
cp "$CLIENT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"
cat > "$STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.rustletranscript.client</string>
  <key>CFBundleName</key><string>RustleTranscript</string>
  <key>CFBundleDisplayName</key><string>Rustle Transcript</string>
  <key>CFBundleExecutable</key><string>RustleTranscript</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
  <key>NSMicrophoneUsageDescription</key><string>O Rustle Transcript ouve a sua voz para mostrar a legenda em tempo real.</string>
  <key>NSAudioCaptureUsageDescription</key><string>O Rustle Transcript ouve o áudio do computador (chamadas, vídeos) para legendá-lo em tempo real.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>O reconhecimento de fala da Apple transforma o áudio em texto, aqui no seu Mac.</string>
</dict>
</plist>
PLIST

xattr -cr "$STAGE"
IDENTITY="$(security find-identity -p codesigning 2>/dev/null | awk '/"RustleTranscript Local Signing"/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --identifier dev.rustletranscript.client "$STAGE"
  echo "Signed with RustleTranscript Local Signing ($IDENTITY)"
else
  codesign --force --sign - "$STAGE"
  echo "Signed ad-hoc (run scripts/create-signing-cert.sh for stable permissions)"
fi
rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
ditto "$STAGE" "$APP"
echo "Built $APP"
