#+build linux:android
#+private
package nv

// Android Row / Column backend: LinearLayout. A flex child gets main-axis size 0 plus
// layout_weight = flex, which is exactly Flutter's Expanded; the cross axis is MATCH_PARENT.
// Spacing becomes a leading margin (top or left) on every child after the first.

@(private) LAYOUT_MATCH_PARENT :: -1
@(private) LAYOUT_WRAP_CONTENT :: -2

@(private)
_flex_create :: proc(f: Flex) -> View {
	env := g_android.env

	ll := linear_layout_new(env, g_android.activity)
	linear_layout_set_orientation(env, ll, int(f.axis))

	gap := android_dp(f.spacing)
	for c, i in f.children {
		main := c.flex > 0 ? 0 : LAYOUT_WRAP_CONTENT
		weight := c.flex > 0 ? f32(c.flex) : 0
		w, h := main, LAYOUT_MATCH_PARENT
		left, top := 0, 0
		if f.axis == .Vertical {
			w, h = LAYOUT_MATCH_PARENT, main
			if i > 0 do top = gap
		} else if i > 0 {
			left = gap
		}
		lp := linear_lp_new(env, w, h, weight)
		view_group_margin_layout_params_set_margins(env, lp, left, top, 0, 0)
		view_group_add_view(env, ll, jobject(c.view), lp)
		jni_delete_local_ref(env, lp)
	}

	root := android_own_ref(env, ll)
	jni_delete_local_ref(env, ll)
	return View(root)
}
