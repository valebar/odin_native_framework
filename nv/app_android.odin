#+build linux:android
package nv

// Android app backend. The Java embedder (nv/android/java/nv/NvActivity.java) loads
// libapp.so and calls nativeOnCreate on the UI thread. We then call the runtime's
// `_odin_entry_point` (runs @init procs, then the app's main), whose nv.run builds the
// root view and sets it as the Activity's content. Desktop Linux runs that entry at load
// via the linker; the android subtarget doesn't, hence the dlsym lookup.
//
// The entry point runs once per process. A later Activity in the same process (the user backed
// out and relaunched, so onCreate ran again but loadLibrary didn't) gets a fresh view tree from
// the same `build`, since views belong to the Activity that created them: the page stack is
// reset to the root first. Configuration changes such as rotation don't recreate the Activity
// (android:configChanges in the manifest).

import "base:runtime"
import "core:sys/posix"

foreign import liblog "system:log"

foreign liblog {
	__android_log_write :: proc "c" (prio: i32, tag: cstring, text: cstring) -> i32 ---
}

@(private) ANDROID_LOG_INFO  :: 4
@(private) ANDROID_LOG_ERROR :: 6

@(private) g_android: struct {
	env:      JNI_Env,  // UI-thread env, refreshed on every JNI callback
	activity: jobject,  // global ref
	ctx:      runtime.Context,
	density:  f32,      // DisplayMetrics.density, read lazily by android_dp
	cache_dir: string,  // Context.getCacheDir(), read lazily by _font_load
}

@(export, link_name="Java_nv_NvActivity_nativeOnCreate")
jni_on_create :: proc "c" (env: JNI_Env, _: jclass, activity: jobject) {
	g_android.env = env
	if g_android.activity != nil do jni_delete_global_ref(env, g_android.activity)
	g_android.activity = jni_new_global_ref(env, activity)

	if len(g_nav) > 0 {
		context = g_android.ctx
		callback_enter()
		defer callback_exit()
		for len(g_nav) > 1 do nav_system_pop() // pushed pages are gone with the old Activity
		dialog_close_page(g_nav[0]) // and so are the root's dialogs
		scope_retire(g_nav[0].scope) // the old root's widgets, once this callback returns
		g_nav[0].scope = scope_new()
		g_nav[0].root = nil // rebuilt by set_content; nil means "building" to page_set_*
		set_content()
		return
	}

	self := posix.dlopen("libapp.so", {.NOW})
	entry := cast(proc "c" ())posix.dlsym(self, "_odin_entry_point")
	if entry == nil {
		__android_log_write(ANDROID_LOG_ERROR, "nv", "_odin_entry_point not found")
		return
	}
	entry()
}

// Unused: native_app_glue is linked for the android subtarget and references it.
@(export)
android_main :: proc "c" (app: rawptr) {}

@(private)
_run :: proc() {
	g_android.ctx = context
	stdout_to_logcat()
	callback_enter()
	set_content()
	callback_exit()
}

// Builds the root page's view tree and shows it in the current Activity.
@(private)
set_content :: proc() {
	nav_show_root()
}

// Converts density-independent pixels to device pixels, rounding to the nearest pixel.
android_dp :: proc "contextless" (dp: f64) -> int {
	if g_android.density == 0 {
		env := g_android.env
		res := context_get_resources(env, g_android.activity)
		metrics := resources_get_display_metrics(env, res)
		g_android.density = display_metrics_density(env, metrics)
		jni_delete_local_ref(env, metrics)
		jni_delete_local_ref(env, res)
		if g_android.density == 0 do g_android.density = 1
	}
	return int(dp * f64(g_android.density) + 0.5)
}

// A Color as the int android.graphics.Color / GradientDrawable / Paint take.
android_argb :: proc "contextless" (c: Color) -> int {
	return int(i32(color_argb(c)))
}

// stdout/stderr go nowhere on Android; pipe them into logcat (tag "nv").
@(private)
stdout_to_logcat :: proc() {
	fds: [2]posix.FD
	if posix.pipe(&fds) != .OK do return
	posix.dup2(fds[1], 1)
	posix.dup2(fds[1], 2)
	// Raw pthread: core:thread needs pthread_setcancelstate, which bionic lacks.
	tid: posix.pthread_t
	posix.pthread_create(&tid, nil, logcat_pump, rawptr(uintptr(fds[0])))
	posix.pthread_detach(tid)
}

@(private)
logcat_pump :: proc "c" (arg: rawptr) -> rawptr {
	fd := posix.FD(uintptr(arg))
	buf: [1024]byte
	for {
		n := posix.read(fd, &buf[0], len(buf) - 1)
		if n <= 0 do return nil
		if buf[n - 1] == '\n' do n -= 1
		buf[n] = 0
		__android_log_write(ANDROID_LOG_INFO, "nv", cstring(&buf[0]))
	}
}

// A global ref to `obj` that the current scope deletes when it dies: every widget's views,
// listeners and Paints, so a popped page's Java objects become collectable.
@(private)
android_own_ref :: proc(env: JNI_Env, obj: jobject) -> jobject {
	ref := jni_new_global_ref(env, obj)
	scope_on_dispose(android_release_ref, rawptr(ref))
	return ref
}

@(private)
android_release_ref :: proc(data: rawptr) {
	jni_delete_global_ref(g_android.env, jobject(data))
}
