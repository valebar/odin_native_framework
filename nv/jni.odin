#+build linux:android
package nv

// Minimal JNI binding. Function indices follow `struct JNINativeInterface` in the NDK's jni.h.

jobject   :: distinct rawptr
jclass    :: jobject
jstring   :: jobject
jmethodID :: distinct rawptr
jint      :: i32
jlong     :: i64
jboolean  :: u8

jvalue :: struct #raw_union {
	z: jboolean,
	i: jint,
	j: jlong,
	f: f32,
	d: f64,
	l: jobject,
}

// JNIEnv* = pointer to the function table pointer.
JNI_Env :: ^[^]rawptr

@(private) JNI_FIND_CLASS            :: 6
@(private) JNI_EXCEPTION_DESCRIBE    :: 16
@(private) JNI_EXCEPTION_CLEAR       :: 17
@(private) JNI_NEW_GLOBAL_REF        :: 21
@(private) JNI_DELETE_GLOBAL_REF     :: 22
@(private) JNI_DELETE_LOCAL_REF      :: 23
@(private) JNI_NEW_OBJECT_A          :: 30
@(private) JNI_GET_OBJECT_CLASS      :: 31
@(private) JNI_GET_METHOD_ID         :: 33
@(private) JNI_CALL_OBJECT_METHOD_A  :: 36
@(private) JNI_CALL_BOOLEAN_METHOD_A :: 39
@(private) JNI_CALL_INT_METHOD_A     :: 51
@(private) JNI_CALL_FLOAT_METHOD_A   :: 57
@(private) JNI_CALL_VOID_METHOD_A    :: 63
@(private) JNI_GET_FIELD_ID          :: 94
@(private) JNI_GET_INT_FIELD         :: 100
@(private) JNI_GET_FLOAT_FIELD       :: 102
@(private) JNI_GET_STATIC_METHOD_ID  :: 113
@(private) JNI_CALL_STATIC_OBJECT_A  :: 116
@(private) JNI_GET_STATIC_FIELD_ID    :: 144
@(private) JNI_GET_STATIC_INT_FIELD   :: 150
@(private) JNI_NEW_STRING_UTF        :: 167
@(private) JNI_GET_STRING_UTF_LENGTH :: 168
@(private) JNI_GET_STRING_UTF_CHARS  :: 169
@(private) JNI_RELEASE_STRING_UTF_CHARS :: 170
@(private) JNI_EXCEPTION_CHECK       :: 228

@(private)
jni_fn :: #force_inline proc "contextless" (env: JNI_Env, $T: typeid, index: int) -> T {
	return cast(T)env^[index]
}

jni_find_class :: proc "contextless" (env: JNI_Env, name: cstring) -> jclass {
	return jni_fn(env, proc "c" (JNI_Env, cstring) -> jclass, JNI_FIND_CLASS)(env, name)
}

jni_new_global_ref :: proc "contextless" (env: JNI_Env, obj: jobject) -> jobject {
	return jni_fn(env, proc "c" (JNI_Env, jobject) -> jobject, JNI_NEW_GLOBAL_REF)(env, obj)
}

jni_delete_global_ref :: proc "contextless" (env: JNI_Env, obj: jobject) {
	jni_fn(env, proc "c" (JNI_Env, jobject), JNI_DELETE_GLOBAL_REF)(env, obj)
}

jni_delete_local_ref :: proc "contextless" (env: JNI_Env, obj: jobject) {
	jni_fn(env, proc "c" (JNI_Env, jobject), JNI_DELETE_LOCAL_REF)(env, obj)
}

jni_get_object_class :: proc "contextless" (env: JNI_Env, obj: jobject) -> jclass {
	return jni_fn(env, proc "c" (JNI_Env, jobject) -> jclass, JNI_GET_OBJECT_CLASS)(env, obj)
}

jni_method :: proc "contextless" (env: JNI_Env, cls: jclass, name, sig: cstring) -> jmethodID {
	return jni_fn(env, proc "c" (JNI_Env, jclass, cstring, cstring) -> jmethodID, JNI_GET_METHOD_ID)(env, cls, name, sig)
}

jni_static_method :: proc "contextless" (env: JNI_Env, cls: jclass, name, sig: cstring) -> jmethodID {
	return jni_fn(env, proc "c" (JNI_Env, jclass, cstring, cstring) -> jmethodID, JNI_GET_STATIC_METHOD_ID)(env, cls, name, sig)
}

jni_new_object :: proc "contextless" (env: JNI_Env, cls: jclass, ctor_sig: cstring, args: ..jvalue) -> jobject {
	ctor := jni_method(env, cls, "<init>", ctor_sig)
	obj := jni_fn(env, proc "c" (JNI_Env, jclass, jmethodID, [^]jvalue) -> jobject, JNI_NEW_OBJECT_A)(env, cls, ctor, raw_data(args))
	jni_check(env)
	return obj
}

// Looks up the method on the object's runtime class, then calls it.
jni_call_object :: proc "contextless" (env: JNI_Env, obj: jobject, name, sig: cstring, args: ..jvalue) -> jobject {
	cls := jni_get_object_class(env, obj)
	m := jni_method(env, cls, name, sig)
	jni_delete_local_ref(env, cls)
	res := jni_fn(env, proc "c" (JNI_Env, jobject, jmethodID, [^]jvalue) -> jobject, JNI_CALL_OBJECT_METHOD_A)(env, obj, m, raw_data(args))
	jni_check(env)
	return res
}

jni_call_void :: proc "contextless" (env: JNI_Env, obj: jobject, name, sig: cstring, args: ..jvalue) {
	cls := jni_get_object_class(env, obj)
	m := jni_method(env, cls, name, sig)
	jni_delete_local_ref(env, cls)
	jni_fn(env, proc "c" (JNI_Env, jobject, jmethodID, [^]jvalue), JNI_CALL_VOID_METHOD_A)(env, obj, m, raw_data(args))
	jni_check(env)
}

jni_call_float :: proc "contextless" (env: JNI_Env, obj: jobject, name, sig: cstring, args: ..jvalue) -> f32 {
	cls := jni_get_object_class(env, obj)
	m := jni_method(env, cls, name, sig)
	jni_delete_local_ref(env, cls)
	res := jni_fn(env, proc "c" (JNI_Env, jobject, jmethodID, [^]jvalue) -> f32, JNI_CALL_FLOAT_METHOD_A)(env, obj, m, raw_data(args))
	jni_check(env)
	return res
}

jni_call_bool :: proc "contextless" (env: JNI_Env, obj: jobject, name, sig: cstring, args: ..jvalue) -> bool {
	cls := jni_get_object_class(env, obj)
	m := jni_method(env, cls, name, sig)
	jni_delete_local_ref(env, cls)
	res := jni_fn(env, proc "c" (JNI_Env, jobject, jmethodID, [^]jvalue) -> jboolean, JNI_CALL_BOOLEAN_METHOD_A)(env, obj, m, raw_data(args))
	jni_check(env)
	return res != 0
}

jni_call_int :: proc "contextless" (env: JNI_Env, obj: jobject, name, sig: cstring, args: ..jvalue) -> jint {
	cls := jni_get_object_class(env, obj)
	m := jni_method(env, cls, name, sig)
	jni_delete_local_ref(env, cls)
	res := jni_fn(env, proc "c" (JNI_Env, jobject, jmethodID, [^]jvalue) -> jint, JNI_CALL_INT_METHOD_A)(env, obj, m, raw_data(args))
	jni_check(env)
	return res
}

jni_call_static_object :: proc "contextless" (env: JNI_Env, cls_name, name, sig: cstring, args: ..jvalue) -> jobject {
	cls := jni_find_class(env, cls_name)
	m := jni_static_method(env, cls, name, sig)
	res := jni_fn(env, proc "c" (JNI_Env, jclass, jmethodID, [^]jvalue) -> jobject, JNI_CALL_STATIC_OBJECT_A)(env, cls, m, raw_data(args))
	jni_delete_local_ref(env, cls)
	jni_check(env)
	return res
}

// Reads a float instance field, looked up on the object's runtime class.
jni_get_float_field :: proc "contextless" (env: JNI_Env, obj: jobject, name: cstring) -> f32 {
	cls := jni_get_object_class(env, obj)
	id := jni_fn(env, proc "c" (JNI_Env, jclass, cstring, cstring) -> rawptr, JNI_GET_FIELD_ID)(env, cls, name, "F")
	jni_delete_local_ref(env, cls)
	res := jni_fn(env, proc "c" (JNI_Env, jobject, rawptr) -> f32, JNI_GET_FLOAT_FIELD)(env, obj, id)
	jni_check(env)
	return res
}

// Reads an int instance field, looked up on the object's runtime class.
jni_get_int_field :: proc "contextless" (env: JNI_Env, obj: jobject, name: cstring) -> jint {
	cls := jni_get_object_class(env, obj)
	id := jni_fn(env, proc "c" (JNI_Env, jclass, cstring, cstring) -> rawptr, JNI_GET_FIELD_ID)(env, cls, name, "I")
	jni_delete_local_ref(env, cls)
	res := jni_fn(env, proc "c" (JNI_Env, jobject, rawptr) -> jint, JNI_GET_INT_FIELD)(env, obj, id)
	jni_check(env)
	return res
}

// Reads a static int field such as a resource id; 0 when the class or field is missing.
jni_get_static_int_field :: proc "contextless" (env: JNI_Env, cls_name, name: cstring) -> jint {
	cls := jni_find_class(env, cls_name)
	if cls == nil {
		jni_check(env)
		return 0
	}
	defer jni_delete_local_ref(env, cls)
	id := jni_fn(env, proc "c" (JNI_Env, jclass, cstring, cstring) -> rawptr, JNI_GET_STATIC_FIELD_ID)(env, cls, name, "I")
	if id == nil {
		jni_check(env)
		return 0
	}
	res := jni_fn(env, proc "c" (JNI_Env, jclass, rawptr) -> jint, JNI_GET_STATIC_INT_FIELD)(env, cls, id)
	jni_check(env)
	return res
}

jni_string :: proc "contextless" (env: JNI_Env, s: cstring) -> jstring {
	return jni_fn(env, proc "c" (JNI_Env, cstring) -> jstring, JNI_NEW_STRING_UTF)(env, s)
}

// Copies a Java string (as modified UTF-8, which only differs from UTF-8 for NUL and
// characters outside the BMP).
jni_string_clone :: proc(env: JNI_Env, s: jstring, allocator := context.allocator) -> string {
	n := jni_fn(env, proc "c" (JNI_Env, jstring) -> jint, JNI_GET_STRING_UTF_LENGTH)(env, s)
	chars := jni_fn(env, proc "c" (JNI_Env, jstring, ^jboolean) -> [^]u8, JNI_GET_STRING_UTF_CHARS)(env, s, nil)
	defer jni_fn(env, proc "c" (JNI_Env, jstring, [^]u8), JNI_RELEASE_STRING_UTF_CHARS)(env, s, chars)
	out := make([]u8, n, allocator)
	copy(out, chars[:n])
	return string(out)
}

// Logs and clears a pending Java exception so later JNI calls stay valid.
jni_check :: proc "contextless" (env: JNI_Env) {
	if jni_fn(env, proc "c" (JNI_Env) -> jboolean, JNI_EXCEPTION_CHECK)(env) != 0 {
		jni_fn(env, proc "c" (JNI_Env), JNI_EXCEPTION_DESCRIBE)(env)
		jni_fn(env, proc "c" (JNI_Env), JNI_EXCEPTION_CLEAR)(env)
	}
}

jv_obj  :: #force_inline proc "contextless" (o: jobject) -> jvalue { return {l = o} }
jv_int  :: #force_inline proc "contextless" (i: int) -> jvalue { return {i = jint(i)} }
jv_long :: #force_inline proc "contextless" (i: i64) -> jvalue { return {j = jlong(i)} }
jv_float :: #force_inline proc "contextless" (f: f32) -> jvalue { return {f = f} }
jv_bool :: #force_inline proc "contextless" (b: bool) -> jvalue { return {z = jboolean(b)} }
