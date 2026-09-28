#+build linux:android
package nv

// Android label backend: a TextView, 20sp bold as a heading, 16sp otherwise, or in the given
// font and size.

@(private) ANDROID_TYPEFACE_BOLD :: 1 // Typeface.BOLD

@(private)
_label_init :: proc(h: ^Label_Handle) {
	env := g_android.env

	tv := text_view_new(env, g_android.activity)
	text_view_set_text(env, tv, h.label.text)
	if h.label.bold && h.label.font == nil {
		text_view_set_typeface_style(env, tv, nil, ANDROID_TYPEFACE_BOLD) // the default face, bold
	}
	size := h.label.size != 0 ? h.label.size : (h.label.bold ? 20 : 16) // sp
	android_apply_font(env, tv, h.label.font, size)

	h.root = View(android_own_ref(env, tv))
	jni_delete_local_ref(env, tv)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	text_view_set_text(g_android.env, jobject(h.root), text)
}
