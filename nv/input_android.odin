#+build linux:android
#+private
package nv

// Android input backend: a single-line EditText with a Done action key. nv.NvInputListener
// (Java shim) forwards its TextWatcher and OnEditorActionListener callbacks. setText also fires
// the TextWatcher, which h.silent mutes.

@(private) ANDROID_IME_ACTION_DONE :: 6 // EditorInfo.IME_ACTION_DONE

// android.text.InputType
@(private) ANDROID_TYPE_CLASS_TEXT               :: 0x1
@(private) ANDROID_TYPE_CLASS_NUMBER             :: 0x2
@(private) ANDROID_TYPE_TEXT_FLAG_CAP_SENTENCES  :: 0x4000
@(private) ANDROID_TYPE_TEXT_VARIATION_PASSWORD  :: 0x80
@(private) ANDROID_TYPE_NUMBER_FLAG_SIGNED       :: 0x1000
@(private) ANDROID_TYPE_NUMBER_FLAG_DECIMAL      :: 0x2000
@(private) ANDROID_TYPE_NUMBER_VARIATION_PASSWORD :: 0x10

// The field's inputType; 0 keeps EditText's own (plain text). Decimal has no sign, like iOS's
// decimal pad.
@(private)
android_input_type :: proc "contextless" (i: Input) -> int {
	t := 0
	switch i.keyboard {
	case .Text:          if i.secure do t = ANDROID_TYPE_CLASS_TEXT
	case .Sentences:     t = ANDROID_TYPE_CLASS_TEXT | ANDROID_TYPE_TEXT_FLAG_CAP_SENTENCES
	case .Number:        t = ANDROID_TYPE_CLASS_NUMBER
	case .Signed_Number: t = ANDROID_TYPE_CLASS_NUMBER | ANDROID_TYPE_NUMBER_FLAG_SIGNED
	case .Decimal:       t = ANDROID_TYPE_CLASS_NUMBER | ANDROID_TYPE_NUMBER_FLAG_DECIMAL
	}
	if i.secure do t |= (t & ANDROID_TYPE_CLASS_NUMBER) != 0 ? ANDROID_TYPE_NUMBER_VARIATION_PASSWORD : ANDROID_TYPE_TEXT_VARIATION_PASSWORD
	return t
}

@(private)
_input_init :: proc(h: ^Input_Handle) {
	env := g_android.env

	et := edit_text_new(env, g_android.activity)
	text_view_set_single_line(env, et)
	// After setSingleLine, whose transformation would undo the password's; before the style, since
	// a password type sets a monospace typeface.
	if t := android_input_type(h.input); t != 0 do text_view_set_input_type(env, et, t)
	text_view_set_ime_options(env, et, ANDROID_IME_ACTION_DONE)
	text_view_set_text(env, et, h.input.text)
	if h.input.placeholder != "" do text_view_set_hint(env, et, h.input.placeholder)
	android_style_text(env, et, h.input.style)
	android_tint_accent(env, et)

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

// NvInputListener.focus: requestFocus, the selection and showSoftInput, posted so that a field
// added just now (a dialog's) is in the window first.
@(private)
_input_focus :: proc(h: ^Input_Handle, select_all: bool) {
	nv_input_listener_focus(g_android.env, jobject(h.field), select_all)
}
