#+build windows
#+private
package nv

// Windows Layout backend: an "NVLayout" window that reports its client size on WM_SIZE, then sizes
// its child to it. What the app changes in on_layout relays out the windows around it inside the
// call, which can re-enter with another size (layout_notify runs that one after).

import win "core:sys/windows"

@(private)
_layout_init :: proc(h: ^Layout_Handle) {
	wnd := win.CreateWindowExW(0, wstr(CLASS_LAYOUT), nil, win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)
	win.SetParent(win.HWND(h.layout.child), wnd)
	h.root = View(wnd)
}

@(private)
layout_handle_of :: proc "contextless" (hwnd: win.HWND) -> ^Layout_Handle {
	return (^Layout_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
}

// The child's natural size: a Layout has none of its own.
@(private)
layout_measure :: proc(hwnd: win.HWND) -> [2]i32 {
	h := layout_handle_of(hwnd)
	if h == nil do return {}
	return measure(win.HWND(h.layout.child))
}

@(private)
layout_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := layout_handle_of(hwnd)
	if h == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx

	switch msg {
	case win.WM_SIZE:
		callback_enter()
		defer callback_exit()
		rc: win.RECT
		win.GetClientRect(hwnd, &rc)
		layout_notify(h, dp(rc.right), dp(rc.bottom))
		win.GetClientRect(hwnd, &rc) // the answer may have resized this window
		win.MoveWindow(win.HWND(h.layout.child), 0, 0, rc.right, rc.bottom, true)
		return 0
	case win.WM_CTLCOLORSTATIC:
		return ctlcolor_static(wparam, lparam)
	case win.WM_CTLCOLORBTN:
		return ctlcolor_button(lparam)
	case win.WM_ERASEBKGND:
		return erase_background(hwnd, win.HDC(wparam))
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
