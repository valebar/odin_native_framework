#+build windows
package nv

// Windows canvas backend: an "NVCanvas" window painted with GDI+ (plain GDI has no
// anti-aliasing) into an off-screen bitmap, then blitted. The GDI+ world transform scales dp to
// px; text goes through GDI on the same bitmap in the message font, or a loaded one, at the
// requested size.
// The left mouse button is captured while pressed, so a drag keeps reporting outside the window.

import win "core:sys/windows"

foreign import gdiplus "system:gdiplus.lib"

// Minimal GDI+ flat API. Every call returns a GpStatus (0 = Ok).
@(private) GpGraphics :: rawptr
@(private) GpBrush    :: rawptr
@(private) GpPen      :: rawptr
@(private) GpImage    :: rawptr // a GpBitmap (image_windows.odin)
@(private) GpPath     :: rawptr

@(private) GdiplusStartupInput :: struct {
	GdiplusVersion:           u32,
	DebugEventCallback:       rawptr,
	SuppressBackgroundThread: win.BOOL,
	SuppressExternalCodecs:   win.BOOL,
}

@(private) GP_SMOOTHING_ANTIALIAS :: i32(4)
@(private) GP_UNIT_WORLD          :: i32(0)
@(private) GP_MATRIX_ORDER_PREPEND :: i32(0)
@(private) GP_LINE_CAP_ROUND      :: i32(2)
@(private) GP_INTERPOLATION_HIGH_QUALITY_BICUBIC :: i32(7)
@(private) GP_PIXEL_OFFSET_HIGH_QUALITY          :: i32(2)

@(default_calling_convention="system", private)
foreign gdiplus {
	GdiplusStartup          :: proc(token: ^uintptr, input: ^GdiplusStartupInput, output: rawptr) -> i32 ---
	GdipCreateFromHDC       :: proc(hdc: win.HDC, graphics: ^GpGraphics) -> i32 ---
	GdipDeleteGraphics      :: proc(graphics: GpGraphics) -> i32 ---
	GdipSetSmoothingMode    :: proc(graphics: GpGraphics, mode: i32) -> i32 ---
	GdipScaleWorldTransform :: proc(graphics: GpGraphics, sx, sy: f32, order: i32) -> i32 ---
	GdipGetDC               :: proc(graphics: GpGraphics, hdc: ^win.HDC) -> i32 ---
	GdipReleaseDC           :: proc(graphics: GpGraphics, hdc: win.HDC) -> i32 ---
	GdipCreateSolidFill     :: proc(argb: u32, brush: ^GpBrush) -> i32 ---
	GdipDeleteBrush         :: proc(brush: GpBrush) -> i32 ---
	GdipCreatePen1          :: proc(argb: u32, width: f32, unit: i32, pen: ^GpPen) -> i32 ---
	GdipDeletePen           :: proc(pen: GpPen) -> i32 ---
	GdipSetPenStartCap      :: proc(pen: GpPen, cap: i32) -> i32 ---
	GdipSetPenEndCap        :: proc(pen: GpPen, cap: i32) -> i32 ---
	GdipFillRectangle       :: proc(graphics: GpGraphics, brush: GpBrush, x, y, w, h: f32) -> i32 ---
	GdipDrawRectangle       :: proc(graphics: GpGraphics, pen: GpPen, x, y, w, h: f32) -> i32 ---
	GdipDrawLine            :: proc(graphics: GpGraphics, pen: GpPen, x1, y1, x2, y2: f32) -> i32 ---
	GdipFillEllipse         :: proc(graphics: GpGraphics, brush: GpBrush, x, y, w, h: f32) -> i32 ---
	GdipDrawEllipse         :: proc(graphics: GpGraphics, pen: GpPen, x, y, w, h: f32) -> i32 ---
	GdipCreatePath          :: proc(fill_mode: i32, path: ^GpPath) -> i32 ---
	GdipDeletePath          :: proc(path: GpPath) -> i32 ---
	GdipAddPathArc          :: proc(path: GpPath, x, y, w, h, start, sweep: f32) -> i32 ---
	GdipClosePathFigure     :: proc(path: GpPath) -> i32 ---
	GdipFillPath            :: proc(graphics: GpGraphics, brush: GpBrush, path: GpPath) -> i32 ---
	GdipDrawPath            :: proc(graphics: GpGraphics, pen: GpPen, path: GpPath) -> i32 ---
	GdipCreateBitmapFromStream :: proc(stream: ^win.IStream, bitmap: ^GpImage) -> i32 ---
	GdipGetImageWidth       :: proc(image: GpImage, width: ^u32) -> i32 ---
	GdipGetImageHeight      :: proc(image: GpImage, height: ^u32) -> i32 ---
	GdipDisposeImage        :: proc(image: GpImage) -> i32 ---
	GdipDrawImageRect       :: proc(graphics: GpGraphics, image: GpImage, x, y, w, h: f32) -> i32 ---
	GdipSetInterpolationMode :: proc(graphics: GpGraphics, mode: i32) -> i32 ---
	GdipSetPixelOffsetMode  :: proc(graphics: GpGraphics, mode: i32) -> i32 ---
}

@(private)
gdiplus_init :: proc() {
	token: uintptr
	input := GdiplusStartupInput{GdiplusVersion = 1}
	GdiplusStartup(&token, &input, nil) // never shut down: lives as long as the process
}

@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	wnd := win.CreateWindowExW(0, wstr(CLASS_CANVAS), nil, win.WS_CHILD | win.WS_VISIBLE,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)
	h.root = View(wnd)
	h.view = rawptr(wnd)
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	win.InvalidateRect(win.HWND(h.view), nil, false)
}

@(private)
with_brush :: proc "contextless" (c: Color) -> GpBrush {
	brush: GpBrush
	GdipCreateSolidFill(color_argb(c), &brush)
	return brush
}

@(private)
with_pen :: proc "contextless" (c: Color, width: f64) -> GpPen {
	pen: GpPen
	GdipCreatePen1(color_argb(c), f32(width), GP_UNIT_WORLD, &pen)
	return pen
}

@(private)
_fill_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	brush := with_brush(color)
	defer GdipDeleteBrush(brush)
	GdipFillRectangle(p.native, brush, f32(x), f32(y), f32(w), f32(h))
}

@(private)
_stroke_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	pen := with_pen(color, width)
	defer GdipDeletePen(pen)
	GdipDrawRectangle(p.native, pen, f32(x), f32(y), f32(w), f32(h))
}

@(private)
_draw_line :: proc(p: ^Painter, x0, y0, x1, y1: f64, color: Color, width: f64) {
	pen := with_pen(color, width)
	defer GdipDeletePen(pen)
	GdipSetPenStartCap(pen, GP_LINE_CAP_ROUND)
	GdipSetPenEndCap(pen, GP_LINE_CAP_ROUND)
	GdipDrawLine(p.native, pen, f32(x0), f32(y0), f32(x1), f32(y1))
}

@(private)
_fill_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	brush := with_brush(color)
	defer GdipDeleteBrush(brush)
	GdipFillEllipse(p.native, brush, f32(x), f32(y), f32(w), f32(h))
}

@(private)
_stroke_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	pen := with_pen(color, width)
	defer GdipDeletePen(pen)
	GdipDrawEllipse(p.native, pen, f32(x), f32(y), f32(w), f32(h))
}

// GDI ignores the GDI+ transform, so text is placed in px. The HDC from GdipGetDC has the
// default TA_TOP | TA_LEFT alignment, so (x, y) is the top-left of the line. The font comes from
// the style_font cache (the message font or the loaded face, at the style's size).
@(private)
_draw_text :: proc(p: ^Painter, text: string, x, y: f64, style: Text_Style) {
	hfont := style_font(style, g_windows.font)

	dc: win.HDC
	GdipGetDC(p.native, &dc)
	defer GdipReleaseDC(p.native, dc)
	old := win.SelectObject(dc, win.HGDIOBJ(hfont))
	defer win.SelectObject(dc, old)
	win.SetBkMode(dc, .TRANSPARENT)
	c := color_argb(style.color)
	win.SetTextColor(dc, win.RGB(c >> 16 & 0xff, c >> 8 & 0xff, c & 0xff)) // GDI text has no alpha
	w := wstr(text)
	win.TextOutW(dc, px(x), px(y), w, i32(len(string16_of(w))))
}

// px → dp, the inverse of `px`.
@(private)
dp :: proc "contextless" (v: i32) -> f64 {
	return f64(v) * 96 / f64(g_windows.dpi)
}

@(private)
canvas_paint :: proc(hwnd: win.HWND, h: ^Canvas_Handle) {
	ps: win.PAINTSTRUCT
	dc := win.BeginPaint(hwnd, &ps)
	defer win.EndPaint(hwnd, &ps)
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	if rc.right <= 0 || rc.bottom <= 0 do return

	mem := win.CreateCompatibleDC(dc)
	defer win.DeleteDC(mem)
	bmp := win.CreateCompatibleBitmap(dc, rc.right, rc.bottom)
	defer win.DeleteObject(win.HGDIOBJ(bmp))
	old := win.SelectObject(mem, win.HGDIOBJ(bmp))
	defer win.SelectObject(mem, old)
	win.FillRect(mem, &rc, background_brush_of(win.GetParent(hwnd)))

	g: GpGraphics
	GdipCreateFromHDC(mem, &g)
	GdipSetSmoothingMode(g, GP_SMOOTHING_ANTIALIAS)
	scale := f32(g_windows.dpi) / 96
	GdipScaleWorldTransform(g, scale, scale, GP_MATRIX_ORDER_PREPEND)
	canvas_draw_notify(h, g, dp(rc.right), dp(rc.bottom), mem)
	GdipDeleteGraphics(g)

	win.BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, win.SRCCOPY)
}

@(private)
canvas_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := (^Canvas_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
	if h == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx

	x, y := dp(win.GET_X_LPARAM(lparam)), dp(win.GET_Y_LPARAM(lparam))
	switch msg {
	case win.WM_PAINT:
		canvas_paint(hwnd, h)
		return 0
	case win.WM_ERASEBKGND:
		return 1 // WM_PAINT covers every pixel
	case win.WM_SIZE:
		win.InvalidateRect(hwnd, nil, false)
		return 0
	case win.WM_LBUTTONDOWN:
		win.SetCapture(hwnd)
		canvas_pointer_notify(h, .Down, x, y)
		return 0
	case win.WM_MOUSEMOVE:
		if win.GetCapture() == hwnd do canvas_pointer_notify(h, .Move, x, y)
		return 0
	case win.WM_LBUTTONUP:
		if win.GetCapture() == hwnd {
			win.ReleaseCapture()
			canvas_pointer_notify(h, .Up, x, y)
		}
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
