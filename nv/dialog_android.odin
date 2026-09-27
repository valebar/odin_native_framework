#+build linux:android
package nv

// Android dialog backend: the card is a FrameLayout with a rounded GradientDrawable background
// in the theme's colorBackground, some elevation and padding, added to the window's decor view
// (a FrameLayout covering the ActionBar and the content) with CENTER gravity; a modal dialog first
// adds a full-size translucent black View. Both are clickable, so a touch on them stops there
// instead of falling through to the page (a ViewGroup offers a touch to lower siblings when the
// top child doesn't take it). The Back key closes a modal dialog (nav_android.odin).

@(private) ANDROID_VIEW_VISIBLE :: 0
@(private) ANDROID_VIEW_GONE    :: 8
@(private) ANDROID_GRAVITY_CENTER :: 17

@(private)
_dialog_show :: proc(h: ^Dialog_Handle) {
	env := g_android.env
	activity := g_android.activity
	window := jni_call_object(env, activity, "getWindow", "()Landroid/view/Window;")
	decor := jni_call_object(env, window, "getDecorView", "()Landroid/view/View;")
	jni_delete_local_ref(env, window)
	lp_cls := jni_find_class(env, "android/widget/FrameLayout$LayoutParams")

	if h.dialog.modal {
		view_cls := jni_find_class(env, "android/view/View")
		scrim := jni_new_object(env, view_cls, "(Landroid/content/Context;)V", jv_obj(activity))
		jni_call_void(env, scrim, "setBackgroundColor", "(I)V", jvalue{i = 0x66000000})
		jni_call_void(env, scrim, "setClickable", "(Z)V", jv_bool(true))
		lp := jni_new_object(env, lp_cls, "(II)V", jv_int(LAYOUT_MATCH_PARENT), jv_int(LAYOUT_MATCH_PARENT))
		jni_call_void(env, decor, "addView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V", jv_obj(scrim), jv_obj(lp))
		jni_delete_local_ref(env, lp)
		h.scrim = rawptr(jni_new_global_ref(env, scrim))
		jni_delete_local_ref(env, scrim)
		jni_delete_local_ref(env, view_cls)
	}

	fl_cls := jni_find_class(env, "android/widget/FrameLayout")
	card := jni_new_object(env, fl_cls, "(Landroid/content/Context;)V", jv_obj(activity))
	gd_cls := jni_find_class(env, "android/graphics/drawable/GradientDrawable")
	bg := jni_new_object(env, gd_cls, "()V")
	jni_call_void(env, bg, "setColor", "(I)V", jvalue{i = android_theme_color("colorBackground", -1)})
	jni_call_void(env, bg, "setCornerRadius", "(F)V", jv_float(f32(android_dp(12))))
	jni_call_void(env, card, "setBackground", "(Landroid/graphics/drawable/Drawable;)V", jv_obj(bg))
	jni_call_void(env, card, "setElevation", "(F)V", jv_float(f32(android_dp(8))))
	pad := android_dp(16)
	jni_call_void(env, card, "setPadding", "(IIII)V", jv_int(pad), jv_int(pad), jv_int(pad), jv_int(pad))
	jni_call_void(env, card, "setClickable", "(Z)V", jv_bool(true))
	body_lp := jni_new_object(env, lp_cls, "(II)V", jv_int(LAYOUT_MATCH_PARENT), jv_int(LAYOUT_WRAP_CONTENT))
	jni_call_void(env, card, "addView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V", jv_obj(jobject(h.body)), jv_obj(body_lp))
	jni_delete_local_ref(env, body_lp)

	// 320dp, or the screen width less the margins on a narrow screen. The decor view may not be
	// laid out yet, so the width comes from the display metrics.
	res := jni_call_object(env, activity, "getResources", "()Landroid/content/res/Resources;")
	metrics := jni_call_object(env, res, "getDisplayMetrics", "()Landroid/util/DisplayMetrics;")
	screen_w := int(jni_get_int_field(env, metrics, "widthPixels"))
	jni_delete_local_ref(env, metrics)
	jni_delete_local_ref(env, res)
	width := min(android_dp(320), screen_w - android_dp(32))
	lp := jni_new_object(env, lp_cls, "(III)V", jv_int(width), jv_int(LAYOUT_WRAP_CONTENT), jv_int(ANDROID_GRAVITY_CENTER))
	jni_call_void(env, decor, "addView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V", jv_obj(card), jv_obj(lp)) // after the scrim: above it
	jni_delete_local_ref(env, lp)
	h.card = rawptr(jni_new_global_ref(env, card))

	jni_delete_local_ref(env, bg)
	jni_delete_local_ref(env, gd_cls)
	jni_delete_local_ref(env, card)
	jni_delete_local_ref(env, fl_cls)
	jni_delete_local_ref(env, lp_cls)
	jni_delete_local_ref(env, decor)
}

@(private)
_dialog_close :: proc(h: ^Dialog_Handle) {
	env := g_android.env
	for v in ([]rawptr{h.card, h.scrim}) {
		if v == nil do continue
		parent := jni_call_object(env, jobject(v), "getParent", "()Landroid/view/ViewParent;")
		if parent != nil {
			jni_call_void(env, parent, "removeView", "(Landroid/view/View;)V", jv_obj(jobject(v)))
			jni_delete_local_ref(env, parent)
		}
		jni_delete_global_ref(env, jobject(v))
	}
	jni_delete_global_ref(env, jobject(h.body)) // the card held the only other reference
}

@(private)
_dialog_set_hidden :: proc(h: ^Dialog_Handle, hidden: bool) {
	env := g_android.env
	for v in ([]rawptr{h.card, h.scrim}) {
		if v == nil do continue
		jni_call_void(env, jobject(v), "setVisibility", "(I)V", jv_int(hidden ? ANDROID_VIEW_GONE : ANDROID_VIEW_VISIBLE))
	}
}

// Resolves an android.R.attr color of the Activity's theme (ARGB); `fallback` when it has none.
@(private)
android_theme_color :: proc(attr: cstring, fallback: jint) -> jint {
	env := g_android.env
	id := jni_get_static_int_field(env, "android/R$attr", attr)
	if id == 0 do return fallback
	theme := jni_call_object(env, g_android.activity, "getTheme", "()Landroid/content/res/Resources$Theme;")
	tv_cls := jni_find_class(env, "android/util/TypedValue")
	tv := jni_new_object(env, tv_cls, "()V")
	found := jni_call_bool(env, theme, "resolveAttribute", "(ILandroid/util/TypedValue;Z)Z", jv_int(int(id)), jv_obj(tv), jv_bool(true))
	color := found ? jni_get_int_field(env, tv, "data") : fallback
	jni_delete_local_ref(env, tv)
	jni_delete_local_ref(env, tv_cls)
	jni_delete_local_ref(env, theme)
	return color
}
