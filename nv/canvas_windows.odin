#+build windows
#+private
package nv

// Windows canvas backend: an "NVCanvas" window painted with GDI+ (plain GDI has no
// anti-aliasing) into an off-screen bitmap, then blitted. The GDI+ world transform scales dp to
// px; text goes through GDI on the same bitmap in the message font, or a loaded one, at the
// requested size. The canvas keeps one brush and one pen (Windows_Canvas, in Canvas_Handle.extra)
// and recolors them per primitive: creating a GDI+ object per call costs more than the drawing.
// The back buffer is kept across paints too, recreated only when the client size changes.
// clip_push saves the Graphics state (GdipSaveGraphics) and intersects its clip; GDI text, which
// ignores the GDI+ clip, gets the same rect (in px) on its DC.
// The left mouse button is captured while pressed, so a drag keeps reporting outside the window.
// Pixels are offset by half (PixelOffsetModeHalf): pixel i covers [i, i + 1], as in CoreGraphics,
// cairo and Skia, so whole-dp edges fall between pixels instead of across them.

import "base:builtin"
import "core:math"
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
@(private) GP_FILL_MODE_WINDING   :: i32(1)
@(private) GP_UNIT_WORLD          :: i32(0)
@(private) GP_MATRIX_ORDER_PREPEND :: i32(0)
@(private) GP_LINE_CAP_FLAT       :: i32(0)
@(private) GP_LINE_CAP_ROUND      :: i32(2)
@(private) GP_INTERPOLATION_HIGH_QUALITY_BICUBIC :: i32(7)
@(private) GP_PIXEL_OFFSET_HALF                  :: i32(4)
@(private) GP_LINE_JOIN_MITER     :: i32(0)
@(private) GP_LINE_JOIN_ROUND     :: i32(2)
@(private) GP_COMBINE_INTERSECT   :: i32(1)

@(private) GpPointF :: struct { x, y: f32 }

// One clip_push: the Graphics state to restore and the clip so far in px (for GDI text).
@(private) Windows_Clip :: struct {
	state: u32, // GraphicsState
	rect:  win.RECT,
}

// Per-canvas GDI+ state (Canvas_Handle.extra, in the page's arena): the brush and pen every
// primitive draws with, the colour / width they were last set to, and the back buffer.
@(private) Windows_Canvas :: struct {
	brush:      GpBrush,
	pen:        GpPen,
	brush_argb: u32,
	pen_argb:   u32,
	pen_width:  f32,
	pen_cap:    i32, // of both ends: round for lines, flat for arcs
	pen_join:   i32, // miter for rects, round for polylines
	clips:      [dynamic]Windows_Clip, // clip_push's, innermost last (the scope's arena); empty between paints
	mem:        win.HDC, // back buffer of `size` px; nil until the first paint
	bmp:        win.HBITMAP,
	old:        win.HGDIOBJ,
	size:       [2]i32,
	painting:   bool, // inside canvas_paint (an on_draw asking for its next frame: _canvas_redraw)
}

// canvas_proc's timer for the next frame of a canvas that asked for it from its own on_draw.
@(private) CANVAS_FRAME_TIMER :: 1

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
	GdipSetPenLineJoin      :: proc(pen: GpPen, join: i32) -> i32 ---
	GdipDrawLines           :: proc(graphics: GpGraphics, pen: GpPen, points: [^]GpPointF, count: i32) -> i32 ---
	GdipSaveGraphics        :: proc(graphics: GpGraphics, state: ^u32) -> i32 ---
	GdipRestoreGraphics     :: proc(graphics: GpGraphics, state: u32) -> i32 ---
	GdipSetClipRect         :: proc(graphics: GpGraphics, x, y, w, h: f32, combine: i32) -> i32 ---
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
	GdipStartPathFigure     :: proc(path: GpPath) -> i32 ---
	GdipAddPathLine         :: proc(path: GpPath, x1, y1, x2, y2: f32) -> i32 ---
	GdipAddPathBezier       :: proc(path: GpPath, x1, y1, x2, y2, x3, y3, x4, y4: f32) -> i32 ---
	GdipFillPath            :: proc(graphics: GpGraphics, brush: GpBrush, path: GpPath) -> i32 ---
	GdipDrawPath            :: proc(graphics: GpGraphics, pen: GpPen, path: GpPath) -> i32 ---
	GdipCreateBitmapFromStream :: proc(stream: ^win.IStream, bitmap: ^GpImage) -> i32 ---
	GdipCreateBitmapFromScan0 :: proc(width, height, stride: i32, format: i32, scan0: [^]u8, bitmap: ^GpImage) -> i32 ---
	GdipBitmapLockBits      :: proc(bitmap: GpImage, rect: ^GpRect, flags: u32, format: i32, data: ^GpBitmapData) -> i32 ---
	GdipBitmapUnlockBits    :: proc(bitmap: GpImage, data: ^GpBitmapData) -> i32 ---
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
	c.pen_cap = GP_LINE_CAP_FLAT // the pen's defaults
	c.pen_join = GP_LINE_JOIN_MITER
	c.clips = make([dynamic]Windows_Clip, scope_allocator(h.scope))
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
	// From its own on_draw (an animation: a spinner) the next frame comes from a timer, which
	// Windows delivers only once no window waits for WM_PAINT. Invalidated at once, the canvas
	// would again be the first window needing a paint, ahead of every window after it in Z order
	// (the bar's title and buttons), which then never painted while it animated.
	if c := (^Windows_Canvas)(h.extra); c != nil && c.painting {
		win.SetTimer(win.HWND(h.view), CANVAS_FRAME_TIMER, 16, nil)
		return
	}
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

// The canvas's brush / pen, recolored (and the pen resized and its caps / join set) only when the
// value changed. Caps only show on open figures, so the rectangles and ellipses leave them as they
// are; joins only on corners (rects: miter, polylines: round).
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
pen_for :: proc "contextless" (p: ^Painter, color: Color, width: f64, ends: Maybe(i32) = nil, join: Maybe(i32) = nil) -> GpPen {
	c := (^Windows_Canvas)(p.h.extra)
	if want, ok := ends.?; ok && want != c.pen_cap {
		GdipSetPenStartCap(c.pen, want)
		GdipSetPenEndCap(c.pen, want)
		c.pen_cap = want
	}
	if want, ok := join.?; ok && want != c.pen_join {
		GdipSetPenLineJoin(c.pen, want)
		c.pen_join = want
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

// The edges on whole pixels: anti-aliased, a fractional edge half-covers its pixel, and where two
// fills meet (a card drawn in pieces, stacked rows) the background shows through as a dark seam.
// A side thinner than a pixel keeps its fractional edges (a hairline stays faint).
@(private)
_fill_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	snap :: proc(v, size: f64) -> (start, length: f64) {
		s := f64(g_windows.dpi) / 96
		a, b := math.round(v * s) / s, math.round((v + size) * s) / s
		return b > a ? a : v, b > a ? b - a : size
	}
	sx, sw := snap(x, w)
	sy, sh := snap(y, h)
	GdipFillRectangle(p.native, brush_for(p, color), f32(sx), f32(sy), f32(sw), f32(sh))
}

@(private)
_stroke_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	GdipDrawRectangle(p.native, pen_for(p, color, width, join = GP_LINE_JOIN_MITER), f32(x), f32(y), f32(w), f32(h))
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
	saved: i32 // the DC's state before the clip, 0 without one
	if c := (^Windows_Canvas)(p.h.extra); len(c.clips) > 0 {
		r := c.clips[len(c.clips) - 1].rect
		saved = win.SaveDC(dc)
		IntersectClipRect(dc, r.left, r.top, r.right, r.bottom)
	}
	defer if saved != 0 do win.RestoreDC(dc, saved) // the back buffer's DC outlives the paint
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
	clear(&c.clips) // the core pops what on_draw left pushed
	g: GpGraphics
	GdipCreateFromHDC(c.mem, &g)
	GdipSetSmoothingMode(g, GP_SMOOTHING_ANTIALIAS)
	GdipSetPixelOffsetMode(g, GP_PIXEL_OFFSET_HALF)
	GdipSetInterpolationMode(g, GP_INTERPOLATION_HIGH_QUALITY_BICUBIC)
	scale := f32(g_windows.dpi) / 96
	GdipScaleWorldTransform(g, scale, scale, GP_MATRIX_ORDER_PREPEND)
	c.painting = true
	canvas_draw_notify(h, g, dp(rc.right), dp(rc.bottom), c.mem)
	c.painting = false
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
	case win.WM_TIMER:
		if wparam == CANVAS_FRAME_TIMER {
			win.KillTimer(hwnd, CANVAS_FRAME_TIMER)
			win.InvalidateRect(hwnd, nil, false)
			return 0
		}
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

// One open figure: butt ends, round joins.
@(private)
_stroke_polyline :: proc(p: ^Painter, points: [][2]f64, color: Color, width: f64) {
	pts := make([]GpPointF, len(points), context.temp_allocator)
	for q, i in points do pts[i] = {f32(q.x), f32(q.y)}
	pen := pen_for(p, color, width, GP_LINE_CAP_FLAT, GP_LINE_JOIN_ROUND)
	GdipDrawLines(p.native, pen, raw_data(pts), i32(len(pts)))
}

// The clip rect is in world units (dp), so the transform applies; the px copy clips GDI text.
@(private)
_clip_push :: proc(p: ^Painter, x, y, w, h: f64) {
	c := (^Windows_Canvas)(p.h.extra)
	state: u32
	GdipSaveGraphics(p.native, &state)
	GdipSetClipRect(p.native, f32(x), f32(y), f32(w), f32(h), GP_COMBINE_INTERSECT)
	r := win.RECT{px(x), px(y), px(x + w), px(y + h)}
	if n := len(c.clips); n > 0 {
		o := c.clips[n - 1].rect
		r = {max(r.left, o.left), max(r.top, o.top), min(r.right, o.right), min(r.bottom, o.bottom)}
		r.right, r.bottom = max(r.right, r.left), max(r.bottom, r.top)
	}
	append(&c.clips, Windows_Clip{state, r})
}

@(private)
_clip_pop :: proc(p: ^Painter) {
	c := (^Windows_Canvas)(p.h.extra)
	if len(c.clips) == 0 do return
	GdipRestoreGraphics(p.native, builtin.pop(&c.clips).state)
}
