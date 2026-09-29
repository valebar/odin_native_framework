#+build linux:android
package nv

// Android theme backend. The manifest's Theme.DeviceDefault.DayNight follows the system, and
// UiModeManager.setApplicationNightMode (API 31) forces light or dark for this app. A change of
// the night mode recreates the Activity (uiMode is not in the manifest's configChanges, so the
// views are inflated again with the new theme colors); jni_on_create's relaunch path then reports
// it through theme_notify and rebuilds the root page. The accent tints the buttons, the inputs and
// the ActionBar. Text styles go on any TextView through android_style_text; a loaded Font is a
// Typeface (font_android.odin), from which Typeface.create derives a weight / slant when asked.

@(private) ANDROID_MODE_NIGHT_AUTO    :: 0
@(private) ANDROID_MODE_NIGHT_NO      :: 1
@(private) ANDROID_MODE_NIGHT_YES     :: 2
@(private) ANDROID_UI_MODE_NIGHT_MASK :: 0x30
@(private) ANDROID_UI_MODE_NIGHT_YES  :: 0x20

// The system's night mode: Resources.getSystem() carries no per-app override.
@(private)
_theme_system_dark :: proc() -> bool {
	env := g_android.env
	res := resources_get_system(env)
	cfg := resources_get_configuration(env, res)
	mode := configuration_ui_mode(env, cfg)
	jni_delete_local_ref(env, cfg)
	jni_delete_local_ref(env, res)
	return mode & ANDROID_UI_MODE_NIGHT_MASK == ANDROID_UI_MODE_NIGHT_YES
}

@(private)
_theme_system_accent :: proc() -> Color {
	c := u32(android_theme_color("colorAccent", 0))
	if c == 0 do return {}
	return {f32(c >> 16 & 0xff) / 255, f32(c >> 8 & 0xff) / 255, f32(c & 0xff) / 255, f32(c >> 24) / 255}
}

// A no-op when the app's night mode already matches, else the Activity is recreated.
@(private)
_theme_apply_mode :: proc() {
	env := g_android.env
	mode := ANDROID_MODE_NIGHT_AUTO
	switch g_theme.mode {
	case .System:
	case .Light: mode = ANDROID_MODE_NIGHT_NO
	case .Dark:  mode = ANDROID_MODE_NIGHT_YES
	}
	manager := context_get_system_service(env, g_android.activity, "uimode") // Context.UI_MODE_SERVICE
	if manager != nil {
		ui_mode_manager_set_application_night_mode(env, manager, mode)
		jni_delete_local_ref(env, manager)
	}
}

// The views are recreated with the Activity.
@(private)
_theme_recolor :: proc() {}

// The Typefaces derived from one family by weight and slant, as global refs made on first use:
// a loaded Font's in Font.extra (deleted with it), the system family's in g_android_typefaces.
// Typeface.create per use would make a Java object on every canvas text draw.
@(private) Typeface_Cache :: [Weight][2]jobject // [weight][italic]
@(private) g_android_typefaces: Typeface_Cache

// A Typeface of the weight (100..900) and slant derived from `base` (null: the default family),
// from `cache`; Typeface.create(Typeface, int, boolean) is API 28. Never owned by the caller.
@(private)
android_typeface :: proc "contextless" (env: JNI_Env, base: jobject, cache: ^Typeface_Cache, w: Weight, bold, italic: bool) -> jobject {
	wt := text_weight(w, bold)
	slot := &cache[wt][italic ? 1 : 0]
	if slot^ == nil {
		weight := 400
		#partial switch wt {
		case .Medium:   weight = 500
		case .Semibold: weight = 600
		case .Bold:     weight = 700
		}
		local := typeface_create(env, base, weight, italic)
		if local == nil do return nil
		slot^ = jni_new_global_ref(env, local)
		jni_delete_local_ref(env, local)
	}
	return slot^
}

// The Typeface for a style: the loaded face itself unless a weight or slant is asked over it,
// else a system one of the style's weight; `bold` is the widget's default weight. nil when the
// style leaves the system font alone. Global refs the caller neither owns nor deletes.
@(private)
android_style_typeface :: proc "contextless" (env: JNI_Env, s: Text_Style, bold: bool) -> jobject {
	if f := s.font; f != nil {
		if s.weight == .Default && !s.italic do return jobject(f.native)
		return android_typeface(env, jobject(f.native), (^Typeface_Cache)(f.extra), s.weight, false, s.italic)
	}
	if bold || s.weight != .Default || s.italic do return android_typeface(env, nil, &g_android_typefaces, s.weight, bold, s.italic)
	return nil
}

// Applies a style to a TextView (or a Button / EditText). `size` and `bold` are the view's
// defaults for the zero fields; with no font, size, weight or slant the view keeps its own font.
@(private)
android_style_text :: proc "contextless" (env: JNI_Env, tv: jobject, s: Text_Style, size: f64 = 0, bold := false) {
	if sz := s.size > 0 ? s.size : size; sz > 0 do text_view_set_text_size(env, tv, f32(sz)) // sp
	if tf := android_style_typeface(env, s, bold); tf != nil do text_view_set_typeface(env, tv, tf)
	if s.color.a > 0 do text_view_set_text_color(env, tv, android_argb(s.color))
}

// Tints a view's background (a Button's shape, an EditText's underline) with the accent.
@(private)
android_tint_accent :: proc "contextless" (env: JNI_Env, v: jobject) {
	if g_theme.accent.a == 0 do return
	list := color_state_list_value_of(env, android_argb(g_theme.accent))
	view_set_background_tint_list(env, v, list)
	jni_delete_local_ref(env, list)
}
