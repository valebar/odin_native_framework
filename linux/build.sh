#!/bin/sh
# Builds app/ for Linux (GTK4) and runs it.
set -e
cd "$(dirname "$0")/.."

OUT=build/linux
mkdir -p "$OUT/libs"

# `-lgtk-4` / `-lcurl` need an unversioned .so, which only the -dev packages install. Without
# one, point the linker at a local symlink to the runtime library.
link_runtime() { # pkg-config name, library name, runtime soname
	if ! pkg-config --exists "$1" 2>/dev/null && [ ! -e "$OUT/libs/lib$2.so" ]; then
		RUNTIME="$(ldconfig -p | awk -v so="$3" '$1 == so {print $NF; exit}')"
		[ -n "$RUNTIME" ] || { echo "$3 not found: install $1" >&2; exit 1; }
		ln -s "$RUNTIME" "$OUT/libs/lib$2.so"
	fi
}
link_runtime gtk4 gtk-4 libgtk-4.so.1
link_runtime libcurl curl libcurl.so.4
# Loaded fonts (font_linux.odin) go through fontconfig and Pango, which GTK4 itself depends on.
link_runtime pango pango-1.0 libpango-1.0.so.0
link_runtime pangocairo pangocairo-1.0 libpangocairo-1.0.so.0
link_runtime pangoft2 pangoft2-1.0 libpangoft2-1.0.so.0
link_runtime fontconfig fontconfig libfontconfig.so.1

odin build app -debug -extra-linker-flags:"-L$PWD/$OUT/libs" -out:"$OUT/example"
# Relative paths in bitmap_from_file resolve against the assets directory next to the executable.
rm -rf "$OUT/assets" && cp -R app/assets "$OUT/assets"
"./$OUT/example"
