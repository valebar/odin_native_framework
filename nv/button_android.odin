#+build linux:android
#+private
package nv

// Android button backend: an android.widget.Button. nv.NvClickListener (Java shim) forwards
// its OnClickListener callback.

@(private)
_button_init :: proc(h: ^Button_Handle) {
	env := g_android.env

	b := button_new(env, g_android.activity)
	text_view_set_text(env, b, h.button.title)
	android_tint_accent(env, b)
	s := h.button.style
	if g_theme.accent.a > 0 && s.color.a == 0 do s.color = {1, 1, 1, 1} // on the accent
	android_style_text(env, b, s)

	listener := nv_click_listener_new(env, i64(uintptr(h)))
	view_set_on_click_listener(env, b, listener)

	h.root = View(android_own_ref(env, b))
	h.control = rawptr(h.root)
	h.target = rawptr(android_own_ref(env, listener))
	jni_delete_local_ref(env, listener)
	jni_delete_local_ref(env, b)
}

@(private)
_button_set_title :: proc(h: ^Button_Handle, title: string) {
	text_view_set_text(g_android.env, jobject(h.control), title)
}

@(export, link_name="Java_nv_NvClickListener_nativeOnClick")
jni_button_on_click :: proc "c" (env: JNI_Env, _: jclass, handle: jlong) {
	h := (^Button_Handle)(uintptr(handle))
	context = h.ctx
	g_android.env = env
	button_notify(h)
}
