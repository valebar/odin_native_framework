#+build windows
package nv

// Windows input backend: a single-line "Edit" control inside an "NVInput" container window.
// Edit caches its parent at creation and sends EN_CHANGE there, so like the list it needs a
// parent that Row / Column never re-parents. Enter produces no notification in a single-line
// Edit, so the control is subclassed to catch it (and to swallow the beep).

import win "core:sys/windows"

@(private)
_input_init :: proc(h: ^Input_Handle) {
	container := win.CreateWindowExW(0, wstr(CLASS_INPUT), nil, win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)

	edit := win.CreateWindowExW(win.WS_EX_CLIENTEDGE, wstr("Edit"), wstr(h.input.text),
		win.WS_CHILD | win.WS_VISIBLE | win.WS_TABSTOP | win.ES_AUTOHSCROLL,
		0, 0, 0, 0, container, nil, g_windows.hinstance, nil)
	win.SendMessageW(edit, win.WM_SETFONT, win.WPARAM(uintptr(g_windows.font)), 0)
	if h.input.placeholder != "" do win.Edit_SetCueBannerText(edit, wstr(h.input.placeholder))
	win.SetWindowSubclass(edit, edit_subclass_proc, 0, win.DWORD_PTR(uintptr(h)))

	h.root = View(container)
	h.field = rawptr(edit)
}

@(private)
_input_text :: proc(h: ^Input_Handle, allocator := context.allocator) -> string {
	edit := win.HWND(h.field)
	buf := make([]u16, win.GetWindowTextLengthW(edit) + 1, context.temp_allocator)
	n := win.GetWindowTextW(edit, raw_data(buf), i32(len(buf)))
	text, _ := win.utf16_to_utf8(buf[:n], allocator)
	return text
}

@(private)
_input_set_text :: proc(h: ^Input_Handle, text: string) {
	win.SetWindowTextW(win.HWND(h.field), wstr(text)) // sends EN_CHANGE, muted by h.silent
}

// Natural size in px: one line of the message font plus the client edge and a little padding,
// the height of a dialog edit box. The width is just a sensible default for a flex-0 input.
@(private)
input_measure :: proc "contextless" () -> [2]i32 {
	return {px(200), g_windows.font_h + px(7)}
}

@(private)
input_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := (^Input_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
	if h == nil || h.field == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx

	switch msg {
	case win.WM_SIZE:
		rc: win.RECT
		win.GetClientRect(hwnd, &rc)
		win.MoveWindow(win.HWND(h.field), 0, 0, rc.right, rc.bottom, true)
		return 0
	case win.WM_COMMAND:
		if win.HWND(uintptr(lparam)) == win.HWND(h.field) && win.HIWORD(u32(wparam)) == win.EN_CHANGE {
			input_notify(h, h.input.on_change)
			return 0
		}
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@(private)
edit_subclass_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM, _: win.UINT_PTR, ref: win.DWORD_PTR) -> win.LRESULT {
	if msg == win.WM_CHAR && wparam == win.VK_RETURN {
		h := (^Input_Handle)(uintptr(ref))
		context = h.ctx
		input_notify(h, h.input.on_submit)
		return 0 // the Edit would beep
	}
	return win.DefSubclassProc(hwnd, msg, wparam, lparam)
}
