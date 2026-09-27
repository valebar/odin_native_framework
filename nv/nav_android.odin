#+build linux:android
package nv

// Android navigation backend: the top page is the Activity's content view and its title goes to
// the ActionBar (Theme.Material.Light.DarkActionBar in the manifest), which shows an up arrow on
// pushed pages. Popped-under pages stay alive as global refs and are set as content again on pop:
// setContentView removes the previous content first, so a page never has a stale parent.

import "core:strings"

@(private)
_nav_push :: proc(e: ^Nav_Page) {
	android_show(e)
}

@(private)
_nav_pop :: proc(top, below: ^Nav_Page) -> bool {
	android_show(below)
	return true
}

@(private)
_nav_release :: proc(e: ^Nav_Page) {
	jni_delete_global_ref(g_android.env, jobject(e.root))
}

@(private)
android_show :: proc(e: ^Nav_Page) {
	env := g_android.env
	activity := g_android.activity
	jni_call_void(env, activity, "setContentView", "(Landroid/view/View;)V", jv_obj(jobject(e.root)))
	jni_call_void(env, activity, "setTitle", "(Ljava/lang/CharSequence;)V",
		jv_obj(jni_string(env, strings.clone_to_cstring(e.page.title, context.temp_allocator))))
	if bar := jni_call_object(env, activity, "getActionBar", "()Landroid/app/ActionBar;"); bar != nil {
		jni_call_void(env, bar, "setDisplayHomeAsUpEnabled", "(Z)V", jv_bool(len(g_nav) > 1))
		jni_delete_local_ref(env, bar)
	}
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
