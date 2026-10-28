#!/bin/sh
# Builds build/Harbor.app for the architectures given as arguments (this Mac's by default), e.g. arm64 x86_64.
# HARBOR_SIGN_IDENTITY picks the signing identity (ad-hoc by default); HARBOR_VERSION sets the bundle version.
# Each architecture is built on its own and merged with lipo: a multi-arch `swift build` breaks on SwiftTerm's build plugin with some Xcode versions.
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."
identity="${HARBOR_SIGN_IDENTITY:--}"
if [ $# -eq 0 ]; then
    set -- "$(uname -m)"
fi

build() {
    swift build -c release --arch "$arch" --scratch-path ".build/$arch" "$@"
}

apps=""
hosts=""
for arch in "$@"; do
    build --product Harbor
    build --product harbor-host
    bin="$(build --show-bin-path)"
    bin="${bin#"$PWD"/}"
    apps="$apps $bin/Harbor"
    hosts="$hosts $bin/harbor-host"
done

stage="build/Harbor.app"
rm -rf build
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Helpers" "$stage/Contents/Resources"
lipo -create $apps -output "$stage/Contents/MacOS/Harbor"
lipo -create $hosts -output "$stage/Contents/Helpers/harbor-host"
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
