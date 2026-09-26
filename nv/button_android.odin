#+build linux:android
package nv

// Android button backend: an android.widget.Button. nv.NvClickListener (Java shim) forwards
// its OnClickListener callback.

@(private)
_button_init :: proc(h: ^Button_Handle) {
	env := g_android.env

	b_cls := jni_find_class(env, "android/widget/Button")
	b := jni_new_object(env, b_cls, "(Landroid/content/Context;)V", jv_obj(g_android.activity))
	set_char_sequence(env, b, "setText", h.button.title)

	l_cls := jni_find_class(env, "nv/NvClickListener")
	listener := jni_new_object(env, l_cls, "(J)V", jv_long(i64(uintptr(h))))
	jni_call_void(env, b, "setOnClickListener", "(Landroid/view/View$OnClickListener;)V", jv_obj(listener))

	h.root = View(jni_new_global_ref(env, b))
	h.control = rawptr(h.root)
	h.target = rawptr(jni_new_global_ref(env, listener))
	jni_delete_local_ref(env, listener)
	jni_delete_local_ref(env, l_cls)
	jni_delete_local_ref(env, b)
	jni_delete_local_ref(env, b_cls)
}

@(private)
_button_set_title :: proc(h: ^Button_Handle, title: string) {
	set_char_sequence(g_android.env, jobject(h.control), "setText", title)
}

@(export, link_name="Java_nv_NvClickListener_nativeOnClick")
jni_button_on_click :: proc "c" (env: JNI_Env, _: jclass, handle: jlong) {
	h := (^Button_Handle)(uintptr(handle))
	context = h.ctx
	g_android.env = env
	button_notify(h)
}
