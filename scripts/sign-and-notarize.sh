#!/bin/bash
#
# Build, sign, and notarize AudioPriorityBar for distribution
#
# Prerequisites:
#   1. Apple Developer Program membership ($99/year)
#   2. Developer ID Application certificate installed in Keychain
#   3. App-specific password for notarization (create at appleid.apple.com)
#
# Environment variables required:
#   DEVELOPER_ID_APPLICATION  - Your signing identity (e.g., "Developer ID Application: Your Name (TEAMID)")
#   APPLE_ID                  - Your Apple ID email
#   APPLE_TEAM_ID             - Your 10-character Team ID
#   NOTARIZATION_PASSWORD     - App-specific password (or @keychain:notarization for keychain)
#
# Usage:
#   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
#   export APPLE_ID="your@email.com"
#   export APPLE_TEAM_ID="ABCD123456"
#   export NOTARIZATION_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   ./scripts/sign-and-notarize.sh
#
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() { echo -e "${GREEN}==>${NC} $1"; }
echo_warn() { echo -e "${YELLOW}Warning:${NC} $1"; }
echo_error() { echo -e "${RED}Error:${NC} $1"; }

# Configuration
APP_NAME="AudioPriorityBar"
BUNDLE_ID="com.example.AudioPriorityBar"  # TODO: Change this to your bundle ID
ENTITLEMENTS="AudioPriorityBar/AudioPriorityBar.entitlements"
OUTPUT_DIR="dist"
BUILD_DIR=".build"

# Validate environment
check_env() {
    local missing=0

    if [ -z "$DEVELOPER_ID_APPLICATION" ]; then
        echo_error "DEVELOPER_ID_APPLICATION not set"
        echo "  Find yours with: security find-identity -v -p codesigning"
        missing=1
    fi

    if [ -z "$APPLE_ID" ]; then
        echo_error "APPLE_ID not set"
        missing=1
    fi

    if [ -z "$APPLE_TEAM_ID" ]; then
        echo_error "APPLE_TEAM_ID not set"
        echo "  Find yours at: https://developer.apple.com/account -> Membership"
        missing=1
    fi

    if [ -z "$NOTARIZATION_PASSWORD" ]; then
        echo_error "NOTARIZATION_PASSWORD not set"
        echo "  Create one at: https://appleid.apple.com -> App-Specific Passwords"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        exit 1
    fi
}

# Build the app
build_app() {
    echo_step "Building ${APP_NAME}..."

    xcodebuild -scheme "$APP_NAME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        -arch arm64 -arch x86_64 \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        clean build | xcbeautify 2>/dev/null || xcodebuild -scheme "$APP_NAME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        -arch arm64 -arch x86_64 \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        clean build

    mkdir -p "$OUTPUT_DIR"
    rm -rf "${OUTPUT_DIR}/${APP_NAME}.app"
    cp -R "${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app" "$OUTPUT_DIR/"

    echo_step "Build complete"
}

# Sign the app
sign_app() {
    echo_step "Signing ${APP_NAME}.app..."

    # Sign with hardened runtime and entitlements
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "${OUTPUT_DIR}/${APP_NAME}.app"

    # Verify signature
    echo_step "Verifying signature..."
    codesign --verify --verbose=2 "${OUTPUT_DIR}/${APP_NAME}.app"

    # Check Gatekeeper assessment
    echo_step "Checking Gatekeeper assessment..."
    spctl --assess --type execute --verbose=2 "${OUTPUT_DIR}/${APP_NAME}.app" || {
        echo_warn "Gatekeeper assessment failed (expected before notarization)"
    }

    echo_step "Signing complete"
}

# Create ZIP for notarization
create_zip() {
    echo_step "Creating ZIP archive..."

    cd "$OUTPUT_DIR"
    rm -f "${APP_NAME}.zip"
    ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"
    cd - > /dev/null

    echo_step "Created ${OUTPUT_DIR}/${APP_NAME}.zip"
}

# Submit for notarization
notarize_app() {
    echo_step "Submitting for notarization..."
    echo "  This may take several minutes..."

    xcrun notarytool submit "${OUTPUT_DIR}/${APP_NAME}.zip" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$NOTARIZATION_PASSWORD" \
        --wait

    echo_step "Notarization complete"
}

# Staple the notarization ticket
staple_app() {
    echo_step "Stapling notarization ticket..."

    xcrun stapler staple "${OUTPUT_DIR}/${APP_NAME}.app"

    echo_step "Stapling complete"
}

# Final verification
verify_app() {
    echo_step "Final Gatekeeper verification..."

    spctl --assess --type execute --verbose=2 "${OUTPUT_DIR}/${APP_NAME}.app"

    echo ""
    echo -e "${GREEN}Success!${NC} ${APP_NAME}.app is now signed, notarized, and ready for distribution."
    echo ""
    echo "Output: ${OUTPUT_DIR}/${APP_NAME}.app"
}

# Create final DMG (optional)
create_dmg() {
    echo_step "Creating DMG..."

    rm -f "${OUTPUT_DIR}/${APP_NAME}.dmg"

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "${OUTPUT_DIR}/${APP_NAME}.app" \
        -ov -format UDZO \
        "${OUTPUT_DIR}/${APP_NAME}.dmg"

    # Sign the DMG too
    codesign --force --sign "$DEVELOPER_ID_APPLICATION" "${OUTPUT_DIR}/${APP_NAME}.dmg"

    # Notarize the DMG
    xcrun notarytool submit "${OUTPUT_DIR}/${APP_NAME}.dmg" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$NOTARIZATION_PASSWORD" \
        --wait

    xcrun stapler staple "${OUTPUT_DIR}/${APP_NAME}.dmg"

    echo_step "Created ${OUTPUT_DIR}/${APP_NAME}.dmg"
}

# Main
main() {
    echo ""
    echo "=========================================="
    echo "  AudioPriorityBar Build & Notarization"
    echo "=========================================="
    echo ""

    check_env
    build_app
    sign_app
    create_zip
    notarize_app
    staple_app
    verify_app

    # Optionally create DMG (uncomment to enable)
    # create_dmg

    echo ""
    echo "Done!"
}

main "$@"
