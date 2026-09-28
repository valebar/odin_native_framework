#+build linux:android
package nv

// Android button backend: an android.widget.Button. nv.NvClickListener (Java shim) forwards
// its OnClickListener callback.

@(private)
_button_init :: proc(h: ^Button_Handle) {
	env := g_android.env

	b := button_new(env, g_android.activity)
	text_view_set_text(env, b, h.button.title)
	android_apply_font(env, b, h.button.font, h.button.size)

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
