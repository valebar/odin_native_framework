#+build darwin:ios
#+private
package nv

// iOS file dialogs: UIDocumentPickerViewController presented over the top controller. An open picks
// a copy (asCopy: no security-scoped access), read and then deleted; a save writes the data to a
// temporary file and exports a copy of it. NVDocumentPickerDelegate (+1 in r.native, since the
// picker holds its delegate weakly) reports the answer; the request is its handle.

import "core:os"
import "core:strings"
import NS "core:sys/darwin/Foundation"

@(require) foreign import uti "system:UniformTypeIdentifiers.framework"

@(private) file_delegate_class: NS.Class

@(private)
_file_open :: proc(r: ^File_Request) {
	types := make([]^NS.Object, max(len(r.extensions), 1), context.temp_allocator)
	n := 0
	for e in r.extensions {
		if t := send(^NS.Object, objc_class_object("UTType"), "typeWithFilenameExtension:", ns_string(e)); t != nil {
			types[n] = t
			n += 1
		}
	}
	if n == 0 {
		types[0] = send(^NS.Object, objc_class_object("UTType"), "typeWithIdentifier:", ns_string("public.item"))
		n = 1
	}
	alloc := send(^NS.Object, objc_class_object("UIDocumentPickerViewController"), "alloc")
	picker := send(^NS.Object, alloc, "initForOpeningContentTypes:asCopy:", array_with_objects(raw_data(types), n), NS.BOOL(true))
	file_picker_present(r, picker)
}

@(private)
_file_save :: proc(r: ^File_Request) {
	name := r.name != "" ? r.name : "file"
	path := strings.concatenate({file_temp_dir(), "/", name}, nv_heap())
	if os.write_entire_file(path, r.data) != nil {
		delete(path, nv_heap())
		post_main(proc(r: rawptr) { file_notify((^File_Request)(r), .Failed) }, r)
		return
	}
	r.extra = new_clone(path, nv_heap())
	url := send(^NS.Object, objc_class_object("NSURL"), "fileURLWithPath:", ns_string(path))
	alloc := send(^NS.Object, objc_class_object("UIDocumentPickerViewController"), "alloc")
	picker := send(^NS.Object, alloc, "initForExportingURLs:asCopy:", array_with_objects(([^]^NS.Object)(&url), 1), NS.BOOL(true))
	file_picker_present(r, picker)
}

@(private)
file_temp_dir :: proc() -> string {
	s := string(send(cstring, NS.TemporaryDirectory(), "UTF8String"))
	return strings.trim_right(s, "/")
}

@(private)
file_picker_present :: proc(r: ^File_Request, picker: ^NS.Object) {
	cls := objc_class(&file_delegate_class, "NVDocumentPickerDelegate", "NSObject", {
		{"documentPicker:didPickDocumentsAtURLs:", auto_cast file_picker_did_pick, "v@:@@"},
		{"documentPickerWasCancelled:", auto_cast file_picker_cancelled, "v@:@"},
	}, {"UIDocumentPickerDelegate"})
	delegate := objc_alloc_with_handle(cls, r)
	r.native = rawptr(delegate)
	send(nil, picker, "setDelegate:", delegate)
	top := (^NS.Object)(g_app.nav)
	for {
		next := send(^NS.Object, top, "presentedViewController")
		if next == nil do break
		top = next
	}
	send(nil, top, "presentViewController:animated:completion:", picker, NS.BOOL(true), rawptr(nil))
	send(nil, picker, "release")
}

@(private)
file_picker_did_pick :: proc "c" (self: NS.id, _: NS.SEL, picker: NS.id, urls: ^NS.Array) {
	r := objc_handle(self, File_Request)
	context = r.ctx
	status := File_Status.Failed
	if send(NS.UInteger, urls, "count") > 0 {
		url := send(^NS.Object, urls, "objectAtIndex:", NS.UInteger(0))
		path := string(send(cstring, send(^NS.Object, url, "path"), "UTF8String"))
		if r.save {
			file_set_result(r, path)
			status = .Ok
		} else {
			if data, err := os.read_entire_file(path, nv_heap()); err == nil {
				file_set_result(r, path, data)
				status = .Ok
			}
			_ = os.remove(path) // the copy picked for this app
		}
	}
	file_picker_done(r, status)
}

@(private)
file_picker_cancelled :: proc "c" (self: NS.id, _: NS.SEL, picker: NS.id) {
	r := objc_handle(self, File_Request)
	context = r.ctx
	file_picker_done(r, .Cancelled)
}

@(private)
file_picker_done :: proc(r: ^File_Request, status: File_Status) {
	if tmp := (^string)(r.extra); tmp != nil {
		_ = os.remove(tmp^)
		delete(tmp^, nv_heap())
		free(tmp, nv_heap())
		r.extra = nil
	}
	send(nil, (^NS.Object)(r.native), "autorelease") // UIKit is still inside its call
	file_notify(r, status)
}

// No folder dialog here: .Failed, after the call.
@(private)
_folder_open :: proc(r: ^File_Request) {
	post_main(proc(data: rawptr) { file_notify((^File_Request)(data), .Failed) }, r)
}
