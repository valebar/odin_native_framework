#+build windows
package nv

// Windows canvas backend: an "NVCanvas" window painted with GDI+ (plain GDI has no
// anti-aliasing) into an off-screen bitmap, then blitted. The GDI+ world transform scales dp to
// px; text goes through GDI on the same bitmap in the message font, or a loaded one, at the
// requested size. The canvas keeps one brush and one pen (Windows_Canvas, in Canvas_Handle.extra)
// and recolors them per primitive: creating a GDI+ object per call costs more than the drawing.
// The back buffer is kept across paints too, recreated only when the client size changes.
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
@(private) GP_LINE_CAP_FLAT       :: i32(0)
@(private) GP_LINE_CAP_ROUND      :: i32(2)
@(private) GP_INTERPOLATION_HIGH_QUALITY_BICUBIC :: i32(7)
@(private) GP_PIXEL_OFFSET_DEFAULT               :: i32(0)
@(private) GP_PIXEL_OFFSET_HIGH_QUALITY          :: i32(2)

// Per-canvas GDI+ state (Canvas_Handle.extra, in the page's arena): the brush and pen every
// primitive draws with, the colour / width they were last set to, and the back buffer.
@(private) Windows_Canvas :: struct {
	brush:      GpBrush,
	pen:        GpPen,
	brush_argb: u32,
	pen_argb:   u32,
	pen_width:  f32,
	pen_cap:    i32, // of both ends: round for lines, flat for arcs
	mem:        win.HDC, // back buffer of `size` px; nil until the first paint
	bmp:        win.HBITMAP,
	old:        win.HGDIOBJ,
	size:       [2]i32,
}

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
	GdipSetSolidFillColor   :: proc(brush: GpBrush, argb: u32) -> i32 ---
	GdipDeleteBrush         :: proc(brush: GpBrush) -> i32 ---
	GdipCreatePen1          :: proc(argb: u32, width: f32, unit: i32, pen: ^GpPen) -> i32 ---
	GdipSetPenColor         :: proc(pen: GpPen, argb: u32) -> i32 ---
	GdipSetPenWidth         :: proc(pen: GpPen, width: f32) -> i32 ---
	GdipDeletePen           :: proc(pen: GpPen) -> i32 ---
	GdipSetPenStartCap      :: proc(pen: GpPen, cap: i32) -> i32 ---
	GdipSetPenEndCap        :: proc(pen: GpPen, cap: i32) -> i32 ---
	GdipFillRectangle       :: proc(graphics: GpGraphics, brush: GpBrush, x, y, w, h: f32) -> i32 ---
	GdipDrawRectangle       :: proc(graphics: GpGraphics, pen: GpPen, x, y, w, h: f32) -> i32 ---
	GdipDrawLine            :: proc(graphics: GpGraphics, pen: GpPen, x1, y1, x2, y2: f32) -> i32 ---
	GdipFillEllipse         :: proc(graphics: GpGraphics, brush: GpBrush, x, y, w, h: f32) -> i32 ---
	GdipDrawEllipse         :: proc(graphics: GpGraphics, pen: GpPen, x, y, w, h: f32) -> i32 ---
	GdipDrawArc             :: proc(graphics: GpGraphics, pen: GpPen, x, y, w, h, start_angle, sweep_angle: f32) -> i32 ---
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

	c := scope_new_in(Windows_Canvas)
	h.extra = c
	GdipCreateSolidFill(0, &c.brush)
	GdipCreatePen1(0, 1, GP_UNIT_WORLD, &c.pen)
	c.pen_width = 1
	c.pen_cap = GP_LINE_CAP_FLAT // the pen's default
	scope_on_dispose(canvas_dispose, h)
}

// Runs from WM_NV_DESTROY after the window is gone; GDI objects do not depend on it.
@(private)
canvas_dispose :: proc(data: rawptr) {
	c := (^Windows_Canvas)((^Canvas_Handle)(data).extra)
	GdipDeletePen(c.pen)
	GdipDeleteBrush(c.brush)
	canvas_buffer_free(c)
}

// A top-down 32-bit DIB section for a back buffer. GDI+ draws straight into a DIB's pixels; on a
// device-dependent bitmap (CreateCompatibleBitmap) it has to fetch and store them through GDI
// around every anti-aliased primitive, which costs far more than the drawing.
@(private)
dib_section :: proc "contextless" (width, height: i32) -> win.HBITMAP {
	bi: win.BITMAPINFO
	bi.bmiHeader = {
		biSize = size_of(win.BITMAPINFOHEADER), biWidth = width, biHeight = -height,
		biPlanes = 1, biBitCount = 32, biCompression = win.BI_RGB,
	}
	bits: rawptr
	return win.CreateDIBSection(nil, &bi, win.DIB_RGB_COLORS, &bits, nil, 0)
}

@(private)
canvas_buffer_free :: proc "contextless" (c: ^Windows_Canvas) {
	if c.mem == nil do return
	win.SelectObject(c.mem, c.old)
	win.DeleteObject(win.HGDIOBJ(c.bmp))
	win.DeleteDC(c.mem)
	c.mem, c.bmp, c.old, c.size = nil, nil, nil, {}
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	win.InvalidateRect(win.HWND(h.view), nil, false)
}

// A throwaway brush / pen for a single use (the container's paint); the caller deletes it.
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

// The canvas's brush / pen, recolored (and the pen resized and its caps set) only when the value
// changed. Caps only show on open figures, so the rectangles and ellipses leave them as they are.
@(private)
brush_for :: proc "contextless" (p: ^Painter, color: Color) -> GpBrush {
	c := (^Windows_Canvas)(p.h.extra)
	if argb := color_argb(color); argb != c.brush_argb {
		GdipSetSolidFillColor(c.brush, argb)
		c.brush_argb = argb
	}
	return c.brush
}

@(private)
pen_for :: proc "contextless" (p: ^Painter, color: Color, width: f64, ends: Maybe(i32) = nil) -> GpPen {
	c := (^Windows_Canvas)(p.h.extra)
	if want, ok := ends.?; ok && want != c.pen_cap {
		GdipSetPenStartCap(c.pen, want)
		GdipSetPenEndCap(c.pen, want)
		c.pen_cap = want
	}
	if argb := color_argb(color); argb != c.pen_argb {
		GdipSetPenColor(c.pen, argb)
		c.pen_argb = argb
	}
	if w := f32(width); w != c.pen_width {
		GdipSetPenWidth(c.pen, w)
		c.pen_width = w
	}
	return c.pen
}

@(private)
_fill_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	GdipFillRectangle(p.native, brush_for(p, color), f32(x), f32(y), f32(w), f32(h))
}

@(private)
_stroke_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	GdipDrawRectangle(p.native, pen_for(p, color, width), f32(x), f32(y), f32(w), f32(h))
}

@(private)
_draw_line :: proc(p: ^Painter, x0, y0, x1, y1: f64, color: Color, width: f64) {
	GdipDrawLine(p.native, pen_for(p, color, width, GP_LINE_CAP_ROUND), f32(x0), f32(y0), f32(x1), f32(y1))
}

@(private)
_fill_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	GdipFillEllipse(p.native, brush_for(p, color), f32(x), f32(y), f32(w), f32(h))
}

@(private)
_stroke_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	GdipDrawEllipse(p.native, pen_for(p, color, width), f32(x), f32(y), f32(w), f32(h))
}

@(private)
_stroke_arc :: proc(p: ^Painter, cx, cy, radius, start, sweep: f64, color: Color, width: f64) {
	d := f32(2 * radius)
	GdipDrawArc(p.native, pen_for(p, color, width, GP_LINE_CAP_FLAT), f32(cx - radius), f32(cy - radius), d, d, f32(start), f32(sweep))
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

// GDI's extent of the same font _draw_text selects: the advance and the line height (tmHeight).
@(private)
_measure_text :: proc(p: ^Painter, text: string, style: Text_Style) -> (width, height: f64) {
	dc: win.HDC
	GdipGetDC(p.native, &dc)
	defer GdipReleaseDC(p.native, dc)
	sz := text_size(dc, style_font(style, g_windows.font), text)
	return dp(sz.cx), dp(sz.cy)
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

	c := (^Windows_Canvas)(h.extra)
	if c.mem == nil || c.size != {rc.right, rc.bottom} {
		canvas_buffer_free(c)
		c.mem = win.CreateCompatibleDC(dc)
		c.bmp = dib_section(rc.right, rc.bottom)
		c.old = win.SelectObject(c.mem, win.HGDIOBJ(c.bmp))
		c.size = {rc.right, rc.bottom}
	}
	win.FillRect(c.mem, &rc, background_brush_of(win.GetParent(hwnd)))

	// A Graphics per paint: cheap, and a kept one would accumulate clip and transform state.
	g: GpGraphics
	GdipCreateFromHDC(c.mem, &g)
	GdipSetSmoothingMode(g, GP_SMOOTHING_ANTIALIAS)
	GdipSetInterpolationMode(g, GP_INTERPOLATION_HIGH_QUALITY_BICUBIC)
	scale := f32(g_windows.dpi) / 96
	GdipScaleWorldTransform(g, scale, scale, GP_MATRIX_ORDER_PREPEND)
	canvas_draw_notify(h, g, dp(rc.right), dp(rc.bottom), c.mem)
	GdipDeleteGraphics(g)

	win.BitBlt(dc, 0, 0, rc.right, rc.bottom, c.mem, 0, 0, win.SRCCOPY)
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
	case win.WM_MOUSEWHEEL, win.WM_MOUSEHWHEEL:
		// WHEEL_DELTA (120) per notch; the vertical wheel is positive away from the user (towards
		// the top), the horizontal one positive to the right. Without on_scroll, DefWindowProc
		// hands it to the parent.
		if h.canvas.on_scroll == nil do break
		d := f64(win.GET_WHEEL_DELTA_WPARAM(wparam)) / 120 * SCROLL_LINE
		if msg == win.WM_MOUSEWHEEL do canvas_scroll_notify(h, 0, -d)
		else do canvas_scroll_notify(h, d, 0)
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
