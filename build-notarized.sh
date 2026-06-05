#!/bin/bash
#
# Build, sign, notarize, and staple AudioPriorityBar.app.
#
# One-time setup before this script will work:
#
#   1. Install a "Developer ID Application" certificate from your Apple
#      Developer account into your login keychain.
#        - Verify with: security find-identity -v -p codesigning
#
#   2. Create an app-specific password at https://appleid.apple.com and
#      store notarytool credentials in the keychain (profile name is
#      arbitrary — match it in NOTARY_PROFILE below):
#        xcrun notarytool store-credentials "AudioPriorityBarNotary" \
#          --apple-id "you@example.com" \
#          --team-id  "YOUR_TEAM_ID" \
#          --password "xxxx-xxxx-xxxx-xxxx"
#
# Env vars (all optional — auto-detected when possible):
#
#   SIGNING_IDENTITY   Full identity string, e.g.
#                      "Developer ID Application: Victor Wang (ABCDE12345)".
#                      Auto-detected if exactly one Developer ID Application
#                      identity is in the keychain.
#   NOTARY_PROFILE     notarytool keychain profile name.
#                      Defaults to "AudioPriorityBarNotary".
#   SKIP_NOTARIZE      Set to 1 to sign-only (still hardened-runtime). Useful
#                      for iterating locally without round-tripping Apple.

set -euo pipefail

cd "$(dirname "$0")"

NOTARY_PROFILE="${NOTARY_PROFILE:-AudioPriorityBarNotary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

if [ -z "${SIGNING_IDENTITY:-}" ]; then
  matches=$(security find-identity -v -p codesigning \
            | grep "Developer ID Application:" \
            | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/' || true)
  count=$(printf '%s\n' "$matches" | grep -c . || true)
  if [ "$count" -eq 1 ]; then
    SIGNING_IDENTITY="$matches"
  elif [ "$count" -eq 0 ]; then
    echo "error: no 'Developer ID Application' identity found in keychain." >&2
    echo "       Install one from your Apple Developer account or set SIGNING_IDENTITY." >&2
    exit 1
  else
    echo "error: multiple Developer ID Application identities found:" >&2
    printf '       %s\n' "$matches" >&2
    echo "       Set SIGNING_IDENTITY to pick one." >&2
    exit 1
  fi
fi

echo "==> Signing identity: $SIGNING_IDENTITY"

# Resolve Xcode if only Command Line Tools are active.
if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
  if [ -d "/Applications/Xcode.app" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  else
    echo "error: Xcode.app not found; install Xcode (not just Command Line Tools)." >&2
    exit 1
  fi
fi

BUILD_DIR=".build"
PRODUCT_DIR="$BUILD_DIR/Build/Products/Release"
APP_PATH="$PRODUCT_DIR/AudioPriorityBar.app"
DIST_DIR="dist"
DIST_APP="$DIST_DIR/AudioPriorityBar.app"
ZIP_PATH="$DIST_DIR/AudioPriorityBar.zip"

echo "==> Building Release (arm64 + x86_64)..."
xcodebuild -scheme AudioPriorityBar \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  build \
  | xcbeautify 2>/dev/null || xcodebuild -scheme AudioPriorityBar \
      -configuration Release \
      -derivedDataPath "$BUILD_DIR" \
      -arch arm64 -arch x86_64 \
      ONLY_ACTIVE_ARCH=NO \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
      OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
      build

# Verify signature has the hardened runtime flag and a secure timestamp.
echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvv "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp|flags" | sed 's/^/    /'

mkdir -p "$DIST_DIR"
rm -rf "$DIST_APP"
cp -R "$APP_PATH" "$DIST_APP"

if [ "$SKIP_NOTARIZE" = "1" ]; then
  echo "==> SKIP_NOTARIZE=1 — signed build only, not notarized."
  echo "    $DIST_APP"
  exit 0
fi

echo "==> Zipping for notarization..."
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$DIST_APP" "$ZIP_PATH"

echo "==> Submitting to Apple notary service (profile: $NOTARY_PROFILE)..."
if ! xcrun notarytool submit "$ZIP_PATH" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait; then
  echo "error: notarization failed. Fetch the log with:" >&2
  echo "       xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE" >&2
  exit 1
fi

echo "==> Stapling ticket..."
xcrun stapler staple "$DIST_APP"

echo "==> Validating staple + Gatekeeper assessment..."
xcrun stapler validate "$DIST_APP"
spctl --assess --type execute --verbose=2 "$DIST_APP"

# Refresh the zip to include the stapled ticket (handy if you distribute the zip).
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$DIST_APP" "$ZIP_PATH"

echo ""
echo "Done: $DIST_APP"
echo "      $ZIP_PATH"
