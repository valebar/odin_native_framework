#+build windows
package nv

// Windows (Win32) app backend. The main window is created hidden before `build` runs, so the
// controls `build` creates have a parent (see win32.odin), then shown once the tree exists.
// The root view fills the client area; the app quits when the window closes.

import win "core:sys/windows"

@(private)
_run :: proc(title: string, build: Build_Proc, user: rawptr) {
	g_windows.ctx = context
	g_windows.hinstance = win.HINSTANCE(win.GetModuleHandleW(nil))
	win.SetProcessDpiAwarenessContext(win.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) // also in the manifest
	icc := win.INITCOMMONCONTROLSEX{size_of(win.INITCOMMONCONTROLSEX), win.ICC_LISTVIEW_CLASSES | win.ICC_STANDARD_CLASSES}
	win.InitCommonControlsEx(&icc)
	register_classes()

	style := win.WS_OVERLAPPEDWINDOW | win.WS_CLIPCHILDREN
	wnd := win.CreateWindowExW(0, wstr(CLASS_WINDOW), wstr(title), style,
		win.CW_USEDEFAULT, win.CW_USEDEFAULT, win.CW_USEDEFAULT, win.CW_USEDEFAULT,
		nil, nil, g_windows.hinstance, nil)
	g_windows.parking = wnd
	g_windows.dpi = win.GetDpiForWindow(wnd)
	create_fonts()

	// 400×600 client area at the window's DPI.
	rc := win.RECT{0, 0, px(400), px(600)}
	win.AdjustWindowRectExForDpi(&rc, style, false, 0, g_windows.dpi)
	win.SetWindowPos(wnd, nil, 0, 0, rc.right - rc.left, rc.bottom - rc.top, win.SWP_NOMOVE | win.SWP_NOZORDER | win.SWP_NOACTIVATE)

	callback_enter()
	g_windows.root = win.HWND(build(user)) // already a child of `wnd`
	callback_exit()
	layout_root(wnd)
	win.ShowWindow(wnd, win.SW_SHOW)

	msg: win.MSG
	for win.GetMessageW(&msg, nil, 0, 0) > 0 {
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}
}

@(private)
layout_root :: proc "contextless" (wnd: win.HWND) {
	if g_windows.root == nil do return
	rc: win.RECT
	win.GetClientRect(wnd, &rc)
	win.MoveWindow(g_windows.root, 0, 0, rc.right, rc.bottom, true)
}

@(private)
window_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = g_windows.ctx
	switch msg {
	case win.WM_SIZE:
		layout_root(hwnd)
		return 0
	case win.WM_CTLCOLORSTATIC:
		return ctlcolor_static(wparam)
	case win.WM_DPICHANGED:
		// Fonts and row heights keep the DPI they were created with; only the window follows.
		r := (^win.RECT)(uintptr(lparam))
		win.SetWindowPos(hwnd, nil, r.left, r.top, r.right - r.left, r.bottom - r.top, win.SWP_NOZORDER | win.SWP_NOACTIVATE)
		return 0
	case win.WM_DESTROY:
		win.PostQuitMessage(0)
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
