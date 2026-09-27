#+build linux:android
package nv

// Android container backend: an nv.NvContainerView (a FrameLayout with a settable natural size)
// that is the margin box. The parent LinearLayout replaces a child's LayoutParams (flex_android.odin),
// so the margin can't live there: the view's padding is margin + border + padding, and the
// background is the rounded, stroked GradientDrawable inside an InsetDrawable with the margin as
// insets. The child fills the padded area with MATCH_PARENT params.

@(private)
_container_init :: proc(h: ^Container_Handle) {
	env := g_android.env
	c := &h.container
	cls := jni_find_class(env, "nv/NvContainerView")
	view := jni_new_object(env, cls, "(Landroid/content/Context;)V", jv_obj(g_android.activity))

	gd_cls := jni_find_class(env, "android/graphics/drawable/GradientDrawable")
	bg := jni_new_object(env, gd_cls, "()V")
	jni_call_void(env, bg, "setColor", "(I)V", jv_argb(c.color))
	jni_call_void(env, bg, "setCornerRadius", "(F)V", jv_float(f32(android_dp(c.radius))))
	if c.border_width > 0 do jni_call_void(env, bg, "setStroke", "(II)V", jv_int(android_dp(c.border_width)), jv_argb(c.border_color))
	m := c.margin
	inset_cls := jni_find_class(env, "android/graphics/drawable/InsetDrawable")
	inset := jni_new_object(env, inset_cls, "(Landroid/graphics/drawable/Drawable;IIII)V", jv_obj(bg),
		jv_int(android_dp(m.left)), jv_int(android_dp(m.top)), jv_int(android_dp(m.right)), jv_int(android_dp(m.bottom)))
	jni_call_void(env, view, "setBackground", "(Landroid/graphics/drawable/Drawable;)V", jv_obj(inset))
	h.box = rawptr(jni_new_global_ref(env, bg))

	f := container_frame(h)
	jni_call_void(env, view, "setPadding", "(IIII)V", jv_int(android_dp(f.left)), jv_int(android_dp(f.top)), jv_int(android_dp(f.right)), jv_int(android_dp(f.bottom)))
	w := c.width > 0 ? android_dp(c.width) + android_dp(m.left) + android_dp(m.right) : 0
	hh := c.height > 0 ? android_dp(c.height) + android_dp(m.top) + android_dp(m.bottom) : 0
	jni_call_void(env, view, "setNaturalSize", "(II)V", jv_int(w), jv_int(hh))

	if c.child != nil {
		lp_cls := jni_find_class(env, "android/widget/FrameLayout$LayoutParams")
		lp := jni_new_object(env, lp_cls, "(II)V", jv_int(LAYOUT_MATCH_PARENT), jv_int(LAYOUT_MATCH_PARENT))
		jni_call_void(env, view, "addView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V", jv_obj(jobject(c.child)), jv_obj(lp))
		jni_delete_local_ref(env, lp)
		jni_delete_local_ref(env, lp_cls)
	}

	h.root = View(jni_new_global_ref(env, view))
	jni_delete_local_ref(env, inset)
	jni_delete_local_ref(env, inset_cls)
	jni_delete_local_ref(env, bg)
	jni_delete_local_ref(env, gd_cls)
	jni_delete_local_ref(env, view)
	jni_delete_local_ref(env, cls)
}

@(private)
_container_set_color :: proc(h: ^Container_Handle) {
	jni_call_void(g_android.env, jobject(h.box), "setColor", "(I)V", jv_argb(h.container.color)) // the drawable invalidates itself
}
