#!/bin/sh
# Builds app/ for macOS and runs it.
set -e
cd "$(dirname "$0")/.."

mkdir -p build/macos
odin build app -debug -out:build/macos/example
./build/macos/example
