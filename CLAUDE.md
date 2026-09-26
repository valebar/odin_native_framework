# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is
Experimental "native views" framework for Odin, targeting macOS, iOS, Android and Linux. It follows the Kotlin/Native approach: no codegen and no JS bridge. Odin code calls AppKit/UIKit directly through Objective-C interop, Android views through JNI, and GTK4 through plain C bindings. Widgets so far: a vertically scrolling list (NSTableView / UITableView / ListView / GtkListView), a bold text label, and Flutter-style Row / Column stacks (NSStackView / UIStackView / LinearLayout / GtkBox). The layout is Flutter-style: one shared app, framework backends per OS, and per-OS host folders that only handle packaging.

## Commands
- macOS: `macos/build.sh` (builds `build/macos/example` and runs it)
- iOS simulator: `ios/build.sh ["iPhone 17"]` (builds, bundles, ad-hoc signs, installs and launches with a console attached)
- Android: `android/build.sh [avd]` (default AVD `Pixel_10`; the `Pixel_8a` image is incomplete). It builds `libapp.so`, packages it without Gradle (javac → d8 → aapt2 → zipalign → apksigner), starts the emulator if needed, then installs and launches. App stdout goes to `adb logcat -s nv`. Screenshot with `adb exec-out screencap -p > build/android/shot.png`; `adb shell input tap/swipe` can drive the UI.
- Linux: `linux/build.sh` (builds `build/linux/example` against GTK4 and runs it). Only the GTK4 runtime is required: without `libgtk-4-dev` the script symlinks `libgtk-4.so.1` into `build/linux/libs` for the linker. Under Hyprland, screenshot with `grim -g "$(hyprctl clients -j | jq -r '.[] | select(.title=="Native List") | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" build/linux/shot.png`.
- Screenshot the simulator: `xcrun simctl io booted screenshot build/ios/shot.png`
- Type-check the framework:
  - macOS: `odin check nv -no-entry-point`
  - iOS: `odin check nv -no-entry-point -target:darwin_arm64 -subtarget:iphonesimulator`
  - Android: `odin check nv -no-entry-point -target:linux_arm64 -subtarget:android` (needs the `ODIN_ANDROID_*` env vars exported in `android/build.sh`; for a check only, any placeholder paths work)
  - Linux: `odin check nv -no-entry-point` on a Linux host

## Layout
- `app/`: shared user app. It must stay free of platform code.
- `nv/nv.odin`: the shared public API (`run`, `list_create`, `list_view`, `list_reload`, `Item`, `List`, `row_create`, `column_create`, `flex_create`, `Flex`, `Flex_Child`, `Axis`, `label_create`, and `View`, an opaque NSView*/UIView*/jobject/GtkWidget*). It forwards to `_run`, `_list_init`, `_list_reload`, `_flex_create` and `_label_create`, which each backend implements. `Item` is the list-row data struct; `Row` is reserved for the layout vocabulary. Row/Column and labels return a plain `View` (no handle): children are fixed at creation, like Flutter.
- `nv/*_macos.odin` / `appkit.odin` and `nv/*_ios.odin` / `uikit.odin`: the platform backends (`list_*`, `flex_*` for Row/Column + label, `app_*`).
  - Each file body is wrapped in `when !IS_IOS { }` or `when IS_IOS { }`. Build tags cannot select the iOS subtarget (`darwin:iphone` parses but selects the wrong file).
  - `send`, `ns_string` and the Auto Layout helpers (`Layout_Constraint`, `flex_link_sizes`) in `appkit.odin` sit outside the `when` block and are shared by both backends.
- `nv/*_android.odin` / `jni.odin`: the Android backend (`#+build linux:android`). The Apple files carry `#+build darwin`.
- `nv/*_linux.odin` / `gtk.odin`: the Linux GTK4 backend (`#+build linux:default`). Unlike Darwin, the Linux subtarget build tags work, so no `when` split is needed.
- `nv/android/java/nv/`: the generic Java embedder. `NvActivity` loads `libapp.so`; `NvListAdapter` forwards `BaseAdapter` and click callbacks to exported `Java_nv_*` procs. Java is only used where Android requires a subclass.
- `macos/`, `ios/`, `android/`, `linux/`: host runners only (build scripts, `Info.plist`, `AndroidManifest.xml`).

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
- **Android JNI:** method IDs are looked up on each call (simple, not fast). `g_android.env` is refreshed in every JNI callback. `targetSdk` is 34 to avoid forced edge-to-edge. `android_dp` converts dp to px from `DisplayMetrics.density` (read once through `jni_get_float_field`). The JNI table indices in `jni.odin` follow `struct JNINativeInterface` in the NDK's `jni.h`; check any new one there.
- **Row / Column (`flex_*.odin`):** `Axis` values equal the native orientation enums on every platform, so backends cast them directly. The cross axis always stretches; `flex` 0 hugs, `flex` > 0 shares the spare main-axis space.
  - macOS/iOS: stack view with Fill distribution (`NSStackViewDistributionFill` is 0, GravityAreas is -1; UIKit's Fill is also 0). Cross-axis stretch is alignment `Width` (7) for a vertical stack / `Height` (8) for a horizontal one; UIKit's default alignment is already Fill. Flex children get hugging priority 1, others 1000, and `flex_link_sizes` adds `NSLayoutConstraint` multipliers between the flex children so weights are exact. NSStackView children need `translatesAutoresizingMaskIntoConstraints = NO` set explicitly; UIStackView does it itself. `text_field_label` is autoreleased, so `_label_create` retains it: every `*_create` returns an owned view.
  - Android: `LinearLayout` with `LinearLayout.LayoutParams(w, h, weight)`; a flex child has main-axis size 0 and `weight = flex`, a flex-0 child is `WRAP_CONTENT`, the cross axis is `MATCH_PARENT`. Spacing is a top/left margin (`setMargins`) in px on every child after the first. `setTypeface(null, BOLD)` is how the label goes bold without looking up `Typeface.DEFAULT_BOLD`.
  - Linux: `GtkBox`. GTK has no weights, so every flex > 0 child gets an equal share. The main-axis expand flag is set explicitly on every child: the list turns both flags on in `_list_init`, so a flex-0 list has to be turned off again, and an explicit value also stops the flag propagating up through the box.
- **Linux GTK4:** `run` uses `GtkApplication` (no app id) and builds the root view in `activate`. The list is a `GtkListView` over a `GListModel` type registered at runtime with `g_type_register_static_simple`; the instance size comes from `g_type_query` and the `^List_Handle` sits right after the GObject fields. Model items are throwaway `GObject`s, because GTK only rebinds a row when its item object changes. Rows are recycled by the `GtkSignalListItemFactory` `setup`/`bind` signals. `GtkSingleSelection` autoselects row 0 at construction, so `_list_init` turns off `autoselect`, turns on `can-unselect` (without it the unselect is silently ignored) and unselects. `list_reload` emits `items-changed` with the previously reported count. `cells_created` starts around 200 because GtkListView pre-creates up to 200 row widgets for measuring, then recycles them. Under Hyprland, keys can be sent for testing with `hyprctl dispatch "hl.dsp.send_shortcut({mods='', key='Down', window='address:<addr>'})"`.
