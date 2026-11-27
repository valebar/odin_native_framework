#+build linux:android
#+private
package nv

// Android label backend: a TextView, 20sp bold as a heading, 16sp otherwise, changed by the style
// (android_style_text, theme_android.odin).

@(private)
_label_init :: proc(h: ^Label_Handle) {
	env := g_android.env

	tv := text_view_new(env, g_android.activity)
	text_view_set_text(env, tv, h.label.text)
	android_style_text(env, tv, h.label.style, h.label.heading ? 20 : 16, h.label.heading) // sp

	h.root = View(android_own_ref(env, tv))
	jni_delete_local_ref(env, tv)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	text_view_set_text(g_android.env, jobject(h.root), text)
}
