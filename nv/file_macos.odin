#+build darwin:default
#+private
package nv

// macOS file dialogs: NSOpenPanel / NSSavePanel as sheets on the window (no nested run loop), each
// with a global block whose user data is the request. The panel (retained) is in r.native, the
// block in r.extra; both go once the completion handler returned.

import "core:os"
import NS "core:sys/darwin/Foundation"

@(private)
_file_open :: proc(r: ^File_Request) {
	panel := send(^NS.Object, objc_class_object("NSOpenPanel"), "openPanel")
	send(nil, panel, "setCanChooseFiles:", NS.BOOL(true))
	send(nil, panel, "setCanChooseDirectories:", NS.BOOL(false))
	send(nil, panel, "setAllowsMultipleSelection:", NS.BOOL(false))
	file_begin_sheet(r, panel)
}

@(private)
_file_save :: proc(r: ^File_Request) {
	panel := send(^NS.Object, objc_class_object("NSSavePanel"), "savePanel")
	if r.name != "" do send(nil, panel, "setNameFieldStringValue:", ns_string(r.name))
	file_begin_sheet(r, panel)
}

@(private)
file_begin_sheet :: proc(r: ^File_Request, panel: ^NS.Object) {
	send(nil, panel, "retain")
	if r.title != "" do send(nil, panel, "setMessage:", ns_string(r.title))
	if len(r.extensions) > 0 {
		types := make([]^NS.Object, len(r.extensions), context.temp_allocator)
		for e, i in r.extensions do types[i] = ns_string(e)
		send(nil, panel, "setAllowedFileTypes:", array_with_objects(raw_data(types), len(types))) // by extension, no UTType needed
	}
	block := NS.Block_createGlobalWithParam(r, file_sheet_done, nv_heap())
	r.native, r.extra = panel, block
	send(nil, panel, "beginSheetModalForWindow:completionHandler:", g_macos.window, block)
}

// NSModalResponseOK is 1.
@(private)
file_sheet_done :: proc "c" (user: rawptr, response: NS.Integer) {
	r := (^File_Request)(user)
	context = r.ctx
	panel := (^NS.Object)(r.native)
	status := File_Status.Cancelled
	if response == 1 {
		url := send(^NS.Object, panel, "URL")
		path := string(send(cstring, send(^NS.Object, url, "path"), "UTF8String"))
		status = .Failed
		if r.save {
			if os.write_entire_file(path, r.data) == nil {
				file_set_result(r, path)
				status = .Ok
			}
		} else if data, err := os.read_entire_file(path, nv_heap()); err == nil {
			file_set_result(r, path, data)
			status = .Ok
		}
	}
	send(nil, panel, "autorelease")
	post_main(proc(block: rawptr) { free(block, nv_heap()) }, r.extra) // AppKit is still inside the block
	file_notify(r, status)
}
