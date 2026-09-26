#+build linux:android
package nv

// Android list backend: ListView + nv.NvListAdapter (Java shim), rows reused via convertView.

import "core:strings"

// android.R constants (stable framework resource ids).
@(private) ANDROID_LAYOUT_SIMPLE_LIST_ITEM_2 :: 17367044
@(private) ANDROID_ID_TEXT1                  :: 16908308
@(private) ANDROID_ID_TEXT2                  :: 16908309

@(private)
_list_init :: proc(h: ^List_Handle) {
	env := g_android.env

	lv_cls := jni_find_class(env, "android/widget/ListView")
	lv := jni_new_object(env, lv_cls, "(Landroid/content/Context;)V", jv_obj(g_android.activity))
	ad_cls := jni_find_class(env, "nv/NvListAdapter")
	adapter := jni_new_object(env, ad_cls, "(J)V", jv_long(i64(uintptr(h))))

	jni_call_void(env, lv, "setAdapter", "(Landroid/widget/ListAdapter;)V", jv_obj(adapter))
	jni_call_void(env, lv, "setOnItemClickListener", "(Landroid/widget/AdapterView$OnItemClickListener;)V", jv_obj(adapter))

	h.root = View(jni_new_global_ref(env, lv))
	h.table = rawptr(h.root)
	h.data_source = rawptr(jni_new_global_ref(env, adapter))
}

@(private)
_list_reload :: proc(h: ^List_Handle) {
	jni_call_void(g_android.env, jobject(h.data_source), "notifyDataSetChanged", "()V")
}

@(export, link_name="Java_nv_NvListAdapter_nativeCount")
jni_list_count :: proc "c" (env: JNI_Env, _: jclass, handle: jlong) -> jint {
	h := (^List_Handle)(uintptr(handle))
	context = h.ctx
	g_android.env = env
	return jint(h.list.count(h.list.user))
}

@(export, link_name="Java_nv_NvListAdapter_nativeOnSelect")
jni_list_on_select :: proc "c" (env: JNI_Env, _: jclass, handle: jlong, position: jint) {
	h := (^List_Handle)(uintptr(handle))
	context = h.ctx
	callback_enter()
	defer callback_exit()
	g_android.env = env
	if h.list.on_select != nil do h.list.on_select(h.list.user, int(position))
}

@(export, link_name="Java_nv_NvListAdapter_nativeGetView")
jni_list_get_view :: proc "c" (env: JNI_Env, _: jclass, handle: jlong, position: jint, convert, parent: jobject) -> jobject {
	h := (^List_Handle)(uintptr(handle))
	context = h.ctx
	callback_enter()
	defer callback_exit()
	g_android.env = env

	cell := convert
	if cell == nil {
		h.cells_created += 1
		ctx := jni_call_object(env, parent, "getContext", "()Landroid/content/Context;")
		inflater := jni_call_static_object(env, "android/view/LayoutInflater", "from",
			"(Landroid/content/Context;)Landroid/view/LayoutInflater;", jv_obj(ctx))
		cell = jni_call_object(env, inflater, "inflate", "(ILandroid/view/ViewGroup;Z)Landroid/view/View;",
			jv_int(ANDROID_LAYOUT_SIMPLE_LIST_ITEM_2), jv_obj(parent), jv_bool(false))
		jni_delete_local_ref(env, inflater)
		jni_delete_local_ref(env, ctx)
	}

	r := h.list.item(h.list.user, int(position))
	set_text(env, cell, ANDROID_ID_TEXT1, r.title)
	set_text(env, cell, ANDROID_ID_TEXT2, r.subtitle)
	return cell
}

@(private)
set_text :: proc(env: JNI_Env, cell: jobject, id: int, text: string) {
	tv := jni_call_object(env, cell, "findViewById", "(I)Landroid/view/View;", jv_int(id))
	s := jni_string(env, strings.clone_to_cstring(text, context.temp_allocator))
	jni_call_void(env, tv, "setText", "(Ljava/lang/CharSequence;)V", jv_obj(s))
	jni_delete_local_ref(env, s)
	jni_delete_local_ref(env, tv)
}
