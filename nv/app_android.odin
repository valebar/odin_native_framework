#+build linux:android
package nv

// Android app backend. The Java embedder (nv/android/java/nv/NvActivity.java) loads
// libapp.so and calls nativeOnCreate on the UI thread. We then call the runtime's
// `_odin_entry_point` (runs @init procs, then the app's main), whose nv.run builds the
// root view and sets it as the Activity's content. Desktop Linux runs that entry at load
// via the linker; the android subtarget doesn't, hence the dlsym lookup.

import "base:runtime"
import "core:strings"
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
}

@(export, link_name="Java_nv_NvActivity_nativeOnCreate")
jni_on_create :: proc "c" (env: JNI_Env, _: jclass, activity: jobject) {
	g_android.env = env
	g_android.activity = jni_new_global_ref(env, activity)

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
_run :: proc(title: string, build: Build_Proc, user: rawptr) {
	g_android.ctx = context
	stdout_to_logcat()

	env := g_android.env
	root := build(user)
	jni_call_void(env, g_android.activity, "setTitle", "(Ljava/lang/CharSequence;)V",
		jv_obj(jni_string(env, strings.clone_to_cstring(title, context.temp_allocator))))
	jni_call_void(env, g_android.activity, "setContentView", "(Landroid/view/View;)V", jv_obj(jobject(root)))
}

// Converts density-independent pixels to device pixels, rounding to the nearest pixel.
android_dp :: proc "contextless" (dp: f64) -> int {
	if g_android.density == 0 {
		env := g_android.env
		res := jni_call_object(env, g_android.activity, "getResources", "()Landroid/content/res/Resources;")
		metrics := jni_call_object(env, res, "getDisplayMetrics", "()Landroid/util/DisplayMetrics;")
		g_android.density = jni_get_float_field(env, metrics, "density")
		jni_delete_local_ref(env, metrics)
		jni_delete_local_ref(env, res)
		if g_android.density == 0 do g_android.density = 1
	}
	return int(dp * f64(g_android.density) + 0.5)
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
