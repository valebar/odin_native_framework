#+build linux:android
package nv

// Android font backend. Typeface has no constructor from bytes below API 29's font builders, so
// the bytes go to a file in the app's cache directory that Typeface.createFromFile maps; the file
// is removed right after, since the mapping keeps it. The Typeface is a global ref in Font.native;
// TextView (labels, buttons, inputs) and Paint (the canvas) take it through android_style_typeface
// (theme_android.odin).

import "core:fmt"
import "core:os"

@(private) g_font_seq: int

@(private)
_font_load :: proc(f: ^Font, data: []u8) -> bool {
	env := g_android.env
	if g_android.cache_dir == "" {
		dir := context_get_cache_dir(env, g_android.activity)
		defer jni_delete_local_ref(env, dir)
		path := file_get_absolute_path(env, dir)
		defer jni_delete_local_ref(env, path)
		g_android.cache_dir = jni_string_clone(env, path)
	}
	g_font_seq += 1
	path := fmt.tprintf("%s/nv-font-%d.ttf", g_android.cache_dir, g_font_seq)
	if os.write_entire_file(path, data) != nil do return false
	defer os.remove(path)

	tf := typeface_create_from_file(env, path)
	if tf == nil do return false // not a font: the RuntimeException is logged and cleared by jni_check
	defer jni_delete_local_ref(env, tf)
	f.native = rawptr(jni_new_global_ref(env, tf))
	f.extra = new(Typeface_Cache) // the weights / slants derived from it (theme_android.odin)
	return true
}

@(private)
_font_free :: proc(f: ^Font) {
	env := g_android.env
	cache := (^Typeface_Cache)(f.extra)
	for slants in cache do for tf in slants do if tf != nil do jni_delete_global_ref(env, tf)
	free(cache)
	jni_delete_global_ref(env, jobject(f.native))
}
