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
	view := nv_container_view_new(env, g_android.activity)

	bg := gradient_drawable_new(env)
	gradient_drawable_set_color(env, bg, android_argb(c.color))
	gradient_drawable_set_corner_radius(env, bg, f32(android_dp(c.radius)))
	if c.border_width > 0 do gradient_drawable_set_stroke(env, bg, android_dp(c.border_width), android_argb(c.border_color))
	m := c.margin
	inset := inset_drawable_new(env, bg, android_dp(m.left), android_dp(m.top), android_dp(m.right), android_dp(m.bottom))
	view_set_background(env, view, inset)
	h.box = rawptr(jni_new_global_ref(env, bg))

	f := container_frame(h)
	view_set_padding(env, view, android_dp(f.left), android_dp(f.top), android_dp(f.right), android_dp(f.bottom))
	w := c.width > 0 ? android_dp(c.width) + android_dp(m.left) + android_dp(m.right) : 0
	hh := c.height > 0 ? android_dp(c.height) + android_dp(m.top) + android_dp(m.bottom) : 0
	nv_container_view_set_natural_size(env, view, w, hh)

	if c.child != nil {
		lp := frame_lp_new(env, LAYOUT_MATCH_PARENT, LAYOUT_MATCH_PARENT)
		view_group_add_view(env, view, jobject(c.child), lp)
		jni_delete_local_ref(env, lp)
	}

	h.root = View(jni_new_global_ref(env, view))
	jni_delete_local_ref(env, inset)
	jni_delete_local_ref(env, bg)
	jni_delete_local_ref(env, view)
}

@(private)
_container_set_color :: proc(h: ^Container_Handle) {
	gradient_drawable_set_color(g_android.env, jobject(h.box), android_argb(h.container.color)) // the drawable invalidates itself
}
