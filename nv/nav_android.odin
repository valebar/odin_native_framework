#+build linux:android
package nv

// Android navigation backend: the top page is the Activity's content view and its title goes to
// the ActionBar (Theme.Material.Light.DarkActionBar in the manifest), which shows an up arrow on
// pushed pages and the page's actions as its options menu (nativeOnCreateMenu adds the items, item
// id = index + 1; invalidateOptionsMenu asks for a rebuild). Popped-under pages stay alive as
// global refs and are set as content again on pop: setContentView removes the previous content
// first, so a page never has a stale parent.

import "core:strings"

// android.R.drawable names by Icon; "" shows the title as text.
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
	jni_delete_global_ref(g_android.env, jobject(e.root))
}

@(private)
android_show :: proc(e: ^Page_Handle) {
	jni_call_void(g_android.env, g_android.activity, "setContentView", "(Landroid/view/View;)V", jv_obj(jobject(e.root)))
	android_chrome(e)
}

// Title, up arrow and (deferred by the framework, so an item can replace the menu from inside its
// own click) the options menu.
@(private)
android_chrome :: proc(e: ^Page_Handle) {
	env := g_android.env
	activity := g_android.activity
	set_char_sequence(env, activity, "setTitle", e.page.title)
	if bar := jni_call_object(env, activity, "getActionBar", "()Landroid/app/ActionBar;"); bar != nil {
		jni_call_void(env, bar, "setDisplayHomeAsUpEnabled", "(Z)V", jv_bool(len(g_nav) > 1))
		jni_delete_local_ref(env, bar)
	}
	jni_call_void(env, activity, "invalidateOptionsMenu", "()V")
}

// The ActionBar shows the top page only; a lower page's changes are picked up when it is shown again.
@(private)
_nav_title_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do set_char_sequence(g_android.env, g_android.activity, "setTitle", e.page.title)
}

@(private)
_nav_actions_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do jni_call_void(g_android.env, g_android.activity, "invalidateOptionsMenu", "()V")
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
		title := jni_string(env, strings.clone_to_cstring(h.action.title, context.temp_allocator))
		item := jni_call_object(env, menu, "add", "(IIILjava/lang/CharSequence;)Landroid/view/MenuItem;",
			jv_int(0), jv_int(i + 1), jv_int(i), jv_obj(title))
		jni_delete_local_ref(env, title)
		if item == nil do continue
		if name := android_icon_names[h.action.icon]; name != "" {
			if id := jni_get_static_int_field(env, "android/R$drawable", name); id != 0 {
				jni_delete_local_ref(env, jni_call_object(env, item, "setIcon", "(I)Landroid/view/MenuItem;", jv_int(int(id))))
			}
		}
		jni_call_void(env, item, "setShowAsAction", "(I)V", jv_int(MENU_SHOW_AS_ACTION_IF_ROOM))
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

// Back key or ActionBar up arrow. Returns false on the root page so the Activity finishes.
@(export, link_name="Java_nv_NvActivity_nativeOnBack")
jni_on_back :: proc "c" (env: JNI_Env, _: jclass) -> jboolean {
	context = g_android.ctx
	g_android.env = env
	if len(g_nav) <= 1 do return 0
	callback_enter()
	defer callback_exit()
	pop()
	return 1
}
