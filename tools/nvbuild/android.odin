package nvbuild

// Android: app/ becomes libapp.so, packaged with the nv Java embedder into an APK without
// Gradle (javac → jnigen → odin build → d8 → aapt2 → jar → zipalign → apksigner), installed and
// launched over adb on `--device`, else the only attached device, else the AVD started here
// (every adb call passes -s). The SDK, NDK and JDK are found from the environment or the
// per-host default locations. d8 and apksigner are batch
// files on Windows, so they are run the way their wrappers do it, through java, on every host;
// the JDK's jar tool adds the dex and the library to the APK, since `zip` is not everywhere.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Android :: struct {
	sdk, ndk, toolchain, build_tools, jar: string,
	java_home:     string, // "" = the JDK tools on PATH
	adb, emulator: string,
}

OUT_ANDROID :: "build/android"
PKG         :: "com.example.nativelist" // as in android/AndroidManifest.xml
PLATFORM    :: "android-36"

// The SDK from ANDROID_HOME / ANDROID_SDK_ROOT, else the host's default install location; the
// NDK and build-tools are the highest versions installed. `required` false (a check) returns ok
// = false instead of failing when there is no SDK.
android_env :: proc(required: bool) -> (a: Android, ok: bool) {
	home, _ := os.user_home_dir(context.allocator)
	a.sdk = env("ANDROID_HOME")
	if a.sdk == "" do a.sdk = env("ANDROID_SDK_ROOT")
	if a.sdk == "" {
		#partial switch ODIN_OS {
		case .Darwin:  a.sdk = path(home, "Library/Android/sdk")
		case .Linux:   a.sdk = path(home, "Android/Sdk")
		case .Windows: a.sdk = path(env("LOCALAPPDATA"), "Android/Sdk")
		}
	}
	if !os.is_directory(a.sdk) {
		if required do fail("Android SDK not found at %s: set ANDROID_HOME", a.sdk)
		return a, false
	}
	a.ndk = env("ODIN_ANDROID_NDK")
	if a.ndk == "" do a.ndk = highest_version_dir(path(a.sdk, "ndk"))
	if a.ndk == "" do fail("no NDK under %s/ndk: install one, or set ODIN_ANDROID_NDK", a.sdk)
	a.toolchain = env("ODIN_ANDROID_NDK_TOOLCHAIN")
	if a.toolchain == "" {
		// Odin looks for darwin-aarch64; NDKs ship a universal darwin-x86_64 toolchain.
		host := ODIN_OS == .Darwin ? "darwin" : ODIN_OS == .Windows ? "windows" : "linux"
		a.toolchain = path(a.ndk, "toolchains/llvm/prebuilt", strings.concatenate({host, "-x86_64"}))
	}
	a.build_tools = highest_version_dir(path(a.sdk, "build-tools"))
	if a.build_tools == "" do fail("no build-tools under %s", a.sdk)
	a.jar = path(a.sdk, "platforms", PLATFORM, "android.jar")
	if !os.exists(a.jar) do fail("%s not found: install the %s platform", a.jar, PLATFORM)
	a.adb = path(a.sdk, "platform-tools", exe("adb"))
	a.emulator = path(a.sdk, "emulator", exe("emulator"))
	a.java_home = env("JAVA_HOME")
	if a.java_home == "" && ODIN_OS == .Darwin && os.is_directory("/opt/homebrew/opt/openjdk@21") {
		a.java_home = "/opt/homebrew/opt/openjdk@21"
	}
	return a, true
}

// What `odin build` for the android subtarget reads, plus the JDK on PATH for the tools that
// need java; children inherit the tool's environment.
android_export :: proc(a: Android) {
	os.set_env("ODIN_ANDROID_SDK", a.sdk)
	os.set_env("ODIN_ANDROID_NDK", a.ndk)
	os.set_env("ODIN_ANDROID_NDK_TOOLCHAIN", a.toolchain)
	if a.java_home != "" {
		sep := ODIN_OS == .Windows ? ";" : ":"
		os.set_env("PATH", strings.concatenate({path(a.java_home, "bin"), sep, env("PATH")}))
	}
}

env :: proc(key: string) -> string {
	return os.get_env(key, context.allocator)
}

// A JDK tool: from JAVA_HOME, else by name on PATH.
java_tool :: proc(a: Android, name: string) -> string {
	return a.java_home == "" ? name : path(a.java_home, "bin", exe(name))
}

// The highest version-named directory under `parent`, "" if none (10 sorts after 9).
highest_version_dir :: proc(parent: string) -> string {
	entries, err := os.read_all_directory_by_path(parent, context.allocator)
	if err != nil do return ""
	names := make([dynamic]string)
	for e in entries do if e.type == .Directory do append(&names, e.name)
	if len(names) == 0 do return ""
	slice.sort_by(names[:], version_less)
	return path(parent, names[len(names) - 1])
}

version_less :: proc(a, b: string) -> bool {
	a, b := a, b
	seps := []string{".", "-"}
	for {
		x, xok := strings.split_multi_iterate(&a, seps)
		y, yok := strings.split_multi_iterate(&b, seps)
		if !xok || !yok do return int(xok) < int(yok) // the shorter one first
		xi, xn := strconv.parse_int(x)
		yi, yn := strconv.parse_int(y)
		if xn && yn {
			if xi != yi do return xi < yi
		} else if x != y do return x < y
	}
}

// Every .class under `dir`, like `find -name '*.class'`.
class_files :: proc(dir: string) -> []string {
	files := make([dynamic]string)
	w := os.walker_create(dir)
	for info in os.walker_walk(&w) {
		if info.type == .Regular && strings.has_suffix(info.name, ".class") do append(&files, strings.clone(info.fullpath))
	}
	if p, err := os.walker_error(&w); err != nil do fail("cannot list %s: %v", p, err)
	return files[:]
}

// The debug keystore apksigner signs with; made the way Android Studio makes it when missing.
ensure_debug_keystore :: proc(a: Android) -> string {
	home, err := os.user_home_dir(context.allocator)
	if err != nil do fail("no home directory: %v", err)
	ks := path(home, ".android", "debug.keystore")
	if !os.exists(ks) {
		mkdir(path(home, ".android"))
		run(java_tool(a, "keytool"), "-genkeypair", "-keystore", ks, "-storepass", "android", "-keypass", "android",
			"-alias", "androiddebugkey", "-dname", "CN=Android Debug,O=Android,C=US", "-validity", "10000", "-keyalg", "RSA")
	}
	return ks
}

// `adb -s <serial> args..` for run / capture: with two devices attached adb refuses a command
// without -s ("more than one device/emulator").
adb_cmd :: proc(a: Android, serial: string, args: ..string) -> []string {
	cmd := make([dynamic]string)
	append(&cmd, a.adb, "-s", serial)
	append(&cmd, ..args)
	return cmd[:]
}

// `adb devices`: the serials in state "device" (usable) and the rest as "serial (state)"
// ("offline" is still booting, "unauthorized" waits for the USB debugging prompt).
adb_devices :: proc(a: Android) -> (ready, other: []string) {
	out, _ := capture(a.adb, "devices")
	r, o := make([dynamic]string), make([dynamic]string)
	for line in strings.split_lines_iterator(&out) {
		f := strings.fields(line)
		if len(f) < 2 || f[0] == "List" || f[0] == "*" do continue // the header, daemon notices
		if f[1] == "device" do append(&r, f[0])
		else do append(&o, fmt.tprintf("%s (%s)", f[0], f[1]))
	}
	return r[:], o[:]
}

// The device to install on: --device, else the only attached one, else an emulator already
// booting or the AVD started here, polled until sys.boot_completed.
android_device :: proc(a: Android, opt: Options) -> string {
	ready, other := adb_devices(a)
	all := strings.join(slice.concatenate([][]string{ready, other}), ", ")
	if all == "" do all = "none"
	if opt.device != "" {
		if slice.contains(ready, opt.device) do return opt.device
		fail("device %s is not attached; adb devices: %s", opt.device, all)
	}
	switch len(ready) {
	case 1: return ready[0]
	case 0:
	case:   fail("%d devices attached (%s): pick one with --device=<serial>", len(ready), all)
	}
	booting := false
	for d in other do if strings.has_prefix(d, "emulator-") do booting = true
	if !booting do spawn(a.emulator, "-avd", opt.avd)
	for {
		time.sleep(time.Second)
		ready, _ = adb_devices(a)
		for d in ready do if strings.has_prefix(d, "emulator-") {
			if out, _ := capture(..adb_cmd(a, d, "shell", "getprop", "sys.boot_completed")); out == "1" do return d
		}
	}
}

build_android :: proc(opt: Options) {
	a, _ := android_env(true)
	android_export(a)
	stage   :: OUT_ANDROID + "/stage"
	classes :: OUT_ANDROID + "/classes"
	stubs   :: OUT_ANDROID + "/stubs"
	os.remove_all(stage)
	os.remove_all(classes)
	mkdir(stage + "/lib/arm64-v8a")
	mkdir(classes)
	mkdir(stubs)

	// Android has pthreads in libc, but core:thread links -lpthread: satisfy it with an empty archive.
	if !os.exists(stubs + "/libpthread.a") do run(path(a.toolchain, "bin", exe("llvm-ar")), "rc", stubs + "/libpthread.a")

	java, err := os.glob("nv/android/java/nv/*.java")
	if err != nil || len(java) == 0 do fail("no Java shims under nv/android/java/nv")
	javac := make([dynamic]string)
	append(&javac, java_tool(a, "javac"), "--release", "11", "-nowarn", "-cp", a.jar, "-d", classes)
	append(&javac, ..java)
	run(..javac[:])

	// Typed JNI wrappers from nv/android/jni_api.txt, every descriptor checked with javap against
	// android.jar and the nv shims just compiled. The output is committed; a spec change updates it.
	run("odin", "run", "android/jnigen", strings.concatenate({"-out:", exe(OUT_ANDROID + "/jnigen")}), "--",
		strings.concatenate({"-jar:", a.jar}), strings.concatenate({"-classes:", classes}),
		"-spec:nv/android/jni_api.txt", "-out:nv/jni_api_android.odin", strings.concatenate({"-javap:", java_tool(a, "javap")}))

	odin_build(opt, stage + "/lib/arm64-v8a/libapp.so", "-target:linux_arm64", "-subtarget:android", "-build-mode:shared",
		strings.concatenate({"-extra-linker-flags:-L", abs(stubs), " -Wl,-z,max-page-size=16384"}))

	d8 := make([dynamic]string)
	append(&d8, java_tool(a, "java"), "-cp", path(a.build_tools, "lib", "d8.jar"), "com.android.tools.r8.D8",
		"--min-api", "34", "--lib", a.jar, "--output", stage)
	append(&d8, ..class_files(classes))
	run(..d8[:])

	// app/assets become the APK's assets, which bitmap_from_file reads for relative paths.
	unsigned, aligned, apk := OUT_ANDROID + "/unsigned.apk", OUT_ANDROID + "/aligned.apk", OUT_ANDROID + "/NativeList.apk"
	run(path(a.build_tools, exe("aapt2")), "link", "--debug-mode", "-I", a.jar, "--manifest", "android/AndroidManifest.xml",
		"-A", "app/assets", "-o", unsigned)
	run(java_tool(a, "jar"), "ufM", unsigned, "-C", stage, "classes.dex", "-C", stage, "lib") // M: no manifest
	run(path(a.build_tools, exe("zipalign")), "-f", "-p", "4", unsigned, aligned)
	run(java_tool(a, "java"), "-jar", path(a.build_tools, "lib", "apksigner.jar"), "sign", "--ks", ensure_debug_keystore(a),
		"--ks-pass", "pass:android", "--key-pass", "pass:android", "--out", apk, aligned)
	if opt.no_run do return

	serial := android_device(a, opt)
	run(..adb_cmd(a, serial, "install", "-r", apk))
	run(..adb_cmd(a, serial, "logcat", "-c"))
	run(..adb_cmd(a, serial, "shell", "am", "start", "-n", PKG + "/nv.NvActivity"))
	fmt.printfln("logs: %s -s %s logcat -s nv AndroidRuntime", a.adb, serial)
}
