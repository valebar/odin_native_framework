#+build linux:android
#+private
package nv

// Android dialog backend: the card is a FrameLayout with a rounded GradientDrawable background
// in the theme's colorBackground, some elevation and padding, added to the window's decor view
// (a FrameLayout covering the ActionBar and the content) with CENTER gravity; a modal dialog first
// adds a full-size translucent black View, whose nv.NvTapListener reports a tap for a
// dismissible dialog. Both are clickable, so a touch on them stops there instead of falling
// through to the page (a ViewGroup offers a touch to lower siblings when the top child doesn't
// take it), and a tap on the card never reaches the scrim. The Back key closes a modal dialog
// (nav_android.odin). A light dialog's card is white and nv.NvDialog.lighten darkens the
// theme-coloured text in its body, which was made with the Activity's theme.

@(private) ANDROID_VIEW_VISIBLE :: 0
@(private) ANDROID_VIEW_GONE    :: 8
@(private) ANDROID_GRAVITY_CENTER :: 17
@(private) ANDROID_SCRIM_ARGB :: 0x66000000

@(private)
_dialog_show :: proc(h: ^Dialog_Handle) {
	env := g_android.env
	activity := g_android.activity
	window := activity_get_window(env, activity)
	decor := window_get_decor_view(env, window)
	jni_delete_local_ref(env, window)

	if h.dialog.modal {
		scrim := view_new(env, activity)
		view_set_background_color(env, scrim, android_argb(dialog_scrim(h)))
		h.scrim = rawptr(jni_new_global_ref(env, scrim))
		android_on_tap(env, scrim, h.scrim, TAP_DIALOG) // clickable; the listener is the dialog scope's
		lp := frame_lp_new(env, LAYOUT_MATCH_PARENT, LAYOUT_MATCH_PARENT)
		view_group_add_view(env, decor, scrim, lp)
		jni_delete_local_ref(env, lp)
		jni_delete_local_ref(env, scrim)
	}

	card := frame_layout_new(env, activity)
	bg := gradient_drawable_new(env)
	gradient_drawable_set_color(env, bg, h.dialog.light ? android_argb(DIALOG_LIGHT) : int(android_theme_color("colorBackground", -1)))
	gradient_drawable_set_corner_radius(env, bg, f32(android_dp(dialog_radius(h, 12))))
	view_set_background(env, card, bg)
	view_set_elevation(env, card, f32(android_dp(8)))
	pad := android_dp(16)
	view_set_padding(env, card, pad, pad, pad, pad)
	view_set_clickable(env, card, true)
	body_lp := frame_lp_new(env, LAYOUT_MATCH_PARENT, LAYOUT_WRAP_CONTENT)
	view_group_add_view(env, card, jobject(h.body), body_lp)
	jni_delete_local_ref(env, body_lp)
	if h.dialog.light do nv_dialog_lighten(env, jobject(h.body))

	// The dialog's width (320dp), or the screen width less the margins on a narrow screen. The
	// decor view may not be laid out yet, so the width comes from the display metrics.
	res := context_get_resources(env, activity)
	metrics := resources_get_display_metrics(env, res)
	screen_w := int(display_metrics_width_pixels(env, metrics))
	jni_delete_local_ref(env, metrics)
	jni_delete_local_ref(env, res)
	width := min(android_dp(dialog_width(h)), screen_w - android_dp(32))
	lp := frame_lp_new_gravity(env, width, LAYOUT_WRAP_CONTENT, ANDROID_GRAVITY_CENTER)
	view_group_add_view(env, decor, card, lp) // after the scrim: above it
	jni_delete_local_ref(env, lp)
	h.card = rawptr(jni_new_global_ref(env, card))

	jni_delete_local_ref(env, bg)
	jni_delete_local_ref(env, card)
	jni_delete_local_ref(env, decor)
}

@(private)
_dialog_close :: proc(h: ^Dialog_Handle) {
	env := g_android.env
	if h.card != nil do nv_input_listener_blur(env, jobject(h.card)) // a field's keyboard goes with it
	for v in ([]rawptr{h.card, h.scrim}) {
		if v == nil do continue
		parent := view_get_parent(env, jobject(v)) // the decor view, a ViewGroup
		if parent != nil {
			view_group_remove_view(env, parent, jobject(v))
			jni_delete_local_ref(env, parent)
		}
		jni_delete_global_ref(env, jobject(v))
	}
	scope_retire(h.scope) // the body's global refs
}

@(private)
_dialog_set_hidden :: proc(h: ^Dialog_Handle, hidden: bool) {
	env := g_android.env
	for v in ([]rawptr{h.card, h.scrim}) {
		if v == nil do continue
		view_set_visibility(env, jobject(v), hidden ? ANDROID_VIEW_GONE : ANDROID_VIEW_VISIBLE)
	}
}

// Resolves an android.R.attr color of the Activity's theme (ARGB); `fallback` when it has none.
@(private)
android_theme_color :: proc(attr: cstring, fallback: jint) -> jint {
	env := g_android.env
	id := jni_get_static_int_field(env, "android/R$attr", attr)
	if id == 0 do return fallback
	theme := context_get_theme(env, g_android.activity)
	tv := typed_value_new(env)
	found := resources_theme_resolve_attribute(env, theme, int(id), tv, true)
	color := found ? typed_value_data(env, tv) : fallback
	jni_delete_local_ref(env, tv)
	jni_delete_local_ref(env, theme)
	return color
}
