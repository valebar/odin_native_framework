#!/bin/sh
# Builds app/ for macOS and runs it.
set -e
cd "$(dirname "$0")/.."

mkdir -p build/macos
odin build app -debug -out:build/macos/example
# Relative paths in bitmap_from_file resolve against the assets directory next to the executable.
rm -rf build/macos/assets && cp -R app/assets build/macos/assets
./build/macos/example
