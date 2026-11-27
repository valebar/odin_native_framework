#+build linux:default
#+private
package nv

// Linux file dialogs: GtkFileChooserNative (every GTK 4.x; the desktop portal under a sandbox),
// modal to the window, with a filter by suffix. The file is read or written once the user
// answered; the dialog is unreferenced from an idle, outside its own "response" emission.

import "core:os"
import "core:strings"

@(private) GTK_FILE_CHOOSER_ACTION_OPEN :: i32(0)
@(private) GTK_FILE_CHOOSER_ACTION_SAVE :: i32(1)
@(private) GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER :: i32(2)
@(private) GTK_RESPONSE_ACCEPT          :: i32(-3)

@(private)
_file_open :: proc(r: ^File_Request) {
	file_chooser_show(r, GTK_FILE_CHOOSER_ACTION_OPEN)
}

@(private)
_file_save :: proc(r: ^File_Request) {
	file_chooser_show(r, GTK_FILE_CHOOSER_ACTION_SAVE)
}

@(private)
_folder_open :: proc(r: ^File_Request) {
	file_chooser_show(r, GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER)
}

@(private)
file_chooser_show :: proc(r: ^File_Request, action: i32) {
	title := strings.clone_to_cstring(r.title, context.temp_allocator)
	dialog := gtk_file_chooser_native_new(title, g_linux.window, action, nil, nil)
	if len(r.extensions) > 0 {
		filter := gtk_file_filter_new()
		gtk_file_filter_set_name(filter, strings.clone_to_cstring(strings.join(r.extensions, ", ", context.temp_allocator), context.temp_allocator))
		for e in r.extensions do gtk_file_filter_add_suffix(filter, strings.clone_to_cstring(e, context.temp_allocator))
		gtk_file_chooser_add_filter(dialog, filter) // takes it
	}
	if r.save && r.name != "" do gtk_file_chooser_set_current_name(dialog, strings.clone_to_cstring(r.name, context.temp_allocator))
	gtk_native_dialog_set_modal(dialog, true)
	g_signal_connect(dialog, "response", rawptr(file_chooser_response), r)
	r.native = dialog
	gtk_native_dialog_show(dialog)
}

@(private)
file_chooser_response :: proc "c" (dialog: rawptr, response: i32, user: gpointer) {
	r := (^File_Request)(user)
	context = r.ctx
	status := File_Status.Cancelled
	if response == GTK_RESPONSE_ACCEPT {
		status = .Failed
		if file := gtk_file_chooser_get_file(dialog); file != nil {
			if p := g_file_get_path(file); p != nil {
				path := string(p)
				if r.folder {
					file_set_result(r, path)
					status = .Ok
				} else if r.save {
					if os.write_entire_file(path, r.data) == nil {
						file_set_result(r, path)
						status = .Ok
					}
				} else if data, err := os.read_entire_file(path, nv_heap()); err == nil {
					file_set_result(r, path, data)
					status = .Ok
				}
				g_free(rawptr(p))
			}
			g_object_unref(file)
		}
	}
	g_idle_add(unref_widget_idle, dialog)
	file_notify(r, status)
}
