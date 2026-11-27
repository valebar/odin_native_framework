#+build windows
#+private
package nv

// Windows input backend: a single-line "Edit" control inside an "NVInput" container window.
// Edit caches its parent at creation and sends EN_CHANGE there, so like the list it needs a
// parent that Row / Column never re-parents. Enter produces no notification in a single-line
// Edit, so the control is subclassed to catch it (and to swallow the beep). `secure` is
// ES_PASSWORD (comctl32 v6 masks with a bullet), Keyboard.Number ES_NUMBER (digits only); the other
// keyboards have no desktop meaning.

import win "core:sys/windows"

@(private)
_input_init :: proc(h: ^Input_Handle) {
	container := win.CreateWindowExW(0, wstr(CLASS_INPUT), nil, win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)

	style := win.WS_CHILD | win.WS_VISIBLE | win.WS_TABSTOP | win.ES_AUTOHSCROLL
	if h.input.secure do style |= win.ES_PASSWORD
	if h.input.keyboard == .Number do style |= win.ES_NUMBER
	edit := win.CreateWindowExW(win.WS_EX_CLIENTEDGE, wstr("Edit"), wstr(h.input.text), style,
		0, 0, 0, 0, container, nil, g_windows.hinstance, nil)
	win.SendMessageW(edit, win.WM_SETFONT, win.WPARAM(uintptr(style_font(h.input.style, g_windows.font))), 0)
	theme_control(edit)
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

// Natural size in px: one line of its font plus the client edge and a little padding, the height
// of a dialog edit box. The width is just a sensible default for a flex-0 input.
@(private)
input_measure :: proc "contextless" (container: win.HWND) -> [2]i32 {
	h := (^Input_Handle)(uintptr(win.GetWindowLongPtrW(container, win.GWLP_USERDATA)))
	return {px(200), font_height(control_font(win.HWND(h.field))) + px(7)}
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
	case win.WM_CTLCOLOREDIT: // the text on the palette's surface; on white in a light dialog
		light := in_light_dialog(hwnd)
		p := light ? PALETTE_LIGHT : theme_palette()
		dc := win.HDC(wparam)
		win.SetTextColor(dc, colorref(h.input.style.color.a > 0 ? h.input.style.color : p.text))
		win.SetBkColor(dc, colorref(light ? DIALOG_LIGHT : p.surface))
		return win.LRESULT(uintptr(light ? g_theme_windows.light : g_theme_windows.surface))
	case win.WM_COMMAND:
		if win.HWND(uintptr(lparam)) == win.HWND(h.field) && win.HIWORD(u32(wparam)) == win.EN_CHANGE {
			input_notify(h, h.input.on_change)
			return 0
		}
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@(private)
edit_subclass_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM, id: win.UINT_PTR, ref: win.DWORD_PTR) -> win.LRESULT {
	switch msg {
	case win.WM_CHAR:
		if wparam == win.VK_RETURN {
			h := (^Input_Handle)(uintptr(ref))
			context = h.ctx
			input_notify(h, h.input.on_submit)
			return 0 // the Edit would beep
		}
	case win.WM_NCDESTROY: // a popped page destroys its inputs; the subclass must go first
		RemoveWindowSubclass(hwnd, edit_subclass_proc, id)
	}
	return win.DefSubclassProc(hwnd, msg, wparam, lparam)
}

// The caret goes to the end unless everything is selected.
@(private)
_input_focus :: proc(h: ^Input_Handle, select_all: bool) {
	edit := win.HWND(h.field)
	win.SetFocus(edit)
	if select_all {
		win.SendMessageW(edit, win.EM_SETSEL, 0, -1)
	} else {
		n := win.GetWindowTextLengthW(edit)
		win.SendMessageW(edit, win.EM_SETSEL, win.WPARAM(n), win.LPARAM(n))
	}
}
