#+build linux:android
package nv

// Android navigation backend: the top page is the Activity's content view and its title goes to
// the ActionBar (its custom view, nv.NvTitleView), which shows an up arrow on pushed pages and the
// page's actions as its options menu (nativeOnCreateMenu adds the items, item id = index + 1;
// invalidateOptionsMenu asks for a rebuild). Popped-under pages stay alive as global refs and are
// set as content again on pop: setContentView removes the previous content first, so a page never
// has a stale parent.

// android.R.drawable names by Icon (after icon_android.odin's drawn ones); "" shows the title as text.
@(private) android_icon_names := [Icon]cstring{
	.None     = "",
	.Add      = "ic_menu_add",
	.Edit     = "ic_menu_edit",
	.Delete   = "ic_menu_delete",
	.Search   = "ic_menu_search",
	.Share    = "ic_menu_share",
	.Settings = "ic_menu_preferences",
	.Refresh  = "ic_popup_sync",
	.Done     = "", // no public checkmark drawable
	.Info     = "ic_menu_info_details",
	.More     = "ic_menu_more",
	.Close    = "ic_menu_close_clear_cancel",
	.Menu     = "ic_menu_sort_by_size", // no public hamburger drawable; the closest set of lines
	.Home     = "ic_menu_myplaces",
	.Star     = "btn_star_big_on",
	.Person   = "", // no public person drawable
	.Hub      = "", // no public hub drawable
}

@(private) MENU_SHOW_AS_ACTION_IF_ROOM :: 1

@(private)
_nav_push :: proc(e: ^Page_Handle) {
	android_show(e)
}

@(private)
_nav_pop :: proc(top, below: ^Page_Handle) -> bool {
	android_show(below)
	return true
}

@(private)
_nav_release :: proc(e: ^Page_Handle) {
	scope_retire(e.scope) // setContentView already detached it; the scope holds the global refs
}

@(private)
android_show :: proc(e: ^Page_Handle) {
	activity_set_content_view(g_android.env, g_android.activity, jobject(e.root))
	android_chrome(e)
}

// Title, up arrow and (deferred by the framework, so an item can replace the menu from inside its
// own click) the options menu.
@(private)
android_chrome :: proc(e: ^Page_Handle) {
	env := g_android.env
	activity := g_android.activity
	if bar := activity_get_action_bar(env, activity); bar != nil {
		if g_android.title_view == nil do android_title_install(env, bar)
		menu := nav_shows_menu(e) // the up arrow becomes the drawer's menu button (nativeOnMenu)
		action_bar_set_display_home_as_up_enabled(env, bar, len(g_nav) > 1 || menu)
		if menu {
			icon := android_icon_drawable(env, .Menu, theme_palette().text)
			action_bar_set_home_as_up_indicator_drawable(env, bar, icon)
			jni_delete_local_ref(env, icon)
		} else {
			action_bar_set_home_as_up_indicator(env, bar, 0) // the theme's arrow
		}
		// The bar's color is the Activity theme's (colorPrimary), as the other platforms' bars are theirs.
		jni_delete_local_ref(env, bar)
	}
	android_set_title(env, e.page.title)
	activity_invalidate_options_menu(env, activity)
}

// The ActionBar shows the top page only; a lower page's changes are picked up when it is shown again.
@(private)
_nav_title_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do android_set_title(g_android.env, e.page.title)
}

// The title as the bar's custom view (nv.NvTitleView: centred, as on iOS) in the bar title style,
// once per Activity. Its context is the bar's themed one, for the bar's text color.
@(private)
android_title_install :: proc(env: JNI_Env, bar: jobject) {
	ctx := action_bar_get_themed_context(env, bar)
	tv := nv_title_view_new(env, ctx)
	jni_delete_local_ref(env, ctx)
	android_style_text(env, tv, theme_bar_title()) // over the ActionBar title's own look (NvTitleView)
	lp := action_bar_layout_params_new(env, LAYOUT_MATCH_PARENT, LAYOUT_MATCH_PARENT)
	action_bar_set_custom_view(env, bar, tv, lp)
	jni_delete_local_ref(env, lp)
	action_bar_set_display_show_title_enabled(env, bar, false)
	action_bar_set_display_show_custom_enabled(env, bar, true)
	g_android.title_view = jni_new_global_ref(env, tv)
	jni_delete_local_ref(env, tv)
}

// The page title: the bar's title view, and the Activity's title (accessibility, recents).
@(private)
android_set_title :: proc(env: JNI_Env, title: string) {
	activity_set_title(env, g_android.activity, title)
	if g_android.title_view != nil do text_view_set_text(env, g_android.title_view, title)
}

// `text` as a SpannableString in `s`'s typeface (none when the style sets no font: the view's
// own); a local ref.
@(private)
android_styled_text :: proc(env: JNI_Env, text: string, s: Text_Style, bold: bool) -> jobject {
	SPAN_EXCLUSIVE_EXCLUSIVE :: 33
	str := spannable_string_new(env, text)
	if s.font == nil do return str
	if tf := android_style_typeface(env, s, bold); tf != nil {
		n := 0 // UTF-16 units
		for r in text do n += r >= 0x10000 ? 2 : 1
		span := typeface_span_new(env, tf)
		spannable_set_span(env, str, span, 0, n, SPAN_EXCLUSIVE_EXCLUSIVE)
		jni_delete_local_ref(env, span)
	}
	return str
}

@(private)
_nav_actions_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do activity_invalidate_options_menu(g_android.env, g_android.activity)
}

// onCreateOptionsMenu: fills the (empty) menu with the top page's actions.
@(export, link_name="Java_nv_NvActivity_nativeOnCreateMenu")
jni_on_create_menu :: proc "c" (env: JNI_Env, _: jclass, menu: jobject) {
	context = g_android.ctx
	g_android.env = env
	if len(g_nav) == 0 do return
	callback_enter()
	defer callback_exit()
	e := g_nav[len(g_nav) - 1]
	for h, i in e.actions {
		title := android_styled_text(env, h.action.title, g_theme.body, false) // a text action in the body font
		item := jni_call_object(env, menu, &jm_menu_add, jv_int(0), jv_int(i + 1), jv_int(i), jv_obj(title))
		jni_delete_local_ref(env, title)
		if item == nil do continue
		if icon := android_icon_drawable(env, h.action.icon, theme_palette().text); icon != nil {
			jni_delete_local_ref(env, menu_item_set_icon_drawable(env, item, icon))
			jni_delete_local_ref(env, icon)
		} else if id := android_icon_res(env, h.action.icon); id != 0 {
			jni_delete_local_ref(env, menu_item_set_icon(env, item, id))
		}
		menu_item_set_show_as_action(env, item, MENU_SHOW_AS_ACTION_IF_ROOM)
		jni_delete_local_ref(env, item)
	}
}

// onOptionsItemSelected for an item other than the up arrow. False for an unknown id.
@(export, link_name="Java_nv_NvActivity_nativeOnAction")
jni_on_action :: proc "c" (env: JNI_Env, _: jclass, id: jint) -> jboolean {
	context = g_android.ctx
	g_android.env = env
	if len(g_nav) == 0 do return 0
	e := g_nav[len(g_nav) - 1]
	i := int(id) - 1
	if i < 0 || i >= len(e.actions) do return 0
	action_notify(e.actions[i])
	return 1
}

// Back key or ActionBar up arrow. A modal dialog takes it first and closes, as Android dialogs
// do, then an open drawer. Returns false on the root page, so the default handling finishes the Activity (or moves the
// task to the back when the launcher started it).
@(export, link_name="Java_nv_NvActivity_nativeOnBack")
jni_on_back :: proc "c" (env: JNI_Env, _: jclass) -> jboolean {
	context = g_android.ctx
	g_android.env = env
	if d := dialog_top_modal(); d != nil {
		callback_enter()
		defer callback_exit()
		dialog_close(d)
		return 1
	}
	if s := scaffold_top_drawer(); s != nil { // an open drawer closes before anything pops
		callback_enter()
		defer callback_exit()
		scaffold_close_drawer(s)
		return 1
	}
	if len(g_nav) <= 1 do return 0
	callback_enter()
	defer callback_exit()
	pop()
	return 1
}

// The ActionBar's home button on a root page with a drawer (nav_shows_menu) toggles the drawer;
// false elsewhere, so NvActivity goes on to nativeOnBack.
@(export, link_name="Java_nv_NvActivity_nativeOnMenu")
jni_on_menu :: proc "c" (env: JNI_Env, _: jclass) -> jboolean {
	context = g_android.ctx
	g_android.env = env
	if len(g_nav) == 0 || !nav_shows_menu(g_nav[len(g_nav) - 1]) do return 0
	nav_menu_notify()
	return 1
}
