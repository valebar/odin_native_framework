#+build windows
package nv

// Windows container backend: an "NVContainer" window that is the margin box. It places its child
// inside the margin, border and padding on WM_SIZE, and paints itself with GDI+ (a rounded rect
// inset by the margin over the parent's background) into an off-screen bitmap. Its fill is also a
// GDI brush (Container_Handle.box) that background_brush_of hands to every window inside it.

import win "core:sys/windows"

@(private)
_container_init :: proc(h: ^Container_Handle) {
	wnd := win.CreateWindowExW(0, wstr(CLASS_CONTAINER), nil, win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)
	h.root = View(wnd)
	container_make_brush(h)
	if h.container.child != nil do win.SetParent(win.HWND(h.container.child), wnd)
}

@(private)
_container_set_color :: proc(h: ^Container_Handle) {
	container_make_brush(h)
	// Every window inside erases with the new brush.
	win.RedrawWindow(win.HWND(h.root), nil, nil, win.RedrawWindowFlags(u32(win.RedrawWindowFlags.RDW_INVALIDATE) | u32(win.RedrawWindowFlags.RDW_ERASE) | u32(win.RedrawWindowFlags.RDW_ALLCHILDREN)))
}

// (Re)creates the solid brush of the fill; nil without a color.
@(private)
container_make_brush :: proc "contextless" (h: ^Container_Handle) {
	if h.box != nil do win.DeleteObject(win.HGDIOBJ(h.box))
	h.box = nil
	if h.container.color.a <= 0 do return
	c := color_argb(h.container.color)
	h.box = rawptr(win.CreateSolidBrush(win.RGB(c >> 16 & 0xff, c >> 8 & 0xff, c & 0xff)))
}

@(private)
container_handle_of :: proc "contextless" (hwnd: win.HWND) -> ^Container_Handle {
	return (^Container_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
}

// The insets in px, each side rounded on its own and summed, so measure, layout and paint agree
// to the pixel at a fractional DPI.
@(private) Container_Px :: struct {
	margin: [4]i32, // left, top, right, bottom
	frame:  [4]i32, // margin + border + padding
}

@(private)
container_px :: proc "contextless" (h: ^Container_Handle) -> Container_Px {
	c := &h.container
	b := px(c.border_width)
	m := [4]i32{px(c.margin.left), px(c.margin.top), px(c.margin.right), px(c.margin.bottom)}
	p := [4]i32{px(c.padding.left), px(c.padding.top), px(c.padding.right), px(c.padding.bottom)}
	return {m, m + p + b}
}

// Natural size in px: the given size plus the margin, or the child plus every inset.
@(private)
container_measure :: proc(hwnd: win.HWND) -> [2]i32 {
	h := container_handle_of(hwnd)
	if h == nil do return {}
	c := &h.container
	i := container_px(h)
	child: [2]i32
	if c.child != nil do child = measure(win.HWND(c.child))
	out: [2]i32
	out.x = c.width > 0 ? px(c.width) + i.margin[0] + i.margin[2] : child.x + i.frame[0] + i.frame[2]
	out.y = c.height > 0 ? px(c.height) + i.margin[1] + i.margin[3] : child.y + i.frame[1] + i.frame[3]
	return out
}

@(private)
container_layout :: proc "contextless" (hwnd: win.HWND, h: ^Container_Handle) {
	if h.container.child == nil do return
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	f := container_px(h).frame
	win.MoveWindow(win.HWND(h.container.child), f[0], f[1], max(rc.right - f[0] - f[2], 0), max(rc.bottom - f[1] - f[3], 0), true)
}

// A rounded rectangle as a GDI+ path (four quarter arcs); the caller deletes it.
@(private)
rounded_rect_path :: proc "contextless" (x, y, w, h, r: f32) -> GpPath {
	path: GpPath
	GdipCreatePath(0, &path) // FillModeAlternate
	d := min(2 * r, w, h)
	GdipAddPathArc(path, x, y, d, d, 180, 90)
	GdipAddPathArc(path, x + w - d, y, d, d, 270, 90)
	GdipAddPathArc(path, x + w - d, y + h - d, d, d, 0, 90)
	GdipAddPathArc(path, x, y + h - d, d, d, 90, 90)
	GdipClosePathFigure(path)
	return path
}

@(private)
container_paint :: proc(hwnd: win.HWND, h: ^Container_Handle) {
	ps: win.PAINTSTRUCT
	dc := win.BeginPaint(hwnd, &ps)
	defer win.EndPaint(hwnd, &ps)
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	if rc.right <= 0 || rc.bottom <= 0 do return

	mem := win.CreateCompatibleDC(dc)
	defer win.DeleteDC(mem)
	bmp := dib_section(rc.right, rc.bottom)
	defer win.DeleteObject(win.HGDIOBJ(bmp))
	old := win.SelectObject(mem, win.HGDIOBJ(bmp))
	defer win.SelectObject(mem, old)
	win.FillRect(mem, &rc, background_brush_of(win.GetParent(hwnd))) // the margin shows the parent

	c := &h.container
	m := container_px(h).margin
	x, y := f32(m[0]), f32(m[1])
	w := f32(rc.right - m[0] - m[2])
	hh := f32(rc.bottom - m[1] - m[3])
	if w > 0 && hh > 0 && (c.color.a > 0 || c.border_width > 0) {
		g: GpGraphics
		GdipCreateFromHDC(mem, &g) // in px: no world transform
		GdipSetSmoothingMode(g, GP_SMOOTHING_ANTIALIAS)
		r := f32(px(c.radius))
		if c.color.a > 0 {
			brush := with_brush(c.color)
			if r > 0 {
				path := rounded_rect_path(x, y, w, hh, r)
				GdipFillPath(g, brush, path)
				GdipDeletePath(path)
			} else {
				GdipFillRectangle(g, brush, x, y, w, hh)
			}
			GdipDeleteBrush(brush)
		}
		if c.border_width > 0 {
			bw := f32(px(c.border_width))
			pen := with_pen(c.border_color, f64(bw))
			// The stroke is centered on the path, so the path is inset by half the width to keep it inside.
			ix, iy, iw, ih := x + bw / 2, y + bw / 2, w - bw, hh - bw
			if r > 0 {
				path := rounded_rect_path(ix, iy, iw, ih, max(r - bw / 2, 0))
				GdipDrawPath(g, pen, path)
				GdipDeletePath(path)
			} else {
				GdipDrawRectangle(g, pen, ix, iy, iw, ih)
			}
			GdipDeletePen(pen)
		}
		GdipDeleteGraphics(g)
	}

	win.BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, win.SRCCOPY)
}

@(private)
container_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := container_handle_of(hwnd)
	if h == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx

	switch msg {
	case win.WM_SIZE:
		// A nested Row / Column lays out inside the child's MoveWindow.
		callback_enter()
		defer callback_exit()
		container_layout(hwnd, h)
		win.InvalidateRect(hwnd, nil, false)
		return 0
	case win.WM_PAINT:
		container_paint(hwnd, h)
		return 0
	case win.WM_ERASEBKGND:
		return 1 // WM_PAINT covers every pixel
	case win.WM_CTLCOLORSTATIC:
		return ctlcolor_static(wparam, lparam)
	case win.WM_NCDESTROY: // a popped page is destroyed with its children
		if h.box != nil do win.DeleteObject(win.HGDIOBJ(h.box))
		h.box = nil
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
