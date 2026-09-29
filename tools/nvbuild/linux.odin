package nvbuild

// Linux: links against GTK4, libcurl and the font libraries. `-lgtk-4` and the others need an
// unversioned .so, which only the -dev packages install; without one, the runtime library from
// `ldconfig -p` is symlinked into build/linux/libs for the linker.

import "core:os"
import "core:strings"

Runtime_Lib :: struct { pkg, lib, soname: string } // pkg-config name, -l name, runtime soname

RUNTIME_LIBS :: [?]Runtime_Lib{
	{"gtk4", "gtk-4", "libgtk-4.so.1"},
	{"libcurl", "curl", "libcurl.so.4"},
	// Loaded fonts (font_linux.odin) go through fontconfig and Pango, which GTK4 itself depends on.
	{"pango", "pango-1.0", "libpango-1.0.so.0"},
	{"pangocairo", "pangocairo-1.0", "libpangocairo-1.0.so.0"},
	{"pangoft2", "pangoft2-1.0", "libpangoft2-1.0.so.0"},
	{"fontconfig", "fontconfig", "libfontconfig.so.1"},
}

link_runtime :: proc(libs_dir: string, r: Runtime_Lib) {
	if _, ok := capture("pkg-config", "--exists", r.pkg); ok do return
	link := path(libs_dir, strings.concatenate({"lib", r.lib, ".so"}))
	if os.exists(link) do return
	// `ldconfig -p` lines: "\tlibgtk-4.so.1 (libc6,x86-64) => /usr/lib/libgtk-4.so.1"
	out, _ := capture("ldconfig", "-p")
	for line in strings.split_lines_iterator(&out) {
		f := strings.fields(line)
		if len(f) < 2 || f[0] != r.soname do continue
		if err := os.symlink(f[len(f) - 1], link); err != nil do fail("cannot link %s: %v", link, err)
		return
	}
	fail("%s not found: install %s", r.soname, r.pkg)
}

build_linux :: proc(opt: Options) {
	OUT  :: "build/linux"
	LIBS :: OUT + "/libs"
	mkdir(LIBS)
	for r in RUNTIME_LIBS do link_runtime(LIBS, r)
	odin_build(opt, OUT + "/example", strings.concatenate({"-extra-linker-flags:-L", abs(LIBS)}))
	copy_assets(OUT)
	if !opt.no_run do run(abs(OUT + "/example"))
}
