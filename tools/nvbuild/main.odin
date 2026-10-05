package nvbuild

// The build tool: one program for every platform, replacing per-OS shell scripts.
//
//   odin run tools/nvbuild -- [build|check|clean] [--platform=windows|macos|ios|android|linux|all]
//                              [--release|--debug] [--no-run] [--sim="iPhone 17"] [--avd=Pixel_10] [--device=<serial>]
//                              [--team=<id>] [--any-odin]
//
// `build` (the default) compiles app/ for the platform (this host when none is given), packages
// it (assets next to the executable, the iOS bundle, the APK) and runs it with the console
// attached. `check` type-checks nv and app with -vet and -strict-style for one target, or every
// target with `all` (plus this tool and android/jnigen): the cross-target checks work from any
// host. `clean` removes build/<platform>, or all of build/.
// Every command but `clean` first makes sure that odin is the pinned compiler (ODIN_PIN);
// --any-odin skips that, to try another one.
// Every command it spawns is echoed with a leading `+`, and the first failing one ends the build
// with its exit code. The output lives under build/<platform>/; the tool's own binary is left in
// the cwd by `odin run` (nvbuild, gitignored), which is why the package is not called `build`.
// The tool never frees: it is a short-lived process.

import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

Command  :: enum { build, check, clean }
Platform :: enum { host, windows, macos, ios, android, linux, all } // lowercase: flags matches the names

Options :: struct {
	command:  Command  `args:"pos=0" usage:"build (the default: build, package and run) | check | clean"`,
	platform: Platform `usage:"windows | macos | ios | android | linux (default: this host); all for check and clean"`,
	release:  bool     `usage:"optimized build (-o:speed)"`,
	debug:    bool     `usage:"debug build (-debug), the default"`,
	no_run:   bool     `usage:"build and package only, do not launch the app"`,
	sim:      string   `usage:"iOS simulator, by name or UDID, to boot, install on and launch (default: iPhone 17)"`,
	avd:      string   `usage:"Android AVD to start when no device is attached (default: Pixel_10)"`,
	device:   string   `usage:"Android: device serial from adb devices (default: the only attached device, else the emulator started from --avd). iOS: a physical device, by name or UDID from xcrun devicectl list devices (default: the simulator)"`,
	team:     string   `usage:"Apple team id whose provisioning profile signs an iOS device build (default: the first profile that fits)"`,
	any_odin: bool     `usage:"do not require the pinned Odin (ODIN_PIN): try another compiler before moving the pin"`,
}

SIM_DEFAULT :: "iPhone 17"
AVD_DEFAULT :: "Pixel_10"

// The Odin this repo is built with, as `odin version` prints it; only the hash is compared. How the
// compiler links a shared library decides how libapp.so starts (nv/app_android.odin), so the pin
// moves only through the upgrade steps in CLAUDE.md (Commands, compiler pin).
ODIN_PIN :: "dev-2026-09-nightly:a2fb372"

ROOT :: #directory + "/../.." // the repo, whatever the cwd `odin run` was given

main :: proc() {
	root, _ := os.clean_path(ROOT, context.allocator)
	if err := os.set_working_directory(root); err != nil do fail("cannot enter %s: %v", root, err)

	opt: Options
	flags.parse_or_exit(&opt, os.args, .Unix)
	if opt.release && opt.debug do fail("--release and --debug exclude each other")
	if opt.sim == "" do opt.sim = SIM_DEFAULT
	if opt.avd == "" do opt.avd = AVD_DEFAULT
	if opt.platform == .host do opt.platform = host_platform()
	if opt.command != .clean { // clean compiles nothing
		if opt.any_odin do fmt.printfln("nvbuild: --any-odin: Odin %s:%s, the pin is %s", ODIN_VERSION, ODIN_VERSION_HASH, ODIN_PIN)
		else do odin_pin_check()
	}

	start := time.tick_now()
	switch opt.command {
	case .build:
		#partial switch opt.platform {
		case .windows: build_windows(opt)
		case .macos:   build_macos(opt)
		case .ios:     build_ios(opt)
		case .android: build_android(opt)
		case .linux:   build_linux(opt)
		case:          fail("build needs one platform, not %v", opt.platform)
		}
	case .check: check(opt)
	case .clean: clean(opt)
	}
	fmt.printfln("nvbuild: %v done in %.1fs", opt.command, time.duration_seconds(time.tick_since(start)))
}

host_platform :: proc() -> Platform {
	#partial switch ODIN_OS {
	case .Windows: return .windows
	case .Darwin:  return .macos
	case .Linux:   return .linux
	}
	fail("no backend for %v", ODIN_OS)
}

fail :: proc(format: string, args: ..any) -> ! {
	fmt.eprint("nvbuild: ")
	fmt.eprintfln(format, ..args)
	os.exit(1)
}

// ---- compiler pin ----

// Stops unless the compiler is the pinned one: the one that built this tool (`odin run` rebuilds
// it every time) and the `odin` on PATH that the tool spawns. They are normally the same binary;
// a stale ./nvbuild or an odin run by its full path makes them differ.
odin_pin_check :: proc() {
	if !odin_pinned(ODIN_VERSION_HASH) {
		fail("this tool was built by Odin %s:%s, but the repo is pinned to %s: install that one, or pass --any-odin", ODIN_VERSION, ODIN_VERSION_HASH, ODIN_PIN)
	}
	version, ok := capture_quiet("odin", "version") // "odin version dev-2026-09-nightly:a2fb372"
	if !ok do fail("cannot run `odin version`: the pinned Odin %s must be on PATH", ODIN_PIN)
	if !odin_pinned(odin_hash(version)) do fail("the odin on PATH is %q, not the pinned %s: fix PATH, or pass --any-odin", version, ODIN_PIN)
}

// The git hash after the last colon: "dev-2026-09-nightly:a2fb372" -> "a2fb372".
odin_hash :: proc(version: string) -> string {
	return version[strings.last_index_byte(version, ':') + 1:]
}

// Compared as prefixes, since the hash's length depends on the clone the compiler was built from
// (an Odin built from source at the pinned commit matches too). Empty (no .git at build) never does.
odin_pinned :: proc(hash: string) -> bool {
	pin := odin_hash(ODIN_PIN)
	return len(hash) >= 7 && (strings.has_prefix(hash, pin) || strings.has_prefix(pin, hash))
}

// ---- processes ----

// Prints the command the way `set -x` would, so a failure shows what ran.
echo :: proc(cmd: []string) {
	b := strings.builder_make()
	strings.write_string(&b, "+")
	for a in cmd {
		strings.write_byte(&b, ' ')
		if strings.contains_any(a, " \"") {
			fmt.sbprintf(&b, "%q", a)
		} else {
			strings.write_string(&b, a)
		}
	}
	fmt.println(strings.to_string(b))
}

// Runs a command with the console attached and waits; a non-zero exit ends the build with it.
run :: proc(cmd: ..string) {
	if code, ok := run_wait(cmd); !ok do os.exit(code)
}

// `run`, but a failure is reported by the result instead of ending the build.
try_run :: proc(cmd: ..string) -> bool {
	_, ok := run_wait(cmd)
	return ok
}

run_wait :: proc(cmd: []string) -> (code: int, ok: bool) {
	echo(cmd)
	// nil stdio would discard the child's output; the standard handles are inherited.
	p, err := os.process_start({command = cmd, stdin = os.stdin, stdout = os.stdout, stderr = os.stderr})
	if err != nil do fail("cannot run %s: %v", cmd[0], err)
	state, werr := os.process_wait(p)
	if werr != nil do fail("waiting for %s: %v", cmd[0], werr)
	if state.exit_code != 0 { // `success` is always true on Windows
		fmt.eprintfln("nvbuild: %s exited with %d", cmd[0], state.exit_code)
		return state.exit_code, false
	}
	return 0, true
}

// Runs a command with its output captured; `ok` is false when it is missing or fails, which is
// the normal answer for the probes (pkg-config --exists, adb get-state, ..).
capture :: proc(cmd: ..string) -> (stdout: string, ok: bool) {
	echo(cmd)
	return capture_quiet(..cmd)
}

// `capture` without the echo, for a probe that runs once per file.
capture_quiet :: proc(cmd: ..string) -> (stdout: string, ok: bool) {
	state, out, _, err := os.process_exec({command = cmd}, context.allocator)
	if err != nil do return "", false
	return strings.trim_space(string(out)), state.exit_code == 0
}

// Starts a process and forgets it (the emulator): its output is discarded and it is never waited for.
spawn :: proc(cmd: ..string) {
	echo(cmd)
	if _, err := os.process_start({command = cmd}); err != nil do fail("cannot run %s: %v", cmd[0], err)
}

// ---- shared build steps ----

exe :: proc(name: string) -> string {
	return ODIN_OS == .Windows ? strings.concatenate({name, ".exe"}) : name
}

opt_flag :: proc(opt: Options) -> string {
	return opt.release ? "-o:speed" : "-debug"
}

// `odin build app` with the optimization flag, the platform's extra flags and the output path.
odin_build :: proc(opt: Options, out: string, extra: ..string) {
	cmd := make([dynamic]string)
	append(&cmd, "odin", "build", "app", opt_flag(opt))
	append(&cmd, ..extra)
	append(&cmd, strings.concatenate({"-out:", out}))
	run(..cmd[:])
}

// A fresh copy of app/assets in `dir`: bitmap_from_file resolves relative paths against it.
copy_assets :: proc(dir: string) {
	dst := path(dir, "assets")
	os.remove_all(dst)
	if err := os.copy_directory_all(dst, "app/assets"); err != nil do fail("cannot copy app/assets to %s: %v", dst, err)
}

mkdir :: proc(dir: string) {
	if os.is_directory(dir) do return // make_directory_all reports an existing path as .Exist
	if err := os.make_directory_all(dir); err != nil do fail("cannot create %s: %v", dir, err)
}

abs :: proc(p: string) -> string {
	a, err := os.get_absolute_path(p, context.allocator)
	if err != nil do fail("cannot resolve %s: %v", p, err)
	return a
}

path :: proc(elems: ..string) -> string {
	p, _ := os.join_path(elems, context.allocator)
	return p
}

// ---- check ----

// The targets `check` covers per platform. iOS is two: the simulator and the device are separate
// subtargets, and `#+build darwin:ios` (not in Odin's docs, see CLAUDE.md) has to pick the iOS
// backend for both.
target_flags := [Platform][][]string{
	.host    = {},
	.windows = {{"-target:windows_amd64"}},
	.macos   = {{"-target:darwin_arm64"}},
	.ios     = {{"-target:darwin_arm64", "-subtarget:iphonesimulator"}, {"-target:darwin_arm64", "-subtarget:iphone"}},
	.android = {{"-target:linux_arm64", "-subtarget:android"}},
	.linux   = {{"-target:linux_amd64"}},
	.all     = {},
}

// Type-checks nv and app with -vet and -strict-style for the platform, or for every one with `all`,
// which also checks the two host programs; failures are listed at the end. An Android check only
// needs the ODIN_ANDROID_* variables to be set, not a real SDK.
check :: proc(opt: Options) {
	platforms: []Platform = {opt.platform}
	if opt.platform == .all do platforms = {.windows, .macos, .ios, .android, .linux}
	failed := make([dynamic]string)
	for p in platforms {
		if p == .android {
			if a, ok := android_env(false); ok do android_export(a)
			else do for key in ([]string{"ODIN_ANDROID_SDK", "ODIN_ANDROID_NDK", "ODIN_ANDROID_NDK_TOOLCHAIN"}) {
				if _, set := os.lookup_env(key, context.allocator); !set do os.set_env(key, "x")
			}
		}
		for flags in target_flags[p] {
			for pkg in ([]string{"nv", "app"}) {
				cmd := make([dynamic]string)
				append(&cmd, "odin", "check", pkg, "-vet", "-strict-style")
				if pkg == "nv" do append(&cmd, "-no-entry-point")
				append(&cmd, ..flags)
				if !try_run(..cmd[:]) do append(&failed, fmt.tprintf("%s for %s", pkg, strings.join(flags, " ")))
			}
		}
	}
	if opt.platform == .all {
		for pkg in ([]string{"tools/nvbuild", "android/jnigen"}) {
			if !try_run("odin", "check", pkg, "-vet", "-strict-style") do append(&failed, pkg)
		}
	}
	if len(failed) > 0 do fail("check failed: %s", strings.join(failed[:], ", "))
}

// ---- clean ----

clean :: proc(opt: Options) {
	dir := opt.platform == .all ? "build" : path("build", fmt.tprint(opt.platform))
	fmt.printfln("+ remove %s", dir)
	if err := os.remove_all(dir); err != nil && err != os.General_Error.Not_Exist {
		fail("cannot remove %s: %v (is the app still running?)", dir, err)
	}
}
