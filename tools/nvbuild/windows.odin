package nvbuild

// Windows: a plain executable with the manifest from windows/app.rc (Common Controls v6, DPI
// awareness) embedded, run with the console attached.

build_windows :: proc(opt: Options) {
	OUT :: "build/windows"
	mkdir(OUT)
	odin_build(opt, OUT + "/example.exe", "-resource:windows\\app.rc")
	copy_assets(OUT)
	if !opt.no_run do run(abs(OUT + "/example.exe"))
}
