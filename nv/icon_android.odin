#+build linux:android
#+private
package nv

// Icons drawn from Material's 24-unit SVG paths (svg_path.odin, nv.js has the same) into a
// ShapeDrawable, where android.R.drawable has none or only Holo's: the hamburger (the closest
// drawable is a sort icon), the hub and the search magnifier.

@(private) android_icon_paths := #partial [Icon]string{
	.Search = MATERIAL_SEARCH_PATH,
	.Menu   = MATERIAL_MENU_PATH,
	.Hub    = MATERIAL_HUB_PATH,
}

// `icon` at 24 dp in `color`, a local ref; nil when it has no path (android_icon_res has the rest).
@(private)
android_icon_drawable :: proc(env: JNI_Env, icon: Icon, color: Color) -> jobject {
	d := android_icon_paths[icon]
	if d == "" do return nil
	path := path_new(env)
	defer jni_delete_local_ref(env, path)
	target := Android_Svg{env, path}
	svg_path_replay(d, {
		user     = &target,
		move_to  = proc(u: rawptr, x, y: f32) { t := (^Android_Svg)(u); path_move_to(t.env, t.path, x, y) },
		line_to  = proc(u: rawptr, x, y: f32) { t := (^Android_Svg)(u); path_line_to(t.env, t.path, x, y) },
		cubic_to = proc(u: rawptr, c1x, c1y, c2x, c2y, x, y: f32) { t := (^Android_Svg)(u); path_cubic_to(t.env, t.path, c1x, c1y, c2x, c2y, x, y) },
		close    = proc(u: rawptr) { t := (^Android_Svg)(u); path_close(t.env, t.path) },
	})
	shape := path_shape_new(env, path, 24, 24)
	defer jni_delete_local_ref(env, shape)
	drawable := shape_drawable_new(env, shape)
	paint := shape_drawable_get_paint(env, drawable)
	paint_set_color(env, paint, android_argb(color))
	jni_delete_local_ref(env, paint)
	size := android_dp(24)
	shape_drawable_set_intrinsic_width(env, drawable, size)
	shape_drawable_set_intrinsic_height(env, drawable, size)
	return drawable
}

// svg_path_replay's target: an android.graphics.Path.
@(private = "file")
Android_Svg :: struct {
	env:  JNI_Env,
	path: jobject,
}
