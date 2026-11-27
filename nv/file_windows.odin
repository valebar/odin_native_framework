#+build windows
#+private
package nv

// Windows file dialogs: GetOpenFileNameW / GetSaveFileNameW (the Explorer-style dialog with the
// Common Controls v6 manifest), run from a posted timer so file_open returns first. Their modal
// loop dispatches timers and post_main inside the callback bracket, as nv already allows.

import "core:os"
import "core:strings"
import win "core:sys/windows"

@(private)
_file_open :: proc(r: ^File_Request) {
	post_main(file_dialog_run, r)
}

@(private)
_file_save :: proc(r: ^File_Request) {
	post_main(file_dialog_run, r)
}

// The Vista folder picker (IFileOpenDialog with FOS_PICKFOLDERS): GetOpenFileNameW picks files
// only. Run from a posted timer too, owned by the window.
@(private)
_folder_open :: proc(r: ^File_Request) {
	post_main(folder_dialog_run, r)
}

@(private)
folder_dialog_run :: proc(user: rawptr) {
	r := (^File_Request)(user)
	status := File_Status.Failed
	win.CoInitializeEx(nil, .APARTMENTTHREADED) // S_FALSE when the thread already has it
	dialog: ^win.IFileOpenDialog
	if win.CoCreateInstance(win.CLSID_FileOpenDialog, nil, win.CLSCTX_INPROC_SERVER, win.IID_IFileOpenDialog, (^win.LPVOID)(&dialog)) >= 0 {
		options: win.FILEOPENDIALOGOPTIONS
		dialog->GetOptions(&options)
		dialog->SetOptions(options | win.FOS_PICKFOLDERS | win.FOS_FORCEFILESYSTEM)
		if r.title != "" do dialog->SetTitle(wstr(r.title))
		hr := dialog->Show(g_windows.parking)
		if hr >= 0 {
			item: ^win.IShellItem
			if dialog->GetResult(&item) >= 0 {
				path: win.LPWSTR
				if item->GetDisplayName(.FILESYSPATH, &path) >= 0 {
					chosen, _ := win.wstring_to_utf8(win.wstring(path), -1, context.temp_allocator)
					file_set_result(r, chosen)
					status = .Ok
					win.CoTaskMemFree(path)
				}
				item->Release()
			}
		} else if u32(hr) == 0x800704C7 { // HRESULT_FROM_WIN32(ERROR_CANCELLED)
			status = .Cancelled
		}
		dialog->Release()
	}
	file_notify(r, status)
}

@(private)
file_dialog_run :: proc(user: rawptr) {
	r := (^File_Request)(user)
	// "JSON (*.json)\0*.json\0All files\0*.*\0\0"
	b := strings.builder_make(context.temp_allocator)
	if len(r.extensions) > 0 {
		patterns := make([]string, len(r.extensions), context.temp_allocator)
		for e, i in r.extensions do patterns[i] = strings.concatenate({"*.", e}, context.temp_allocator)
		joined := strings.join(patterns, ";", context.temp_allocator)
		strings.write_string(&b, strings.to_upper(r.extensions[0], context.temp_allocator))
		strings.write_string(&b, " (")
		strings.write_string(&b, joined)
		strings.write_string(&b, ")\x00")
		strings.write_string(&b, joined)
		strings.write_byte(&b, 0)
	}
	strings.write_string(&b, "All files\x00*.*\x00\x00")
	filter := win.utf8_to_utf16(strings.to_string(b), context.temp_allocator)

	path: [win.MAX_PATH * 4]u16
	if r.save && r.name != "" {
		name := win.utf8_to_utf16(r.name, context.temp_allocator)
		copy(path[:len(path) - 1], name)
	}
	ofn := win.OPENFILENAMEW{
		lStructSize  = size_of(win.OPENFILENAMEW),
		hwndOwner    = g_windows.parking,
		lpstrFilter  = cstring16(raw_data(filter)),
		nFilterIndex = 1,
		lpstrFile    = &path[0],
		nMaxFile     = len(path),
		Flags        = win.OFN_EXPLORER | win.OFN_NOCHANGEDIR | (r.save ? win.OFN_OVERWRITEPROMPT : win.OFN_FILEMUSTEXIST | win.OFN_PATHMUSTEXIST),
	}
	if r.title != "" do ofn.lpstrTitle = wstr(r.title)
	if r.save && len(r.extensions) > 0 do ofn.lpstrDefExt = wstr(r.extensions[0])

	status := File_Status.Cancelled
	if (r.save ? win.GetSaveFileNameW(&ofn) : win.GetOpenFileNameW(&ofn)) {
		n := 0
		for path[n] != 0 do n += 1
		chosen, _ := win.utf16_to_utf8(path[:n], context.temp_allocator)
		status = .Failed
		if r.save {
			if os.write_entire_file(chosen, r.data) == nil {
				file_set_result(r, chosen)
				status = .Ok
			}
		} else if data, err := os.read_entire_file(chosen, nv_heap()); err == nil {
			file_set_result(r, chosen, data)
			status = .Ok
		}
	}
	file_notify(r, status)
}
