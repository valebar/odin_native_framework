#+build linux:android
#+private
package nv

// Android file dialogs: nv.NvFiles starts the system document picker (ACTION_OPEN_DOCUMENT /
// ACTION_CREATE_DOCUMENT) and answers through nativeOnDone on the UI thread, once the file was read
// or written on a thread of its own.

import "core:strings"

@(private)
_file_open :: proc(r: ^File_Request) {
	nv_files_open(g_android.env, g_android.activity, i64(uintptr(r)), strings.join(r.extensions, ",", context.temp_allocator))
}

@(private)
_file_save :: proc(r: ^File_Request) {
	name := r.name != "" ? r.name : "file"
	ext := len(r.extensions) > 0 ? r.extensions[0] : ""
	nv_files_save(g_android.env, g_android.activity, i64(uintptr(r)), name, ext, r.data)
}

@(export, link_name="Java_nv_NvFiles_nativeOnDone")
jni_files_on_done :: proc "c" (env: JNI_Env, _: jclass, req: jlong, status: jint, name: jobject, data: jobject) {
	r := (^File_Request)(uintptr(req))
	context = r.ctx
	g_android.env = env
	s := File_Status(status)
	if s == .Ok {
		n := name != nil ? jni_string_clone(env, name, context.temp_allocator) : ""
		file_set_result(r, n, r.save ? nil : jni_bytes_clone(env, data, nv_heap()))
	}
	file_notify(r, s)
}

// No folder dialog here: .Failed, after the call.
@(private)
_folder_open :: proc(r: ^File_Request) {
	post_main(proc(data: rawptr) { file_notify((^File_Request)(data), .Failed) }, r)
}
