#+build linux:android
package nv

// Android label backend: a TextView, 20sp bold as a heading, 16sp otherwise, or in the given
// font and size.

@(private)
_label_init :: proc(h: ^Label_Handle) {
	env := g_android.env

	tv_cls := jni_find_class(env, "android/widget/TextView")
	tv := jni_new_object(env, tv_cls, "(Landroid/content/Context;)V", jv_obj(g_android.activity))
	set_char_sequence(env, tv, "setText", h.label.text)
	if h.label.bold && h.label.font == nil {
		jni_call_void(env, tv, "setTypeface", "(Landroid/graphics/Typeface;I)V", jv_obj(nil), jv_int(1)) // Typeface.BOLD
	}
	size := h.label.size != 0 ? h.label.size : (h.label.bold ? 20 : 16) // sp
	android_apply_font(env, tv, h.label.font, size)
	jni_delete_local_ref(env, tv_cls)

	h.root = View(jni_new_global_ref(env, tv))
	jni_delete_local_ref(env, tv)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	set_char_sequence(g_android.env, jobject(h.root), "setText", text)
}
