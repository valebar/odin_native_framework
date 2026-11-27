#+build windows
#+private
package nv

// Windows dialog backend: the card is an "NVDialog" child of the NVNav host (so it can cover the
// bar too), cut to a rounded rectangle with a window region and painted with a thin border; it
// holds the body and sizes it to its measure plus padding. A modal dialog first creates an
// "NVScrim": a black, layered child window at 40% alpha (layered children work since Windows 8).
// Any window swallows the mouse for what it covers (the scrim reports a click for a dismissible
// dialog; the card is a sibling above it); the keyboard is blocked by disabling the
// page root and the bar's controls while a modal dialog is visible. Dialog.scrim sets the scrim's
// fill (WM_ERASEBKGND) and alpha; a light card paints white and its controls keep the light
// styles and colours (in_light_dialog, win32.odin). nav_layout places the
// dialogs of the top page on every WM_SIZE and keeps them at the top of the z-order, since a
// new child or a re-parented page lands above its siblings. A closed dialog's windows are hidden
// at once and destroyed through WM_NV_DESTROY, like a popped page: the close often runs inside
// one of the card's own buttons' BN_CLICKED.

import win "core:sys/windows"

@(private) DIALOG_PAD    :: 16.0
@(private) DIALOG_RADIUS :: 12.0
@(private) SCRIM_ALPHA   :: 0x66 // the scaffold's; a dialog's comes from dialog_scrim

@(private)
_dialog_show :: proc(h: ^Dialog_Handle) {
	host := g_windows.root
	if h.dialog.modal {
		scrim := win.CreateWindowExW(win.WS_EX_LAYERED, wstr(CLASS_SCRIM), nil,
			win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPSIBLINGS, 0, 0, 0, 0, host, nil, g_windows.hinstance, nil)
		alpha := win.BYTE(clamp(dialog_scrim(h).a, 0, 1) * 255 + 0.5)
		win.SetLayeredWindowAttributes(scrim, 0, alpha, win.LWA_ALPHA)
		h.scrim = rawptr(scrim)
	}
	card := win.CreateWindowExW(0, wstr(CLASS_DIALOG), nil,
		win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN | win.WS_CLIPSIBLINGS, 0, 0, 0, 0, host, nil, g_windows.hinstance, h)
	win.SetParent(win.HWND(h.body), card)
	h.card = rawptr(card)
	if h.dialog.light { // the body's controls were themed for the page; now they are in the card
		win.EnumChildWindows(card, proc "system" (hwnd: win.HWND, _: win.LPARAM) -> win.BOOL {
			context = g_windows.ctx
			theme_control(hwnd)
			return true
		}, 0)
	}

	dialog_apply_modal()
	if h.dialog.modal && len(h.buttons) > 0 do win.SetFocus(win.HWND(h.buttons[0].handle.control))
	nav_layout(host)
}

@(private)
_dialog_close :: proc(h: ^Dialog_Handle) {
	card := win.HWND(h.card)
	if win.IsChild(card, win.GetFocus()) do win.SetFocus(g_windows.parking) // the focus would die with the card
	win.SetWindowLongPtrW(card, win.GWLP_USERDATA, 0) // the handle is freed before the destroy message arrives
	for w in ([]rawptr{h.card, h.scrim}) {
		if w == nil do continue
		win.ShowWindow(win.HWND(w), win.SW_HIDE)
		scope := w == h.card ? h.scope : nil // the body dies with the card
		win.PostMessageW(g_windows.root, WM_NV_DESTROY, win.WPARAM(uintptr(scope)), win.LPARAM(uintptr(w)))
	}
	dialog_apply_modal()
}

@(private)
_dialog_set_hidden :: proc(h: ^Dialog_Handle, hidden: bool) {
	for w in ([]rawptr{h.scrim, h.card}) {
		if w != nil do win.ShowWindow(win.HWND(w), hidden ? win.SW_HIDE : win.SW_SHOW)
	}
	dialog_apply_modal()
	if !hidden do nav_layout(g_windows.root)
}

// The top page's root and the bar's controls are enabled unless the top page has a modal dialog
// up. Also run by _nav_pop, since a page left disabled under another page comes back through it.
@(private)
dialog_apply_modal :: proc() {
	if len(g_nav) == 0 do return
	enabled := win.BOOL(dialog_top_modal() == nil)
	win.EnableWindow(win.HWND(g_nav[len(g_nav) - 1].root), enabled)
	win.EnableWindow(g_windows.nav_back, enabled)
	win.EnableWindow(g_windows.nav_menu, enabled)
	for b in g_windows.nav_actions do win.EnableWindow(b, enabled)
}

// Places the top page's visible dialogs in the host's client rect: the scrim over all of it, the
// card centered at dialog_width (less on a narrow window) by the body's height plus padding, then
// raises them above the pages in show order.
@(private)
dialog_layout :: proc(rc: win.RECT) {
	top := g_nav[len(g_nav) - 1]
	for d in g_dialogs {
		if d.page != top || d.hidden do continue
		if d.scrim != nil {
			win.MoveWindow(win.HWND(d.scrim), 0, 0, rc.right, rc.bottom, true)
			win.SetWindowPos(win.HWND(d.scrim), nil, 0, 0, 0, 0, win.SWP_NOMOVE | win.SWP_NOSIZE | win.SWP_NOACTIVATE)
		}
		pad := px(DIALOG_PAD)
		w := min(px(dialog_width(d)), rc.right - 2 * pad)
		hgt := measure(win.HWND(d.body)).y + 2 * pad
		win.MoveWindow(win.HWND(d.card), (rc.right - w) / 2, (rc.bottom - hgt) / 2, w, hgt, true)
		win.SetWindowPos(win.HWND(d.card), nil, 0, 0, 0, 0, win.SWP_NOMOVE | win.SWP_NOSIZE | win.SWP_NOACTIVATE) // HWND_TOP
	}
}

// A dialog's scrim swallows the mouse, reports a click for a dismissible dialog and fills itself
// with Dialog.scrim's colour; a scaffold's (scaffold_windows.odin) has its overlay in
// GWLP_USERDATA, stays black (the class brush) and reports a click.
@(private)
scrim_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	switch msg {
	case win.WM_LBUTTONDOWN:
		if h := overlay_handle_of(hwnd); h != nil {
			context = h.ctx
			overlay_scrim_notify(h)
			return 0
		}
		dialog_scrim_notify(rawptr(hwnd))
		return 0
	case win.WM_ERASEBKGND:
		if overlay_handle_of(hwnd) != nil do break
		for d in g_dialogs {
			if win.HWND(d.scrim) != hwnd do continue
			rc: win.RECT
			win.GetClientRect(hwnd, &rc)
			brush := win.CreateSolidBrush(colorref(dialog_scrim(d)))
			win.FillRect(win.HDC(wparam), &rc, brush)
			win.DeleteObject(win.HGDIOBJ(brush))
			return 1
		}
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@(private)
dialog_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := (^Dialog_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
	if h == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx

	switch msg {
	case win.WM_SIZE:
		callback_enter() // the body's Row / Column lay out inside this MoveWindow
		defer callback_exit()
		rc: win.RECT
		win.GetClientRect(hwnd, &rc)
		pad := px(DIALOG_PAD)
		if h.body != nil do win.MoveWindow(win.HWND(h.body), pad, pad, max(rc.right - 2 * pad, 0), max(rc.bottom - 2 * pad, 0), true)
		r := px(dialog_radius(h, DIALOG_RADIUS)) * 2
		win.SetWindowRgn(hwnd, CreateRoundRectRgn(0, 0, rc.right + 1, rc.bottom + 1, r, r), true) // the system owns the region
		return 0
	case win.WM_PAINT:
		ps: win.PAINTSTRUCT
		dc := win.BeginPaint(hwnd, &ps)
		rc: win.RECT
		win.GetClientRect(hwnd, &rc)
		light := h.dialog.light
		pen := win.CreatePen(win.PS_SOLID, 1, colorref(light ? PALETTE_LIGHT.separator : theme_palette().separator))
		old_pen := win.SelectObject(dc, win.HGDIOBJ(pen))
		old_brush := win.SelectObject(dc, win.HGDIOBJ(light ? g_theme_windows.light : g_theme_windows.bg))
		r := px(dialog_radius(h, DIALOG_RADIUS)) * 2
		win.RoundRect(dc, 0, 0, rc.right, rc.bottom, r, r)
		win.SelectObject(dc, old_brush)
		win.SelectObject(dc, old_pen)
		win.DeleteObject(win.HGDIOBJ(pen))
		win.EndPaint(hwnd, &ps)
		return 0
	case win.WM_CTLCOLORSTATIC:
		return ctlcolor_static(wparam, lparam)
	case win.WM_CTLCOLORBTN:
		return ctlcolor_button(lparam)
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

