#!/bin/sh
# Builds app/ for Linux (GTK4) and runs it.
set -e
cd "$(dirname "$0")/.."

OUT=build/linux
mkdir -p "$OUT/libs"

# `-lgtk-4` needs an unversioned libgtk-4.so, which only the -dev package installs. Without it,
# point the linker at a local symlink to the runtime library.
if ! pkg-config --exists gtk4 2>/dev/null && [ ! -e "$OUT/libs/libgtk-4.so" ]; then
	RUNTIME="$(ldconfig -p | awk '/libgtk-4\.so\.1 / {print $NF; exit}')"
	[ -n "$RUNTIME" ] || { echo "libgtk-4.so.1 not found: install GTK 4" >&2; exit 1; }
	ln -s "$RUNTIME" "$OUT/libs/libgtk-4.so"
fi

odin build app -debug -extra-linker-flags:"-L$PWD/$OUT/libs" -out:"$OUT/example"
"./$OUT/example"
