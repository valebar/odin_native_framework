#+build linux:android
#+private
package nv

// Android Layout backend: an nv.NvLayoutView (a FrameLayout) the child fills, which reports its
// size from a pre-draw listener and skips the frame that would show the old answer.

@(private)
_layout_init :: proc(h: ^Layout_Handle) {
	env := g_android.env
	view := nv_layout_view_new(env, g_android.activity, i64(uintptr(h)))
	lp := frame_lp_new(env, LAYOUT_MATCH_PARENT, LAYOUT_MATCH_PARENT)
	view_group_add_view(env, view, jobject(h.layout.child), lp)
	jni_delete_local_ref(env, lp)
	h.root = View(android_own_ref(env, view))
	jni_delete_local_ref(env, view)
}

@(export, link_name="Java_nv_NvLayoutView_nativeOnLayout")
jni_layout_on_layout :: proc "c" (env: JNI_Env, _: jclass, handle: jlong, width, height: jint) {
	h := (^Layout_Handle)(uintptr(handle))
	context = h.ctx
	g_android.env = env
	d := android_density()
	layout_notify(h, f64(width) / d, f64(height) / d)
}
