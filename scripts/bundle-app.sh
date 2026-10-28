#!/bin/sh
# Builds build/Harbor.app. Arguments go to `swift build`, e.g. --arch arm64 --arch x86_64.
# HARBOR_SIGN_IDENTITY picks the signing identity (ad-hoc by default); HARBOR_VERSION sets the bundle version.
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."
identity="${HARBOR_SIGN_IDENTITY:--}"

swift build -c release --product Harbor "$@"
swift build -c release --product harbor-host "$@"
bin="$(swift build -c release --show-bin-path "$@")"

stage="build/Harbor.app"
rm -rf build
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Helpers" "$stage/Contents/Resources"
cp "$bin/Harbor" "$stage/Contents/MacOS/Harbor"
cp "$bin/harbor-host" "$stage/Contents/Helpers/harbor-host"
cp Resources/Info.plist "$stage/Contents/Info.plist"
cp Resources/claude-hook.sh "$stage/Contents/Resources/claude-hook.sh"
cp Resources/AppIcon.icns "$stage/Contents/Resources/AppIcon.icns"

if [ -n "${HARBOR_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $HARBOR_VERSION" "$stage/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$stage/Contents/Info.plist"
fi

set -- --force --options runtime --sign "$identity"
if [ "$identity" != "-" ]; then
    set -- "$@" --timestamp
fi
codesign "$@" --identifier com.alessioromeo.harbor.host "$stage/Contents/Helpers/harbor-host"
codesign "$@" "$stage"
