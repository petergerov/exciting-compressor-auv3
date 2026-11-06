#!/bin/bash
# Builds a Developer ID-signed (and optionally notarized) macOS installer package.
#
#   scripts/make-installer.sh                            # build + sign
#   NOTARY_PROFILE=<profile> scripts/make-installer.sh   # build + sign + notarize + staple
#
# Signing settings come from .env (see .env.example). Create a notary profile once with:
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <DEVELOPMENT_TEAM>
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
source scripts/load-env.sh
load_env "$ROOT"
require_env DEVELOPMENT_TEAM BUNDLE_ID_PREFIX INSTALLER_IDENTITY

OUT="$ROOT/build/installer"
ARCHIVE="$OUT/ExcitingCompressor.xcarchive"
EXPORT="$OUT/export"
PKG_ID="$BUNDLE_ID_PREFIX.ExcitingCompressor.app"

VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)
PKG="$OUT/ExcitingCompressor-$VERSION.pkg"

step() { printf '\n▸ %s\n' "$1"; }

rm -rf "$OUT" && mkdir -p "$OUT"

step "Generating Xcode project"
scripts/generate-project.sh

step "Archiving Release build (universal)"
xcodebuild archive \
    -project ExcitingCompressor.xcodeproj \
    -scheme ExcitingCompressor_macOS \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    -quiet

step "Exporting with Developer ID signing"
EXPORT_OPTIONS="$OUT/ExportOptions.plist"
cp Config/ExportOptions-DeveloperID.plist "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string $DEVELOPMENT_TEAM" "$EXPORT_OPTIONS"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    -quiet
APP="$EXPORT/ExcitingCompressor.app"

step "Verifying code signature"
codesign --verify --deep --strict --verbose=1 "$APP"
lipo -archs "$APP/Contents/PlugIns/ExcitingCompressorExtension.appex/Contents/MacOS/ExcitingCompressorExtension"

step "Building component package"
# Stage only the app: the export folder also holds Xcode logs and plists.
STAGE="$OUT/root"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/ExcitingCompressor.app"
pkgbuild --analyze --root "$STAGE" "$OUT/components.plist" >/dev/null
# Install to /Applications even if a copy exists elsewhere (e.g. a DerivedData build).
/usr/libexec/PlistBuddy -c "Delete :0:BundleIsRelocatable" "$OUT/components.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$OUT/components.plist"
pkgbuild \
    --root "$STAGE" \
    --component-plist "$OUT/components.plist" \
    --install-location /Applications \
    --scripts Config/Installer/scripts \
    --identifier "$PKG_ID" \
    --version "$VERSION" \
    "$OUT/ExcitingCompressor-component.pkg"

step "Building signed product archive"
sed -e "s/__VERSION__/$VERSION/" \
    -e "s/__BUNDLE_ID_PREFIX__/$BUNDLE_ID_PREFIX/" \
    -e "s/__PKG_ID__/$PKG_ID/" \
    Config/Installer/distribution.xml > "$OUT/distribution.xml"
productbuild \
    --distribution "$OUT/distribution.xml" \
    --package-path "$OUT" \
    --sign "$INSTALLER_IDENTITY" \
    "$PKG"
pkgutil --check-signature "$PKG" | head -3

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    step "Notarizing (this can take a few minutes)"
    xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$PKG"
    spctl --assess --type install --verbose "$PKG"
else
    step "Skipping notarization (set NOTARY_PROFILE to enable)"
fi

printf '\n✓ %s\n' "$PKG"
