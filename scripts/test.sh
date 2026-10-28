#!/bin/sh
# Swift Testing needs the full Xcode toolchain; xcode-select points at the Command Line Tools.
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."
exec swift test "$@"
