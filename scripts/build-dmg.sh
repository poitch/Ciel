#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------------
# build-dmg.sh — Build, sign, notarize, and package Ciel.app as DMG
# ------------------------------------------------------------------
#
# Prerequisites:
#   - Xcode command-line tools
#   - "Developer ID Application" certificate in Keychain
#   - App Store Connect API key or notarytool credentials stored via:
#       xcrun notarytool store-credentials "Ciel"
#         --apple-id <apple-id>
#         --team-id <team-id>
#         --password <app-specific-password>
#
# Usage:
#   ./scripts/build-dmg.sh
#
# Environment overrides:
#   TEAM_ID           — Developer team ID       (default: 3Z43FVDUGG)
#   SIGN_IDENTITY     — Code signing identity    (default: "Developer ID Application")
#   NOTARIZE_PROFILE  — notarytool profile name  (default: "Ciel")
#   SKIP_NOTARIZE     — set to 1 to skip notarization (for testing)
# ------------------------------------------------------------------

APP_NAME="Ciel"
SCHEME="Ciel"
BUNDLE_ID="cards.enchanted.Ciel"

TEAM_ID="${TEAM_ID:-3Z43FVDUGG}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-Ciel}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
DMG_DIR="${BUILD_DIR}/dmg"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"

# Generate version: YYYY.WW.nn where nn = total commit count
COMMIT_COUNT=$(git -C "${PROJECT_DIR}" rev-list --count HEAD)
VERSION="$(date +%Y).$(date +%V).${COMMIT_COUNT}"
BUILD_NUMBER="${COMMIT_COUNT}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

info()  { printf "\033[1;34m==>\033[0m \033[1m%s\033[0m\n" "$*"; }
error() { printf "\033[1;31merror:\033[0m %s\n" "$*" >&2; exit 1; }

check_identity() {
    if ! security find-identity -v -p codesigning | grep -q "${SIGN_IDENTITY}"; then
        error "No \"${SIGN_IDENTITY}\" certificate found in Keychain.

To distribute outside the App Store you need a Developer ID Application certificate.
  1. Open Xcode -> Settings -> Accounts -> Manage Certificates
  2. Click + and choose \"Developer ID Application\"

Or set SIGN_IDENTITY to an available identity."
    fi
}

# ------------------------------------------------------------------
# Clean
# ------------------------------------------------------------------

info "Cleaning build directory"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${EXPORT_DIR}" "${DMG_DIR}"

# ------------------------------------------------------------------
# Verify signing identity
# ------------------------------------------------------------------

info "Checking signing identity: ${SIGN_IDENTITY}"
check_identity

# ------------------------------------------------------------------
# Archive
# ------------------------------------------------------------------

info "Archiving ${APP_NAME} (v${VERSION}, build ${BUILD_NUMBER})"
xcodebuild archive \
    -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=macOS" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
    CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    | tail -1

# ------------------------------------------------------------------
# Export
# ------------------------------------------------------------------

info "Exporting application"

EXPORT_OPTIONS="${BUILD_DIR}/ExportOptions.plist"
cat > "${EXPORT_OPTIONS}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>${SIGN_IDENTITY}</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    | tail -1

[ -d "${APP_PATH}" ] || error "Export failed — ${APP_PATH} not found"

# ------------------------------------------------------------------
# Verify signature
# ------------------------------------------------------------------

info "Verifying code signature"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 | tail -3
spctl --assess --type execute --verbose "${APP_PATH}" 2>&1 || true

# ------------------------------------------------------------------
# Notarize
# ------------------------------------------------------------------

if [ "${SKIP_NOTARIZE}" != "1" ]; then
    info "Notarizing ${APP_NAME}.app"

    NOTARIZE_ZIP="${BUILD_DIR}/${APP_NAME}-notarize.zip"
    ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"

    xcrun notarytool submit "${NOTARIZE_ZIP}" \
        --keychain-profile "${NOTARIZE_PROFILE}" \
        --wait

    info "Stapling notarization ticket"
    xcrun stapler staple "${APP_PATH}"

    rm -f "${NOTARIZE_ZIP}"
else
    info "Skipping notarization (SKIP_NOTARIZE=1)"
fi

# ------------------------------------------------------------------
# Create DMG
# ------------------------------------------------------------------

info "Creating DMG"

# Stage DMG contents: app + symlink to /Applications
mkdir -p "${DMG_DIR}"
cp -R "${APP_PATH}" "${DMG_DIR}/"
ln -sf /Applications "${DMG_DIR}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_PATH}"

# Sign the DMG itself
info "Signing DMG"
codesign --sign "${SIGN_IDENTITY}" --timestamp "${DMG_PATH}"

# Notarize the DMG
if [ "${SKIP_NOTARIZE}" != "1" ]; then
    info "Notarizing DMG"
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARIZE_PROFILE}" \
        --wait

    xcrun stapler staple "${DMG_PATH}"
fi

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------

info "Done! DMG ready at:"
echo "  ${DMG_PATH}"
echo ""
echo "  Size: $(du -h "${DMG_PATH}" | cut -f1)"
echo "  SHA-256: $(shasum -a 256 "${DMG_PATH}" | cut -d' ' -f1)"
