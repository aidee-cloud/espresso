#!/bin/bash
# Builds Espresso.app (universal: Apple Silicon + Intel) and a shareable zip.
# Requires only the Xcode Command Line Tools:  xcode-select --install
#
# Optional environment variables:
#   VERSION=1.2.0                        version string (default 1.0.0)
#   BUNDLE_ID=com.yourcompany.espresso   bundle identifier
#   SIGN_IDENTITY="Developer ID Application: Your Co (TEAMID)"   real signing (default: ad-hoc)
#   NOTARY_PROFILE=espresso              notarize with a profile saved via `xcrun notarytool store-credentials`
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Espresso"
VERSION="${VERSION:-1.0.0}"
BUNDLE_ID="${BUNDLE_ID:-com.team.espresso}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUILD="build"
APP="$BUILD/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

echo "→ Cleaning"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  echo "→ Compiling for $arch"
  xcrun swiftc -O -swift-version 5 \
    -target "$arch-apple-macos13.0" -sdk "$SDK" \
    -framework AppKit -framework IOKit -framework ServiceManagement \
    Sources/main.swift -o "$BUILD/$APP_NAME-$arch"
done

echo "→ Creating universal binary"
lipo -create "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"
rm "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64"

echo "→ Writing Info.plist"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" Resources/Info.plist > "$APP/Contents/Info.plist"

if [ -f Resources/AppIcon.png ]; then
  echo "→ Building app icon"
  ICONSET="$BUILD/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

echo "→ Signing ($SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

ZIP="$BUILD/$APP_NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "→ Notarizing"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

echo ""
echo "✓ Built $APP"
echo "✓ Share this file with your team: $ZIP"
