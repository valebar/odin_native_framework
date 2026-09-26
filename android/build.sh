#!/bin/sh
# Builds app/ as libapp.so, packages it with the nv Java embedder into an APK (no Gradle),
# installs and launches it. Starts the AVD if no device is connected.
# Usage: android/build.sh [avd name]   (default: Pixel_10)
set -e
cd "$(dirname "$0")/.."

AVD="${1:-Pixel_10}"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
NDK="${ODIN_ANDROID_NDK:-$(ls -d "$SDK"/ndk/* | sort -V | tail -1)}"
BT="$SDK/build-tools/$(ls "$SDK/build-tools" | sort -V | tail -1)"
PLATFORM_JAR="$SDK/platforms/android-36/android.jar"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}"
export PATH="$JAVA_HOME/bin:$PATH" # d8/apksigner need java on PATH
ADB="$SDK/platform-tools/adb"
OUT=build/android
PKG=com.example.nativelist

export ODIN_ANDROID_SDK="$SDK" ODIN_ANDROID_NDK="$NDK"
# Odin looks for darwin-aarch64; NDKs ship a universal darwin-x86_64 toolchain.
export ODIN_ANDROID_NDK_TOOLCHAIN="${ODIN_ANDROID_NDK_TOOLCHAIN:-$NDK/toolchains/llvm/prebuilt/darwin-x86_64}"

rm -rf "$OUT/stage" "$OUT/classes"
mkdir -p "$OUT/stage/lib/arm64-v8a" "$OUT/classes" "$OUT/stubs"

# Android has pthreads in libc, but core:thread links -lpthread: satisfy it with an empty archive.
[ -f "$OUT/stubs/libpthread.a" ] || "$ODIN_ANDROID_NDK_TOOLCHAIN/bin/llvm-ar" rc "$OUT/stubs/libpthread.a"

odin build app -target:linux_arm64 -subtarget:android -build-mode:shared -debug \
	-extra-linker-flags:"-L$PWD/$OUT/stubs -Wl,-z,max-page-size=16384" \
	-out:"$OUT/stage/lib/arm64-v8a/libapp.so"

"$JAVA_HOME/bin/javac" --release 11 -nowarn -cp "$PLATFORM_JAR" -d "$OUT/classes" nv/android/java/nv/*.java
"$BT/d8" --min-api 34 --lib "$PLATFORM_JAR" --output "$OUT/stage" $(find "$OUT/classes" -name '*.class')

"$BT/aapt2" link --debug-mode -I "$PLATFORM_JAR" --manifest android/AndroidManifest.xml -o "$OUT/unsigned.apk"
(cd "$OUT/stage" && zip -qr ../unsigned.apk classes.dex lib)
"$BT/zipalign" -f -p 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"
"$BT/apksigner" sign --ks "$HOME/.android/debug.keystore" --ks-pass pass:android --key-pass pass:android \
	--out "$OUT/NativeList.apk" "$OUT/aligned.apk"

if ! "$ADB" get-state >/dev/null 2>&1; then
	"$SDK/emulator/emulator" -avd "$AVD" >/dev/null 2>&1 &
	"$ADB" wait-for-device
	until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 1; done
fi

"$ADB" install -r "$OUT/NativeList.apk"
"$ADB" logcat -c
"$ADB" shell am start -n "$PKG/nv.NvActivity"
echo "logs: $ADB logcat -s nv AndroidRuntime"
