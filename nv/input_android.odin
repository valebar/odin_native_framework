#+build linux:android
package nv

// Android input backend: a single-line EditText with a Done action key. nv.NvInputListener
// (Java shim) forwards its TextWatcher and OnEditorActionListener callbacks. setText also fires
// the TextWatcher, which h.silent mutes.

@(private) ANDROID_IME_ACTION_DONE :: 6 // EditorInfo.IME_ACTION_DONE

@(private)
_input_init :: proc(h: ^Input_Handle) {
	env := g_android.env

	et := edit_text_new(env, g_android.activity)
	text_view_set_single_line(env, et)
	text_view_set_ime_options(env, et, ANDROID_IME_ACTION_DONE)
	text_view_set_text(env, et, h.input.text)
	if h.input.placeholder != "" do text_view_set_hint(env, et, h.input.placeholder)
	android_apply_font(env, et, h.input.font, h.input.size)

	listener := nv_input_listener_new(env, i64(uintptr(h)))
	text_view_add_text_changed_listener(env, et, listener)
	text_view_set_on_editor_action_listener(env, et, listener)

	h.root = View(android_own_ref(env, et))
	h.field = rawptr(h.root)
	h.delegate = rawptr(android_own_ref(env, listener))
	jni_delete_local_ref(env, listener)
	jni_delete_local_ref(env, et)
}

@(private)
_input_text :: proc(h: ^Input_Handle, allocator := context.allocator) -> string {
	env := g_android.env
	editable := edit_text_get_text(env, jobject(h.field))
	s := object_to_string(env, editable)
	text := jni_string_clone(env, s, allocator)
	jni_delete_local_ref(env, s)
	jni_delete_local_ref(env, editable)
	return text
}

@(private)
_input_set_text :: proc(h: ^Input_Handle, text: string) {
	text_view_set_text(g_android.env, jobject(h.field), text)
}

@(export, link_name="Java_nv_NvInputListener_nativeOnChange")
jni_input_on_change :: proc "c" (env: JNI_Env, _: jclass, handle: jlong) {
	h := (^Input_Handle)(uintptr(handle))
	context = h.ctx
	g_android.env = env
	input_notify(h, h.input.on_change)
}

@(export, link_name="Java_nv_NvInputListener_nativeOnSubmit")
jni_input_on_submit :: proc "c" (env: JNI_Env, _: jclass, handle: jlong) {
	h := (^Input_Handle)(uintptr(handle))
	context = h.ctx
	g_android.env = env
	input_notify(h, h.input.on_submit)
}
