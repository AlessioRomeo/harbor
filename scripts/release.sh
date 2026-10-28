#!/bin/sh
# Builds a universal Harbor.app at the given version and packages it as build/Harbor.dmg, laid out by scripts/dmg-settings.py.
# With HARBOR_SIGN_IDENTITY set to a Developer ID, the app and disk image are signed with it;
# with NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD (an app-specific password) set too, the disk image is notarized.
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."
version="${1:?usage: release.sh <version>}"

HARBOR_VERSION="$version" ./scripts/bundle-app.sh arm64 x86_64

dmg="build/Harbor.dmg"
python3 -m venv build/dmgbuild
build/dmgbuild/bin/pip install --quiet --require-virtualenv -r scripts/dmg-requirements.txt
build/dmgbuild/bin/dmgbuild -s scripts/dmg-settings.py -D app=build/Harbor.app Harbor "$dmg"

if [ -n "${HARBOR_SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$HARBOR_SIGN_IDENTITY" "$dmg"
fi
if [ -n "${NOTARY_APPLE_ID:-}" ]; then
    xcrun notarytool submit "$dmg" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
    xcrun stapler staple "$dmg"
fi
echo "Built $dmg"
