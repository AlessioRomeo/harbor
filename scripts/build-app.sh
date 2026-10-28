#!/bin/sh
# Builds Harbor.app and installs it in ~/Applications.
# The new bundle is staged and moved into place: overwriting the running host's binary in place could get it killed.
set -eu
cd "$(dirname "$0")/.."
./scripts/bundle-app.sh "$@"

stage="build/Harbor.app"
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
