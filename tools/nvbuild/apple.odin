package nvbuild

// macOS: a plain executable. iOS: an .app bundle (Info.plist and assets inside). Without --device
// it is a simulator bundle, signed ad hoc, installed on the `--sim` simulator (a name or a UDID,
// booted first) and launched with a console attached. With --device=<name|udid> it is built for a
// physical device, signed with a development certificate and the provisioning profile found for
// it (see ios_signing), installed and launched through devicectl.

import "core:crypto/hash"
import "core:encoding/base64"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

IOS_BUNDLE_ID :: "com.example.nativelist" // as in ios/Info.plist, with the executable name
IOS_MIN_OS    :: "-minimum-os-version:17.0"

build_macos :: proc(opt: Options) {
	OUT :: "build/macos"
	mkdir(OUT)
	odin_build(opt, OUT + "/example")
	copy_assets(OUT)
	if !opt.no_run do run(abs(OUT + "/example"))
}

build_ios :: proc(opt: Options) {
	if opt.device != "" {
		build_ios_device(opt)
		return
	}
	APP :: "build/ios/NativeList.app"
	mkdir(APP)
	odin_build(opt, APP + "/NativeList", "-target:darwin_arm64", "-subtarget:iphonesimulator", IOS_MIN_OS)
	if err := os.copy_file(APP + "/Info.plist", "ios/Info.plist"); err != nil do fail("cannot copy ios/Info.plist: %v", err)
	copy_assets(APP)
	run("codesign", "--force", "-s", "-", APP)
	if opt.no_run do return
	capture("xcrun", "simctl", "boot", opt.sim) // fails when already booted
	// The window is optional: Simulator.app up to Xcode 26, Device Hub from Xcode 27.
	if _, ok := capture("open", "-b", "com.apple.iphonesimulator"); !ok do capture("open", "-b", "com.apple.dt.Devices")
	run("xcrun", "simctl", "install", opt.sim, APP)
	run("xcrun", "simctl", "launch", "--console-pty", "--terminate-running-process", opt.sim, IOS_BUNDLE_ID)
}

// ---- iOS device ----

build_ios_device :: proc(opt: Options) {
	OUT :: "build/ios/device" // apart from the simulator bundle
	APP :: OUT + "/NativeList.app"
	mkdir(APP)
	udid := ios_device(opt.device, OUT + "/devices.json")
	sign := ios_signing(IOS_BUNDLE_ID, udid, opt.team)

	odin_build(opt, APP + "/NativeList", "-target:darwin_arm64", "-subtarget:iphone", IOS_MIN_OS)
	// The debug info stays on the Mac: in the bundle it would be signed and copied to the phone.
	if os.exists(APP + "/NativeList.dSYM") {
		os.remove_all(OUT + "/NativeList.dSYM")
		if err := os.rename(APP + "/NativeList.dSYM", OUT + "/NativeList.dSYM"); err != nil do fail("cannot move the dSYM: %v", err)
	}
	// ios/Info.plist is the simulator's; only the platform name differs.
	plist, rerr := os.read_entire_file("ios/Info.plist", context.allocator)
	if rerr != nil do fail("cannot read ios/Info.plist: %v", rerr)
	device_plist, _ := strings.replace_all(string(plist), "iPhoneSimulator", "iPhoneOS")
	if err := os.write_entire_file(APP + "/Info.plist", device_plist); err != nil do fail("cannot write %s/Info.plist: %v", APP, err)
	copy_assets(APP)

	if err := os.copy_file(APP + "/embedded.mobileprovision", sign.profile); err != nil do fail("cannot copy %s: %v", sign.profile, err)
	entitlements := fmt.aprintf(IOS_ENTITLEMENTS, sign.app_prefix, IOS_BUNDLE_ID, sign.team)
	if err := os.write_entire_file(OUT + "/entitlements.plist", entitlements); err != nil do fail("cannot write the entitlements: %v", err)
	run("codesign", "--force", "--timestamp=none", "-s", sign.identity, "--entitlements", OUT + "/entitlements.plist", APP)
	if opt.no_run do return

	// The device has to be unlocked, and on a cable or the same network.
	run("xcrun", "devicectl", "device", "install", "app", "--device", udid, APP)
	run("xcrun", "devicectl", "device", "process", "launch", "--console", "--terminate-existing", "--device", udid, IOS_BUNDLE_ID)
}

// What a development build may claim; get-task-allow lets a debugger attach.
IOS_ENTITLEMENTS :: `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key><string>%s.%s</string>
	<key>com.apple.developer.team-identifier</key><string>%s</string>
	<key>get-task-allow</key><true/>
</dict>
</plist>
`

// The hardware UDID (what a provisioning profile lists) of the paired physical device `want`:
// its name, UDID or CoreDevice identifier.
ios_device :: proc(want, json_path: string) -> string {
	if _, ok := capture("xcrun", "devicectl", "list", "devices", "--json-output", json_path); !ok do fail("xcrun devicectl failed: it needs Xcode 15 or later")
	data, err := os.read_entire_file(json_path, context.allocator)
	if err != nil do fail("cannot read %s: %v", json_path, err)
	root, jerr := json.parse(data)
	if jerr != nil do fail("cannot parse %s: %v", json_path, jerr)
	devices, _ := json_get(root, "result", "devices").(json.Array)
	paired := make([dynamic]string)
	for d in devices {
		if json_string(d, "hardwareProperties", "reality") != "physical" || json_string(d, "hardwareProperties", "platform") != "iOS" do continue
		name, udid := json_string(d, "deviceProperties", "name"), json_string(d, "hardwareProperties", "udid")
		for id in ([]string{name, udid, json_string(d, "identifier")}) do if strings.equal_fold(id, want) do return udid
		append(&paired, fmt.aprintf("%s (%s)", name, udid))
	}
	fail("no physical iOS device %q; paired: %s", want, len(paired) == 0 ? "none" : strings.join(paired[:], ", "))
}

json_get :: proc(v: json.Value, keys: ..string) -> json.Value {
	v := v
	for k in keys {
		o, ok := v.(json.Object)
		if !ok do return nil
		v = o[k]
	}
	return v
}

json_string :: proc(v: json.Value, keys: ..string) -> string {
	s, _ := json_get(v, ..keys).(json.String)
	return s
}

Ios_Signing :: struct {
	identity:   string, // the certificate's SHA-1: names can repeat in a keychain
	profile:    string, // the .mobileprovision
	team:       string,
	app_prefix: string, // of the application identifier, normally the team
}

// The signing identity and provisioning profile for a development build: a profile that is not
// expired, allows debugging, covers the bundle id (an exact app id wins over a wildcard) and the
// device, and lists a certificate whose key is in the keychain. `team` narrows it to one team.
// Xcode 16 and later keep their profiles in the first directory, older ones in the second.
ios_signing :: proc(bundle_id, udid, team: string) -> Ios_Signing {
	// `  1) <SHA-1> "Apple Development: Name (ID)"` per valid identity
	out, ok := capture("security", "find-identity", "-v", "-p", "codesigning")
	if !ok do fail("security find-identity failed")
	identities := make(map[string]string) // SHA-1 → name
	for line in strings.split_lines_iterator(&out) {
		f := strings.fields(line)
		q := strings.index_byte(line, '"')
		if len(f) < 3 || len(f[1]) != 40 || q < 0 do continue
		identities[f[1]] = strings.trim(line[q:], "\"")
	}

	home, err := os.user_home_dir(context.allocator)
	if err != nil do fail("no home directory: %v", err)
	best: Ios_Signing
	best_exact := false
	identity_name, profile_name: string
	for dir in ([]string{"Library/Developer/Xcode/UserData/Provisioning Profiles", "Library/MobileDevice/Provisioning Profiles"}) {
		entries, _ := os.read_all_directory_by_path(path(home, dir), context.allocator)
		for e in entries {
			if !strings.has_suffix(e.name, ".mobileprovision") do continue
			xml, decoded := capture_quiet("security", "cms", "-D", "-i", e.fullpath) // the signed plist inside
			if !decoded do continue
			if tag, _ := plist_value(xml, "get-task-allow"); tag != "true" do continue // a distribution profile
			_, date := plist_value(xml, "ExpirationDate")
			if expires, n := time.rfc3339_to_time_utc(date); n == 0 || time.diff(time.now(), expires) <= 0 do continue
			if _, devices := plist_value(xml, "ProvisionedDevices"); !strings.contains(devices, udid) do continue
			_, profile_team := plist_value(xml, "com.apple.developer.team-identifier")
			if team != "" && team != profile_team do continue
			_, app_id := plist_value(xml, "application-identifier") // <prefix>.<bundle id or pattern>
			dot := strings.index_byte(app_id, '.')
			if dot < 0 do continue
			pattern := app_id[dot + 1:]
			exact := pattern == bundle_id
			if !exact && !(strings.has_suffix(pattern, "*") && strings.has_prefix(bundle_id, pattern[:len(pattern) - 1])) do continue
			if best.profile != "" && (best_exact || !exact) do continue
			sha, name := ios_profile_identity(xml, identities)
			if sha == "" do continue
			best = {identity = sha, profile = e.fullpath, team = profile_team, app_prefix = app_id[:dot]}
			best_exact, identity_name = exact, name
			_, profile_name = plist_value(xml, "Name")
		}
	}
	if best.profile == "" {
		fail("no development provisioning profile%s covers %s on device %s with its certificate in the keychain: " +
			"let Xcode make one (a project with this bundle id and automatic signing, run once on the device)",
			team == "" ? "" : fmt.aprintf(" of team %s", team), bundle_id, udid)
	}
	fmt.printfln("nvbuild: signing as %q with profile %q (team %s)", identity_name, profile_name, best.team)
	return best
}

// The first certificate of the profile that is a keychain identity: its SHA-1 and name.
ios_profile_identity :: proc(xml: string, identities: map[string]string) -> (sha, name: string) {
	_, certs := plist_value(xml, "DeveloperCertificates")
	for cert in strings.split_iterator(&certs, "</data>") {
		start := strings.index(cert, "<data>")
		if start < 0 do break
		b64 := strings.join(strings.fields(cert[start + len("<data>"):]), "") // wrapped and indented
		der, err := base64.decode(b64)
		if err != nil do continue
		sha = strings.to_upper(string(hex.encode(hash.hash_bytes(.Insecure_SHA1, der))))
		if n, ok := identities[sha]; ok do return sha, n
	}
	return "", ""
}

// The element after <key>name</key> in an XML plist: its tag and its text ("" for <true/>). Enough
// for a profile, whose keys of interest are unique and hold no nested element of the same tag.
plist_value :: proc(xml, key: string) -> (tag, text: string) {
	k := strings.concatenate({"<key>", key, "</key>"})
	i := strings.index(xml, k)
	if i < 0 do return
	rest := strings.trim_left_space(xml[i + len(k):])
	end := strings.index_byte(rest, '>')
	if !strings.has_prefix(rest, "<") || end < 0 do return
	tag = rest[1:end]
	if strings.has_suffix(tag, "/") do return tag[:len(tag) - 1], ""
	stop := strings.index(rest, strings.concatenate({"</", tag, ">"}))
	if stop < 0 do return tag, ""
	return tag, rest[end + 1:stop]
}
