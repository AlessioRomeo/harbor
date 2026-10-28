#!/bin/sh
# Builds Harbor.app and installs it in ~/Applications.
# The new bundle is staged and moved into place: overwriting the running host's binary in place could get it killed.
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."

swift build -c release --product Harbor
swift build -c release --product harbor-host
bin="$(swift build -c release --show-bin-path)"

stage="build/Harbor.app"
rm -rf build
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Helpers"
cp "$bin/Harbor" "$stage/Contents/MacOS/Harbor"
cp "$bin/harbor-host" "$stage/Contents/Helpers/harbor-host"
cp Resources/Info.plist "$stage/Contents/Info.plist"

codesign --force --sign - --identifier com.alessioromeo.harbor.host "$stage/Contents/Helpers/harbor-host"
codesign --force --sign - "$stage"

install_dir="$HOME/Applications"
mkdir -p "$install_dir"
incoming="$install_dir/.Harbor.app.incoming"
outgoing="$install_dir/.Harbor.app.outgoing"
rm -rf "$incoming" "$outgoing"
cp -R "$stage" "$incoming"
if [ -d "$install_dir/Harbor.app" ]; then
    mv "$install_dir/Harbor.app" "$outgoing"
fi
mv "$incoming" "$install_dir/Harbor.app"
rm -rf "$outgoing"
echo "Installed $install_dir/Harbor.app"
