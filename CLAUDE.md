# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is
Experimental "native views" framework for Odin, targeting macOS, iOS and Android. It follows the Kotlin/Native approach: no codegen and no JS bridge. Odin code calls AppKit/UIKit directly through Objective-C interop, and Android views through JNI. So far it only has a vertically scrolling list (NSTableView / UITableView / ListView). The layout is Flutter-style: one shared app, framework backends per OS, and per-OS host folders that only handle packaging.

## Commands
- macOS: `macos/build.sh` (builds `build/macos/example` and runs it)
- iOS simulator: `ios/build.sh ["iPhone 17"]` (builds, bundles, ad-hoc signs, installs and launches with a console attached)
- Android: `android/build.sh [avd]` (default AVD `Pixel_10`; the `Pixel_8a` image is incomplete). It builds `libapp.so`, packages it without Gradle (javac → d8 → aapt2 → zipalign → apksigner), starts the emulator if needed, then installs and launches. App stdout goes to `adb logcat -s nv`. Screenshot with `adb exec-out screencap -p > build/android/shot.png`; `adb shell input tap/swipe` can drive the UI.
- Screenshot the simulator: `xcrun simctl io booted screenshot build/ios/shot.png`
- Type-check the framework:
  - macOS: `odin check nv -no-entry-point`
  - iOS: `odin check nv -no-entry-point -target:darwin_arm64 -subtarget:iphonesimulator`
  - Android: `odin check nv -no-entry-point -target:linux_arm64 -subtarget:android` (needs the `ODIN_ANDROID_*` env vars exported in `android/build.sh`)

## Layout
- `app/`: shared user app. It must stay free of platform code.
- `nv/nv.odin`: the shared public API (`run`, `list_create`, `list_view`, `list_reload`, `Row`, `List`, and `View`, an opaque NSView*/UIView*). It forwards to `_run`, `_list_init` and `_list_reload`, which each backend implements.
- `nv/*_macos.odin` / `appkit.odin` and `nv/*_ios.odin` / `uikit.odin`: the platform backends.
  - Each file body is wrapped in `when !IS_IOS { }` or `when IS_IOS { }`. Build tags cannot select the iOS subtarget (`darwin:iphone` parses but selects the wrong file).
  - `send` and `ns_string` in `appkit.odin` sit outside the `when` block and are shared by both backends.
- `nv/*_android.odin` / `jni.odin`: the Android backend (`#+build linux`). The Apple files carry `#+build darwin`.
- `nv/android/java/nv/`: the generic Java embedder. `NvActivity` loads `libapp.so`; `NvListAdapter` forwards `BaseAdapter` and click callbacks to exported `Java_nv_*` procs. Java is only used where Android requires a subclass.
- `macos/`, `ios/`, `android/`: host runners only (build scripts, `Info.plist`, `AndroidManifest.xml`).

## Backend patterns
- **Delegate classes:** ObjC classes are registered at runtime with `objc_allocateClassPair` and `class_addMethod`, using `proc "c"` IMPs and arm64 type encodings (for example `"q@:@"`).
  - The list data source stores a `^List_Handle` in its indexed ivars.
  - Each IMP restores `context = h.ctx` before calling Odin code.
- **App builder:** `run` takes a `build` proc because UIKit views can't exist before `UIApplicationMain`.
  - iOS uses the UIScene lifecycle. `NVSceneDelegate` is named in `ios/Info.plist`, and the names must match `app_ios.odin`.
  - Scene and app delegates are created by UIKit, so they use package globals (`g_app`) instead of ivars.
- **Row height:** on iOS rows are self-sizing and `row_height` is only an estimate. At a fixed 44pt, UIKit's subtitle configuration hides the secondary text.
- **Strings:** use `ns_string`, which copies and autoreleases. `initWithOdinString` does not copy.
- **`objc_send` arguments:** literals must be typed (`NS.BOOL(true)`, `NS.Integer(0)`), and nil object arguments are passed as `NS.id(nil)`.
- **Android startup:** Odin's `-build-mode:shared` never runs `_odin_entry_point` on the android subtarget. That entry point runs the `@init` procedures (without it `os.stdout` is nil and fmt prints nothing) and then the app's `main`. `jni_on_create` looks it up with `dlsym` and calls it; the `main` link name is reserved.
- **Android build quirks:**
  - `core:thread` needs `pthread_setcancelstate`, which Android's libc lacks, so use raw `posix.pthread_create`.
  - The script links an empty stub `libpthread.a`.
  - Odin wants a `darwin-aarch64` NDK toolchain, so `ODIN_ANDROID_NDK_TOOLCHAIN` points at `darwin-x86_64`.
  - A stub `android_main` satisfies `native_app_glue`, which Odin always links.
- **Android JNI:** method IDs are looked up on each call (simple, not fast). `g_android.env` is refreshed in every JNI callback. `targetSdk` is 34 to avoid forced edge-to-edge.
