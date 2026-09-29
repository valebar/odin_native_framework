package nvbuild

// macOS: a plain executable. iOS: a simulator bundle (Info.plist and assets inside the .app),
// signed ad hoc, installed on the booted simulator and launched with a console attached.

import "core:os"

build_macos :: proc(opt: Options) {
	OUT :: "build/macos"
	mkdir(OUT)
	odin_build(opt, OUT + "/example")
	copy_assets(OUT)
	if !opt.no_run do run(abs(OUT + "/example"))
}

build_ios :: proc(opt: Options) {
	APP       :: "build/ios/NativeList.app"
	BUNDLE_ID :: "com.example.nativelist" // as in ios/Info.plist, with the executable name
	mkdir(APP)
	odin_build(opt, APP + "/NativeList", "-target:darwin_arm64", "-subtarget:iphonesimulator", "-minimum-os-version:17.0")
	if err := os.copy_file(APP + "/Info.plist", "ios/Info.plist"); err != nil do fail("cannot copy ios/Info.plist: %v", err)
	copy_assets(APP)
	run("codesign", "--force", "-s", "-", APP)
	if opt.no_run do return
	capture("xcrun", "simctl", "boot", opt.sim)        // fails when already booted
	capture("open", "-b", "com.apple.iphonesimulator") // the GUI is optional
	run("xcrun", "simctl", "install", "booted", APP)
	run("xcrun", "simctl", "launch", "--console-pty", "--terminate-running-process", "booted", BUNDLE_ID)
}
