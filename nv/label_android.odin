#+build linux:android
package nv

// Android label backend: a bold 20sp TextView.

@(private)
_label_init :: proc(h: ^Label_Handle) {
	env := g_android.env

	tv_cls := jni_find_class(env, "android/widget/TextView")
	tv := jni_new_object(env, tv_cls, "(Landroid/content/Context;)V", jv_obj(g_android.activity))
	set_char_sequence(env, tv, "setText", h.label.text)
	jni_call_void(env, tv, "setTextSize", "(F)V", jv_float(20)) // sp
	jni_call_void(env, tv, "setTypeface", "(Landroid/graphics/Typeface;I)V", jv_obj(nil), jv_int(1)) // Typeface.BOLD
	jni_delete_local_ref(env, tv_cls)

	h.root = View(jni_new_global_ref(env, tv))
	jni_delete_local_ref(env, tv)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	set_char_sequence(g_android.env, jobject(h.root), "setText", text)
}
