#+build linux:android
package nv

// Android list backend: ListView + nv.NvListAdapter (Java shim), rows reused via convertView.

// android.R constants (stable framework resource ids).
@(private) ANDROID_LAYOUT_SIMPLE_LIST_ITEM_2 :: 17367044
@(private) ANDROID_ID_TEXT1                  :: 16908308
@(private) ANDROID_ID_TEXT2                  :: 16908309

@(private)
_list_init :: proc(h: ^List_Handle) {
	env := g_android.env

	lv := list_view_new(env, g_android.activity)
	adapter := nv_list_adapter_new(env, i64(uintptr(h)))
	list_view_set_adapter(env, lv, adapter)
	adapter_view_set_on_item_click_listener(env, lv, adapter)

	h.root = View(jni_new_global_ref(env, lv))
	h.table = rawptr(h.root)
	h.data_source = rawptr(jni_new_global_ref(env, adapter))
	jni_delete_local_ref(env, adapter)
	jni_delete_local_ref(env, lv)
}

@(private)
_list_reload :: proc(h: ^List_Handle) {
	base_adapter_notify_data_set_changed(g_android.env, jobject(h.data_source))
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
		ctx := view_get_context(env, parent)
		inflater := layout_inflater_from(env, ctx)
		cell = layout_inflater_inflate(env, inflater, ANDROID_LAYOUT_SIMPLE_LIST_ITEM_2, parent, false)
		jni_delete_local_ref(env, inflater)
		jni_delete_local_ref(env, ctx)
	}

	r := h.list.item(h.list.user, int(position))
	set_row_text(env, cell, ANDROID_ID_TEXT1, r.title)
	set_row_text(env, cell, ANDROID_ID_TEXT2, r.subtitle)
	return cell
}

@(private)
set_row_text :: proc(env: JNI_Env, cell: jobject, id: int, text: string) {
	tv := view_find_view_by_id(env, cell, id)
	text_view_set_text(env, tv, text)
	jni_delete_local_ref(env, tv)
}
