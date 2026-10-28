#!/bin/sh
# Builds a universal Harbor.app at the given version and packages it as build/Harbor.dmg.
# With HARBOR_SIGN_IDENTITY set to a Developer ID, the app and disk image are signed with it;
# with NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD (an app-specific password) set too, the disk image is notarized.
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."
version="${1:?usage: release.sh <version>}"

HARBOR_VERSION="$version" ./scripts/bundle-app.sh arm64 x86_64

dmg="build/Harbor.dmg"
contents="build/dmg"
mkdir -p "$contents"
cp -R build/Harbor.app "$contents/"
ln -s /Applications "$contents/Applications"
hdiutil create -volname Harbor -srcfolder "$contents" -fs HFS+ -format UDZO -ov "$dmg"
rm -rf "$contents"

if [ -n "${HARBOR_SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$HARBOR_SIGN_IDENTITY" "$dmg"
fi
if [ -n "${NOTARY_APPLE_ID:-}" ]; then
    xcrun notarytool submit "$dmg" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
    xcrun stapler staple "$dmg"
fi
echo "Built $dmg"
