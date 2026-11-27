#+build js
#+private
package nv

// Web file dialogs (nv.js): a hidden file input reads the chosen file, a Blob download saves one.
// Both answer through nv_web_file.

import "core:strings"

@(private)
_file_open :: proc(r: ^File_Request) {
	accept := make([]string, len(r.extensions), context.temp_allocator)
	for e, i in r.extensions do accept[i] = strings.concatenate({".", e}, context.temp_allocator)
	js_file_open(r, strings.join(accept, ",", context.temp_allocator))
}

@(private)
_file_save :: proc(r: ^File_Request) {
	name := r.name
	if name == "" do name = len(r.extensions) > 0 ? strings.concatenate({"file.", r.extensions[0]}, context.temp_allocator) : "file"
	js_file_save(r, name, r.data)
}
