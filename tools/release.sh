#!/usr/bin/env bash
#
# release.sh — build, sign (Developer ID), notarize, staple, and package Cafein
# as a drag-to-Applications DMG. Run locally on your Mac; upload the resulting
# DMG to a GitHub Release.
#
# One-time credential setup (stores your App Store Connect API key in the
# keychain so this script can notarize unattended):
#
#   xcrun notarytool store-credentials cafein-notary \
#       --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 \
#       --key-id XXXXXXXXXX --issuer 00000000-0000-0000-0000-000000000000
#
# Then:
#
#   TEAM_ID=ABCDE12345 ./tools/release.sh
#
set -euo pipefail

SCHEME="cafein"
APP_NAME="Cafein"          # DMG volume / file name (the bundle stays cafein.app)
CONFIG="Release"
TEAM_ID="${TEAM_ID:?Set TEAM_ID to your 10-character Apple Team ID}"
NOTARY_PROFILE="${NOTARY_PROFILE:-cafein-notary}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/cafein.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
STAGE="$BUILD_DIR/dmg"
DMG="$BUILD_DIR/${APP_NAME}.dmg"

rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

echo "▶ Archiving…"
xcodebuild -project "$ROOT/cafein.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIG" \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID"

echo "▶ Exporting with Developer ID…"
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" -exportPath "$EXPORT_DIR"

APP="$EXPORT_DIR/cafein.app"

echo "▶ Building drag-to-Applications DMG…"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo "▶ Notarizing (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶ Stapling ticket…"
xcrun stapler staple "$DMG"

echo "✅ Done: $DMG"
echo "   Upload this to a GitHub Release."
