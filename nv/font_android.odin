#+build linux:android
package nv

// Android font backend. Typeface has no constructor from bytes below API 29's font builders, so
// the bytes go to a file in the app's cache directory that Typeface.createFromFile maps; the file
// is removed right after, since the mapping keeps it. The Typeface is a global ref in Font.native;
// TextView (labels, buttons, inputs) and Paint (the canvas) take it as is.

import "core:fmt"
import "core:os"
import "core:strings"

@(private) g_font_seq: int

@(private)
_font_load :: proc(f: ^Font, data: []u8) -> bool {
	env := g_android.env
	if g_android.cache_dir == "" {
		dir := jni_call_object(env, g_android.activity, "getCacheDir", "()Ljava/io/File;")
		defer jni_delete_local_ref(env, dir)
		path := jni_call_object(env, dir, "getAbsolutePath", "()Ljava/lang/String;")
		defer jni_delete_local_ref(env, path)
		g_android.cache_dir = jni_string_clone(env, path)
	}
	g_font_seq += 1
	path := fmt.tprintf("%s/nv-font-%d.ttf", g_android.cache_dir, g_font_seq)
	if os.write_entire_file(path, data) != nil do return false
	defer os.remove(path)

	s := jni_string(env, strings.clone_to_cstring(path, context.temp_allocator))
	defer jni_delete_local_ref(env, s)
	tf := jni_call_static_object(env, "android/graphics/Typeface", "createFromFile", "(Ljava/lang/String;)Landroid/graphics/Typeface;", jv_obj(s))
	if tf == nil do return false // not a font: the RuntimeException is logged and cleared by jni_check
	defer jni_delete_local_ref(env, tf)
	f.native = rawptr(jni_new_global_ref(env, tf))
	return true
}

@(private)
_font_free :: proc(f: ^Font) {
	jni_delete_global_ref(g_android.env, jobject(f.native))
}

// Sets a TextView's typeface and text size (sp); either is left alone when not given.
@(private)
android_apply_font :: proc "contextless" (env: JNI_Env, view: jobject, font: ^Font, size: f64) {
	if font != nil do jni_call_void(env, view, "setTypeface", "(Landroid/graphics/Typeface;)V", jv_obj(jobject(font.native)))
	if size != 0 do jni_call_void(env, view, "setTextSize", "(F)V", jv_float(f32(size)))
}
