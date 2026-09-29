#+build windows
package nv

// Windows button backend: a "Button" push button inside an "NVButton" container window, which
// gets its BN_CLICKED. Like the list and the input, the control keeps a parent that Row / Column
// never re-parents, so its notifications always reach the handle.

import win "core:sys/windows"

@(private)
_button_init :: proc(h: ^Button_Handle) {
	container := win.CreateWindowExW(0, wstr(CLASS_BUTTON), nil, win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)

	button := win.CreateWindowExW(0, wstr("Button"), wstr(h.button.title),
		win.WS_CHILD | win.WS_VISIBLE | win.WS_TABSTOP | win.BS_PUSHBUTTON,
		0, 0, 0, 0, container, nil, g_windows.hinstance, nil)
	win.SendMessageW(button, win.WM_SETFONT, win.WPARAM(uintptr(style_font(h.button.style, g_windows.font))), 0)
	theme_control(button)

	h.root = View(container)
	h.control = rawptr(button)
}

@(private)
_button_set_title :: proc(h: ^Button_Handle, title: string) {
	before := measure(win.HWND(h.root))
	win.SetWindowTextW(win.HWND(h.control), wstr(title))
	if measure(win.HWND(h.root)) != before do flex_relayout_ancestors(win.HWND(h.root)) // the natural width follows the title
}

// Natural size in px: the themed ideal size plus some horizontal padding, at least the 75px of a
// dialog button, and the 23px dialog button height at 96 DPI (for the message font; another
// font gets its line height plus the same padding).
@(private)
button_measure :: proc "contextless" (container: win.HWND) -> [2]i32 {
	h := (^Button_Handle)(uintptr(win.GetWindowLongPtrW(container, win.GWLP_USERDATA)))
	return button_ideal_size(win.HWND(h.control))
}

// The same for a bare push button (the navigation bar's).
@(private)
button_ideal_size :: proc "contextless" (button: win.HWND) -> [2]i32 {
	ideal: win.SIZE
	win.Button_GetIdealSize(button, &ideal)
	return {max(ideal.cx + px(16), px(75)), font_height(control_font(button)) + px(8)}
}

@(private)
button_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := (^Button_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
	if h == nil || h.control == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx

	switch msg {
	case win.WM_SIZE:
		rc: win.RECT
		win.GetClientRect(hwnd, &rc)
		win.MoveWindow(win.HWND(h.control), 0, 0, rc.right, rc.bottom, true)
		return 0
	case win.WM_CTLCOLORBTN:
		return ctlcolor_button(lparam)
	case win.WM_ERASEBKGND: // the themed button asks its parent to paint its rounded corners
		return erase_background(hwnd, win.HDC(wparam))
	case win.WM_COMMAND:
		if win.HWND(uintptr(lparam)) == win.HWND(h.control) && win.HIWORD(u32(wparam)) == win.BN_CLICKED {
			button_notify(h)
			return 0
		}
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
