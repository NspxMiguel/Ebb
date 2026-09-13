#!/bin/bash
# Builds Ebb.app (universal binary) into ./build.
set -euo pipefail

cd "$(dirname "$0")"

VERSION="$(cat VERSION 2>/dev/null || echo 1.0.0)"
VERSION_IN_CODE="$(grep 'public static let current' Sources/EbbCore/Version.swift | sed 's/.*= "//' | sed 's/".*//')"

if [ "$VERSION" != "$VERSION_IN_CODE" ]; then
  echo "ERROR: VERSION ($VERSION) does not match Sources/EbbCore/Version.swift ($VERSION_IN_CODE)"
  exit 1
fi

APP="build/Ebb.app"
BUNDLE_ID="com.ebb.app"

ARCH_FLAGS="--arch arm64 --arch x86_64"
if [ "${1:-}" = "--no-universal" ]; then
  ARCH_FLAGS=""
fi

echo "==> Compiling (release$([[ -z "$ARCH_FLAGS" ]] && echo ", $(uname -m)" || echo ", arm64 + x86_64"))"
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS --product Ebb
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS --product EbbCLI
# A universal build lands in .build/apple/Products/Release, a single-arch one
# in .build/<triple>/release; ask SwiftPM instead of guessing.
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/Ebb" "$APP/Contents/MacOS/Ebb"
cp "$BIN/EbbCLI" "$APP/Contents/Helpers/ebb"

echo "==> Drawing the icon"
rm -rf build/AppIcon.iconset
swift Tools/makeicon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf build/AppIcon.iconset

cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Ebb</string>
    <key>CFBundleDisplayName</key><string>Ebb</string>
    <key>CFBundleExecutable</key><string>Ebb</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 KeepOK</string>
    <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# A file copied out of a tarball can arrive quarantined; clear it before signing.
xattr -cr "$APP"

# Ad-hoc signing changes the cdhash on every build, and the keychain remembers
# "Always Allow" per designated requirement: every rebuild would ask again for
# the app password. A local certificate pins the requirement to the certificate,
# which does not change. Whoever installs through the tap has no such
# certificate and gets ad-hoc, which is fine for a fresh install.
SIGN_ID="NSPX Local Code Signing"
SIGN_KEYCHAIN="$HOME/Library/Keychains/nspx-codesign.keychain-db"
signed_locally=false

if [ -f "$SIGN_KEYCHAIN" ] && security find-identity -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "==> Signing with $SIGN_ID"
  if codesign --force --sign "$SIGN_ID" --keychain "$SIGN_KEYCHAIN" "$APP/Contents/Helpers/ebb" 2>/tmp/ebb-codesign.log &&
    codesign --force --sign "$SIGN_ID" --keychain "$SIGN_KEYCHAIN" "$APP" 2>>/tmp/ebb-codesign.log; then
    signed_locally=true
  else
    echo "==> Local signing failed ($(tail -1 /tmp/ebb-codesign.log)), falling back to ad-hoc"
  fi
fi

if [ "$signed_locally" = false ]; then
  echo "==> Signing (ad-hoc)"
  codesign --force --sign - "$APP/Contents/Helpers/ebb"
  codesign --force --sign - "$APP"
fi

echo "==> Done: $APP ($VERSION)"
echo "==> CLI at: $APP/Contents/Helpers/ebb"
