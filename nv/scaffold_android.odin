#+build linux:android
package nv

// Android scaffold backend: the overlay is a FrameLayout (the base MATCH_PARENT, the children
// placed by FrameLayout.LayoutParams gravity, size and margins), the scrim a clickable translucent
// View, the FAB an ImageButton (or a Button when it has a label) on an accent GradientDrawable, the
// tab bar a LinearLayout of clickable icon + title items (the platform has no BottomNavigationView;
// that is Material Components), and the timer nv.NvTimer (Handler.postDelayed). Every child of the
// overlay is clickable, so a touch on it stops there instead of reaching the views under it (a
// ViewGroup offers a touch to lower siblings when the top child ignores it). nv.NvTapListener
// forwards the clicks; its `kind` says which handle it carries.

@(private) ANDROID_GRAVITY_START  :: 0x00800003
@(private) ANDROID_GRAVITY_END    :: 0x00800005
@(private) ANDROID_GRAVITY_CENTER_HORIZONTAL :: 0x01
@(private) ANDROID_GRAVITY_TOP    :: 0x30
@(private) ANDROID_GRAVITY_BOTTOM :: 0x50
@(private) ANDROID_GRAVITY_CENTER_VERTICAL :: 0x10
@(private) ANDROID_SHAPE_OVAL     :: 1 // GradientDrawable.OVAL

@(private) TAP_SCRIM :: 0
@(private) TAP_FAB   :: 1
@(private) TAP_TAB   :: 2 // + the tab index

@(private)
_view_set_hidden :: proc(v: View, hidden: bool) {
	view_set_visibility(g_android.env, jobject(v), hidden ? ANDROID_VIEW_GONE : ANDROID_VIEW_VISIBLE)
}

// ViewGroup.FOCUS_BEFORE_DESCENDANTS (a ViewGroup's default) / FOCUS_BLOCK_DESCENDANTS, which also
// takes the focus from a descendant that has it. The base under the drawer is always a ViewGroup.
@(private) ANDROID_FOCUS_BEFORE_DESCENDANTS :: 0x20000
@(private) ANDROID_FOCUS_BLOCK_DESCENDANTS  :: 0x60000

@(private)
_view_set_enabled :: proc(v: View, enabled: bool) {
	view_group_set_descendant_focusability(g_android.env, jobject(v), enabled ? ANDROID_FOCUS_BEFORE_DESCENDANTS : ANDROID_FOCUS_BLOCK_DESCENDANTS)
}

@(private)
_overlay_init :: proc(h: ^Overlay_Handle) {
	env := g_android.env
	frame := frame_layout_new(env, g_android.activity)
	lp := frame_lp_new(env, LAYOUT_MATCH_PARENT, LAYOUT_MATCH_PARENT)
	view_group_add_view(env, frame, jobject(h.base), lp)
	jni_delete_local_ref(env, lp)
	h.root = View(android_own_ref(env, frame))
	jni_delete_local_ref(env, frame)
}

@(private)
_overlay_add :: proc(h: ^Overlay_Handle, child: View, place: Overlay_Place) {
	env := g_android.env
	view_set_clickable(env, jobject(child), true)
	lp := overlay_lp(place)
	view_group_add_view(env, jobject(h.root), jobject(child), lp) // above the earlier ones
	jni_delete_local_ref(env, lp)
}

@(private)
_overlay_place :: proc(h: ^Overlay_Handle, child: View, place: Overlay_Place) {
	env := g_android.env
	lp := overlay_lp(place)
	view_set_layout_params(env, jobject(child), lp)
	jni_delete_local_ref(env, lp)
}

// A local ref to the child's FrameLayout.LayoutParams.
@(private)
overlay_lp :: proc(place: Overlay_Place) -> jobject {
	env := g_android.env
	size :: proc(a: Align, s: f64) -> int {
		if a == .Fill do return LAYOUT_MATCH_PARENT
		return s > 0 ? android_dp(s) : LAYOUT_WRAP_CONTENT
	}
	gravity := 0
	switch place.h {
	case .Start:  gravity |= ANDROID_GRAVITY_START
	case .Center: gravity |= ANDROID_GRAVITY_CENTER_HORIZONTAL
	case .End:    gravity |= ANDROID_GRAVITY_END
	case .Fill:
	}
	switch place.v {
	case .Start:  gravity |= ANDROID_GRAVITY_TOP
	case .Center: gravity |= ANDROID_GRAVITY_CENTER_VERTICAL
	case .End:    gravity |= ANDROID_GRAVITY_BOTTOM
	case .Fill:
	}
	lp := frame_lp_new_gravity(env, size(place.h, place.width), size(place.v, place.height), gravity)
	m := place.margin
	view_group_margin_layout_params_set_margins(env, lp, android_dp(m.left), android_dp(m.top), android_dp(m.right), android_dp(m.bottom))
	return lp
}

@(private)
_overlay_scrim_init :: proc(h: ^Overlay_Handle) {
	env := g_android.env
	scrim := view_new(env, g_android.activity)
	view_set_background_color(env, scrim, ANDROID_SCRIM_ARGB)
	android_on_tap(env, scrim, h, TAP_SCRIM) // clickable: the touch stops at the scrim
	lp := frame_lp_new(env, LAYOUT_MATCH_PARENT, LAYOUT_MATCH_PARENT)
	view_group_add_view(env, jobject(h.root), scrim, lp)
	jni_delete_local_ref(env, lp)
	h.scrim = View(android_own_ref(env, scrim))
	jni_delete_local_ref(env, scrim)
}

@(private)
_fab_init :: proc(h: ^Fab_Handle) {
	env := g_android.env
	activity := g_android.activity
	accent := android_argb(theme_palette().accent)
	icon := android_icon_res(env, h.fab.icon)
	if icon == 0 && h.fab.label == "" do icon = android_icon_res(env, .Add) // no image for it here
	bg := gradient_drawable_new(env)
	gradient_drawable_set_color(env, bg, accent)
	b: jobject
	if h.fab.label == "" && icon != 0 {
		b = image_button_new(env, activity)
		gradient_drawable_set_shape(env, bg, ANDROID_SHAPE_OVAL)
		image_view_set_image_resource(env, b, icon)
		image_view_set_color_filter(env, b, android_argb({1, 1, 1, 1}))
		pad := android_dp(16) // a 24dp icon in the 56dp circle
		view_set_padding(env, b, pad, pad, pad, pad)
		view_set_minimum_width(env, b, android_dp(56))
	} else { // extended: the label, with the icon before it
		b = button_new(env, activity)
		gradient_drawable_set_corner_radius(env, bg, f32(android_dp(28)))
		text_view_set_text(env, b, h.fab.label)
		text_view_set_text_color(env, b, android_argb({1, 1, 1, 1}))
		if icon != 0 {
			text_view_set_compound_drawables_relative_with_intrinsic_bounds(env, b, icon, 0, 0, 0)
			text_view_set_compound_drawable_padding(env, b, android_dp(8))
		}
		view_set_padding(env, b, android_dp(20), 0, android_dp(20), 0)
	}
	view_set_minimum_height(env, b, android_dp(56))
	view_set_background(env, b, bg)
	view_set_elevation(env, b, f32(android_dp(6)))
	h.target = rawptr(android_on_tap(env, b, h, TAP_FAB))
	h.root = View(android_own_ref(env, b))
	h.control = rawptr(h.root)
	jni_delete_local_ref(env, bg)
	jni_delete_local_ref(env, b)
}

// One tab's icon and title (Tabbar_Handle.items, in the scope's arena), recolored on selection.
@(private) Android_Tab :: struct {
	image: jobject, // nil without an icon
	title: jobject,
}

@(private)
_tabbar_init :: proc(h: ^Tabbar_Handle) {
	env := g_android.env
	activity := g_android.activity
	bar := linear_layout_new(env, activity)
	linear_layout_set_orientation(env, bar, int(Axis.Horizontal))
	view_set_background_color(env, bar, android_argb(theme_palette().surface))
	view_set_elevation(env, bar, f32(android_dp(8)))
	tabs := make([]Android_Tab, len(h.tabs), scope_allocator(scope_current()))
	for t, i in h.tabs {
		item := linear_layout_new(env, activity)
		linear_layout_set_orientation(env, item, int(Axis.Vertical))
		linear_layout_set_gravity(env, item, ANDROID_GRAVITY_CENTER)
		pad := android_dp(6)
		view_set_padding(env, item, 0, pad, 0, pad)
		if icon := android_icon_res(env, t.icon); icon != 0 {
			img := image_view_new(env, activity)
			image_view_set_image_resource(env, img, icon)
			lp := linear_lp_new(env, android_dp(24), android_dp(24), 0)
			view_group_add_view(env, item, img, lp)
			jni_delete_local_ref(env, lp)
			tabs[i].image = android_own_ref(env, img)
			jni_delete_local_ref(env, img)
		}
		title := text_view_new(env, activity)
		text_view_set_text(env, title, t.title)
		text_view_set_text_size(env, title, 12)
		lp := linear_lp_new(env, LAYOUT_WRAP_CONTENT, LAYOUT_WRAP_CONTENT, 0)
		view_group_add_view(env, item, title, lp)
		jni_delete_local_ref(env, lp)
		tabs[i].title = android_own_ref(env, title)
		jni_delete_local_ref(env, title)

		android_on_tap(env, item, h, TAP_TAB + i)
		item_lp := linear_lp_new(env, 0, LAYOUT_WRAP_CONTENT, 1)
		view_group_add_view(env, bar, item, item_lp)
		jni_delete_local_ref(env, item_lp)
		jni_delete_local_ref(env, item)
	}
	h.items = raw_data(tabs)
	h.root = View(android_own_ref(env, bar))
	h.control = rawptr(h.root)
	jni_delete_local_ref(env, bar)
	tabbar_paint(h, h.selected)
}

@(private)
_tabbar_select :: proc(h: ^Tabbar_Handle) {
	tabbar_paint(h, h.selected)
}

// The selected tab in the accent, the others in the secondary text color.
@(private)
tabbar_paint :: proc(h: ^Tabbar_Handle, selected: int) {
	env := g_android.env
	p := theme_palette()
	tabs := ([^]Android_Tab)(h.items)[:len(h.tabs)]
	for t, i in tabs {
		c := android_argb(i == selected ? p.accent : p.secondary_text)
		if t.image != nil do image_view_set_color_filter(env, t.image, c)
		text_view_set_text_color(env, t.title, c)
	}
}

@(private)
_post_delayed :: proc(ms: int, t: ^Timer) {
	nv_timer_start(g_android.env, i64(uintptr(t)), i64(max(ms, 0)))
}

@(export, link_name="Java_nv_NvTimer_nativeOnTimer")
jni_on_timer :: proc "c" (env: JNI_Env, _: jclass, timer: jlong) {
	g_android.env = env
	timer_fire((^Timer)(uintptr(timer)))
}

// Makes `v` clickable through an nv.NvTapListener carrying `handle` and `kind`; returns the
// listener's global ref, which the scope deletes.
@(private)
android_on_tap :: proc(env: JNI_Env, v: jobject, handle: rawptr, kind: int) -> jobject {
	listener := nv_tap_listener_new(env, i64(uintptr(handle)), kind)
	view_set_on_click_listener(env, v, listener) // makes it clickable too
	ref := android_own_ref(env, listener)
	jni_delete_local_ref(env, listener)
	return ref
}

@(export, link_name="Java_nv_NvTapListener_nativeOnTap")
jni_on_tap :: proc "c" (env: JNI_Env, _: jclass, handle: jlong, kind: jint) {
	g_android.env = env
	switch {
	case kind == TAP_SCRIM:
		h := (^Overlay_Handle)(uintptr(handle))
		context = h.ctx
		overlay_scrim_notify(h)
	case kind == TAP_FAB:
		h := (^Fab_Handle)(uintptr(handle))
		context = h.ctx
		fab_notify(h)
	case:
		h := (^Tabbar_Handle)(uintptr(handle))
		context = h.ctx
		i := int(kind) - TAP_TAB
		if i < 0 || i >= len(h.tabs) do return
		tabbar_paint(h, i) // before the notify: its on_tab may pop the page, which frees h
		tabbar_notify(h, i)
	}
}

// The android.R.drawable resource id of an icon, 0 when there is none.
@(private)
android_icon_res :: proc(env: JNI_Env, icon: Icon) -> int {
	name := android_icon_names[icon]
	if name == "" do return 0
	return int(jni_get_static_int_field(env, "android/R$drawable", name))
}
