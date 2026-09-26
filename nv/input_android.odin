#+build linux:android
package nv

// Android input backend: a single-line EditText with a Done action key. nv.NvInputListener
// (Java shim) forwards its TextWatcher and OnEditorActionListener callbacks. setText also fires
// the TextWatcher, which h.silent mutes.

import "core:strings"

@(private) ANDROID_IME_ACTION_DONE :: 6 // EditorInfo.IME_ACTION_DONE

@(private)
_input_init :: proc(h: ^Input_Handle) {
	env := g_android.env

	et_cls := jni_find_class(env, "android/widget/EditText")
	et := jni_new_object(env, et_cls, "(Landroid/content/Context;)V", jv_obj(g_android.activity))
	jni_call_void(env, et, "setSingleLine", "()V")
	jni_call_void(env, et, "setImeOptions", "(I)V", jv_int(ANDROID_IME_ACTION_DONE))
	set_char_sequence(env, et, "setText", h.input.text)
	if h.input.placeholder != "" do set_char_sequence(env, et, "setHint", h.input.placeholder)

	l_cls := jni_find_class(env, "nv/NvInputListener")
	listener := jni_new_object(env, l_cls, "(J)V", jv_long(i64(uintptr(h))))
	jni_call_void(env, et, "addTextChangedListener", "(Landroid/text/TextWatcher;)V", jv_obj(listener))
	jni_call_void(env, et, "setOnEditorActionListener", "(Landroid/widget/TextView$OnEditorActionListener;)V", jv_obj(listener))

	h.root = View(jni_new_global_ref(env, et))
	h.field = rawptr(h.root)
	h.delegate = rawptr(jni_new_global_ref(env, listener))
	jni_delete_local_ref(env, listener)
	jni_delete_local_ref(env, l_cls)
	jni_delete_local_ref(env, et)
	jni_delete_local_ref(env, et_cls)
}

@(private)
_input_text :: proc(h: ^Input_Handle, allocator := context.allocator) -> string {
	env := g_android.env
	editable := jni_call_object(env, jobject(h.field), "getText", "()Landroid/text/Editable;")
	s := jni_call_object(env, editable, "toString", "()Ljava/lang/String;")
	text := jni_string_clone(env, s, allocator)
	jni_delete_local_ref(env, s)
	jni_delete_local_ref(env, editable)
	return text
}

@(private)
_input_set_text :: proc(h: ^Input_Handle, text: string) {
	set_char_sequence(g_android.env, jobject(h.field), "setText", text)
}

// Calls a TextView `(CharSequence)V` setter such as setText or setHint.
@(private)
set_char_sequence :: proc(env: JNI_Env, view: jobject, method: cstring, text: string) {
	s := jni_string(env, strings.clone_to_cstring(text, context.temp_allocator))
	jni_call_void(env, view, method, "(Ljava/lang/CharSequence;)V", jv_obj(s))
	jni_delete_local_ref(env, s)
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
