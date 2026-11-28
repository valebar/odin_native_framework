#+build windows
#+private
package nv

// Windows canvas backend: an "NVCanvas" window drawn with Direct2D into its back buffer (a DIB
// section) through one shared ID2D1DCRenderTarget, then blitted in WM_PAINT, in DIPs at the
// window's DPI, so dp are DIPs; text is DirectWrite's, in the theme's font or a loaded one
// (font_windows.odin keeps its collection). Not an ID2D1HwndRenderTarget per window: that one
// presents after EndDraw, on the GPU, clipped as its window was when the frame was queued, so a
// window shown over an animating canvas (any dialog over a settings page) got a stale frame over
// it that nothing painted again (6 of 24 real clicks on the VM); the blit is GDI's, in order. The
// frame costs more than the window target's (14 ms against 5 at 2560x1257 on the VM, the copy
// back included) and less than GDI+'s (18; GDI text had no alpha either). Shared: the factories,
// the target with its brush and the bitmaps uploaded to it (all made again after a device loss,
// D2DERR_RECREATE_TARGET), the stroke styles and the text formats.
// The GDI+ declarations below stay for the widgets that still paint with it (containers, the
// bar, the scaffold, the Image widget).
// The left mouse button is captured while pressed, so a drag keeps reporting outside the window.

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


// Per-canvas state (Canvas_Handle.extra, in the page's arena): the back buffer, kept across paints
// and made again when the client size changes.
@(private) Windows_Canvas :: struct {
	mem:      win.HDC, // nil until the first paint
	bmp:      win.HBITMAP,
	old:      win.HGDIOBJ,
	size:     [2]i32,
	painting: bool, // inside canvas_paint (an on_draw asking for its next frame: _canvas_redraw)
}

// A bitmap uploaded to the shared target, as of its generation, last drawn at paint `used`.
@(private) Canvas_Bitmap :: struct {
	bitmap: ^ID2D1Bitmap,
	gen:    u64,
	used:   u64,
	size:   [2]int,
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
	GdipFillPolygon         :: proc(graphics: GpGraphics, brush: GpBrush, points: [^]GpPointF, count: i32, fill_mode: i32) -> i32 ---
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


// The device-independent objects, made with the first canvas.
@(private) g_d2d: struct {
	factory:    ^ID2D1Factory,
	dwrite:     ^IDWriteFactory5, // an IDWriteFactory before Windows 10 1703: only its first part is called
	dwrite5:    bool,
	loader:     ^IDWriteInMemoryFontFileLoader, // loaded fonts (font_windows.odin)
	line:       ^ID2D1StrokeStyle, // round caps: draw_line
	open:       ^ID2D1StrokeStyle, // butt ends, round joins: stroke_polyline
	formats:    map[Text_Key]Text_Format,
	system:     [32]u16, // the theme's font family (the message font's face name), NUL-terminated
	tried:      bool,
	// The target every canvas draws through (bound to its back buffer per paint) and what lives on it.
	target:     ^ID2D1DCRenderTarget,
	dc:         ^ID2D1DeviceContext, // the same target, for DrawBitmap's cubic filter; nil before Windows 8
	brush:      ^ID2D1SolidColorBrush,
	brush_argb: u32,
	dpi:        u32,
	bitmaps:    map[u64]Canvas_Bitmap, // by bitmap id (image_windows.odin)
	paints:     u64,
	drawing:    bool, // between BeginDraw and EndDraw: a paint inside a paint waits for the next
}

// A text format per font, size, weight and slant, with the face's ascent and descent: a line box is
// ascent + descent high and its baseline the ascent below its top, as GDI's.
@(private) Text_Key :: struct {
	font:   ^Font,
	size:   f32,
	weight: u32,
	italic: bool,
}

@(private) Text_Format :: struct {
	format:  ^IDWriteTextFormat,
	ascent:  f32,
	descent: f32,
}

// The factories (DirectWrite may already exist for a font loaded before the first canvas).
@(private)
d2d_start :: proc() -> bool {
	if g_d2d.factory != nil do return true
	if g_d2d.tried do return false
	g_d2d.tried = true
	if !dwrite_start() do return false
	if D2D1CreateFactory(0, &IID_ID2D1Factory, nil, (^rawptr)(&g_d2d.factory)) < 0 do return false
	stroke :: proc(caps, join: u32) -> ^ID2D1StrokeStyle {
		props := D2D1_STROKE_STYLE_PROPERTIES{start_cap = caps, end_cap = caps, dash_cap = caps, line_join = join, miter_limit = 10}
		s: ^ID2D1StrokeStyle
		g_d2d.factory->CreateStrokeStyle(&props, nil, 0, &s)
		return s
	}
	g_d2d.line = stroke(D2D1_CAP_STYLE_ROUND, D2D1_LINE_JOIN_MITER)
	g_d2d.open = stroke(D2D1_CAP_STYLE_FLAT, D2D1_LINE_JOIN_ROUND)
	g_d2d.formats = make(map[Text_Key]Text_Format, nv_heap())
	lf: win.LOGFONTW
	win.GetObjectW(win.HANDLE(g_windows.font), size_of(lf), &lf)
	copy(g_d2d.system[:len(g_d2d.system) - 1], lf.lfFaceName[:])
	return true
}

// DirectWrite alone: IDWriteFactory5 where there is one (in-memory fonts), else IDWriteFactory.
@(private)
dwrite_start :: proc() -> bool {
	if g_d2d.dwrite != nil do return true
	if DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, &IID_IDWriteFactory5, (^rawptr)(&g_d2d.dwrite)) >= 0 {
		g_d2d.dwrite5 = true
		return true
	}
	return DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, &IID_IDWriteFactory, (^rawptr)(&g_d2d.dwrite)) >= 0
}

// The style's format: the loaded font's own collection and family (font_windows.odin), or the
// theme's family among the system's.
@(private)
text_format :: proc(style: Text_Style) -> ^Text_Format {
	key := Text_Key{font = style.font, size = f32(style.size), italic = style.italic}
	switch text_weight(style.weight, false) {
	case .Default:  key.weight = style.font != nil ? u32(style.font.weight) : 400
	case .Regular:  key.weight = 400
	case .Medium:   key.weight = 500
	case .Semibold: key.weight = 600
	case .Bold:     key.weight = 700
	}
	if f := style.font; f != nil do key.italic ||= f.italic
	if t, ok := &g_d2d.formats[key]; ok do return t
	family := cstring16(&g_d2d.system[0])
	collection: ^IDWriteFontCollection
	if f := style.font; f != nil {
		if dw := font_dwrite(f); dw != nil && dw.collection != nil {
			family = cstring16(raw_data(dw.family))
			collection = dw.collection
		}
	}
	slant := u32(key.italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL)
	t: Text_Format
	locale := [1]u16{}
	if g_d2d.dwrite->CreateTextFormat(family, collection, key.weight, slant, DWRITE_FONT_STRETCH_NORMAL, key.size, cstring16(&locale[0]), &t.format) < 0 do return nil
	t.format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP)
	// The face's metrics, from the collection the format resolves the family in.
	coll := collection
	if coll == nil do g_d2d.dwrite->GetSystemFontCollection(&coll, false)
	t.ascent, t.descent = key.size * 0.9, key.size * 0.25 // when the family is not found
	index: u32
	exists: win.BOOL
	if coll != nil && coll->FindFamilyName(family, &index, &exists) >= 0 && exists {
		fam: ^IDWriteFontFamily
		if coll->GetFontFamily(index, &fam) >= 0 {
			font: ^IDWriteFont
			if fam->GetFirstMatchingFont(key.weight, DWRITE_FONT_STRETCH_NORMAL, slant, &font) >= 0 {
				m: DWRITE_FONT_METRICS
				font->GetMetrics(&m)
				em := f32(m.design_units_per_em)
				if em > 0 do t.ascent, t.descent = f32(m.ascent) * key.size / em, f32(m.descent) * key.size / em
				com_release(font)
			}
			com_release(fam)
		}
	}
	if collection == nil do com_release(coll)
	t.format->SetLineSpacing(DWRITE_LINE_SPACING_METHOD_UNIFORM, t.ascent + t.descent, t.ascent)
	g_d2d.formats[key] = t
	return &g_d2d.formats[key]
}

// A loaded font goes: the formats over it go too.
@(private)
text_formats_drop :: proc(f: ^Font) {
	gone := make([dynamic]Text_Key, context.temp_allocator)
	for key, t in g_d2d.formats do if key.font == f {
		com_release(t.format)
		append(&gone, key)
	}
	for key in gone do delete_key(&g_d2d.formats, key)
}


@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	wnd := win.CreateWindowExW(0, wstr(CLASS_CANVAS), nil, win.WS_CHILD | win.WS_VISIBLE,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)
	h.root = View(wnd)
	h.view = rawptr(wnd)

	c := scope_new_in(Windows_Canvas)
	h.extra = c
	scope_on_dispose(canvas_dispose, h)
	d2d_start()
}

// Runs from WM_NV_DESTROY after the window is gone; GDI objects do not depend on it.
@(private)
canvas_dispose :: proc(data: rawptr) {
	h := (^Canvas_Handle)(data)
	hires_drop_canvas(win.HWND(h.view))
	canvas_buffer_free((^Windows_Canvas)(h.extra))
}

@(private)
canvas_buffer_free :: proc "contextless" (c: ^Windows_Canvas) {
	if c.mem == nil do return
	win.SelectObject(c.mem, c.old)
	win.DeleteObject(win.HGDIOBJ(c.bmp))
	win.DeleteDC(c.mem)
	c.mem, c.bmp, c.old, c.size = nil, nil, nil, {}
}

// The shared target and what was made on it.
@(private)
d2d_target_free :: proc() {
	for _, b in g_d2d.bitmaps do com_release(b.bitmap)
	clear(&g_d2d.bitmaps)
	com_release(g_d2d.brush)
	com_release(g_d2d.dc)
	com_release(g_d2d.target)
	g_d2d.brush, g_d2d.dc, g_d2d.target = nil, nil, nil
}

// The shared target, made at the first paint and after a device loss: the GPU where there is one.
@(private)
d2d_target :: proc() -> ^ID2D1DCRenderTarget {
	if g_d2d.target != nil do return g_d2d.target
	if !d2d_start() do return nil
	props := D2D1_RENDER_TARGET_PROPERTIES{
		pixel_format = {DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE}, // opaque: ClearType text
		dpi_x = f32(g_windows.dpi), dpi_y = f32(g_windows.dpi),
	}
	if g_d2d.factory->CreateDCRenderTarget(&props, &g_d2d.target) < 0 do return nil
	white := D2D1_COLOR_F{1, 1, 1, 1}
	if (^ID2D1RenderTarget)(g_d2d.target)->CreateSolidColorBrush(&white, nil, &g_d2d.brush) < 0 {
		d2d_target_free()
		return nil
	}
	g_d2d.brush_argb = 0xFFFFFFFF
	(^win.IUnknown)(g_d2d.target)->QueryInterface(&IID_ID2D1DeviceContext, (^rawptr)(&g_d2d.dc))
	if g_d2d.bitmaps == nil do g_d2d.bitmaps = make(map[u64]Canvas_Bitmap, nv_heap())
	g_d2d.dpi = g_windows.dpi
	return g_d2d.target
}

// A top-down 32-bit DIB section: a canvas's back buffer, and the GDI+ widgets'.
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
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	// From its own on_draw (an animation: a spinner) the next frame comes from a timer, which
	// Windows delivers only once no window waits for WM_PAINT. Invalidated at once, the canvas
	// would again be the first window needing a paint, ahead of every window after it in Z order
	// (the bar's title and buttons), which then never painted while it animated.
	if c := (^Windows_Canvas)(h.extra); c != nil && c.painting {
		win.SetTimer(win.HWND(h.view), CANVAS_FRAME_TIMER, 16, nil)
		hires_add(16, {canvas = win.HWND(h.view)}) // SetTimer alone comes every 33 ms
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

@(private)
target_of :: #force_inline proc "contextless" (p: ^Painter) -> ^ID2D1RenderTarget {
	return (^ID2D1RenderTarget)(p.native)
}

// The shared brush, recolored only when the colour changed.
@(private)
brush_for :: proc "contextless" (p: ^Painter, color: Color) -> ^ID2D1Brush {
	if argb := color_argb(color); argb != g_d2d.brush_argb {
		col := D2D1_COLOR_F{color.r, color.g, color.b, color.a}
		g_d2d.brush->SetColor(&col)
		g_d2d.brush_argb = argb
	}
	return (^ID2D1Brush)(g_d2d.brush)
}

@(private)
rect_f :: #force_inline proc "contextless" (x, y, w, h: f64) -> D2D1_RECT_F {
	return {f32(x), f32(y), f32(x + w), f32(y + h)}
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
	r := rect_f(sx, sy, sw, sh)
	target_of(p)->FillRectangle(&r, brush_for(p, color))
}

@(private)
_stroke_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	r := rect_f(x, y, w, h)
	target_of(p)->DrawRectangle(&r, brush_for(p, color), f32(width), nil)
}

@(private)
_draw_line :: proc(p: ^Painter, x0, y0, x1, y1: f64, color: Color, width: f64) {
	target_of(p)->DrawLine({f32(x0), f32(y0)}, {f32(x1), f32(y1)}, brush_for(p, color), f32(width), g_d2d.line)
}

@(private)
_fill_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	e := D2D1_ELLIPSE{{f32(x + w / 2), f32(y + h / 2)}, f32(w / 2), f32(h / 2)}
	target_of(p)->FillEllipse(&e, brush_for(p, color))
}

@(private)
_stroke_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	e := D2D1_ELLIPSE{{f32(x + w / 2), f32(y + h / 2)}, f32(w / 2), f32(h / 2)}
	target_of(p)->DrawEllipse(&e, brush_for(p, color), f32(width), nil)
}

// A path geometry and its open sink; the caller closes the sink and releases both.
@(private)
path_open :: proc() -> (geo: ^ID2D1PathGeometry, sink: ^ID2D1GeometrySink, ok: bool) {
	if g_d2d.factory->CreatePathGeometry(&geo) < 0 do return
	if geo->Open(&sink) < 0 {
		com_release(geo)
		return nil, nil, false
	}
	return geo, sink, true
}

// Degrees clockwise from 3 o'clock, butt ends; a whole turn is the circle.
@(private)
_stroke_arc :: proc(p: ^Painter, cx, cy, radius, start, sweep: f64, color: Color, width: f64) {
	if sweep == 0 || radius <= 0 do return
	if abs(sweep) >= 360 {
		_stroke_ellipse(p, cx - radius, cy - radius, 2 * radius, 2 * radius, color, width)
		return
	}
	geo, sink, ok := path_open()
	if !ok do return
	at :: proc(cx, cy, r, deg: f64) -> D2D1_POINT_2F {
		a := deg * math.PI / 180
		return {f32(cx + r * math.cos(a)), f32(cy + r * math.sin(a))}
	}
	sink->BeginFigure(at(cx, cy, radius, start), D2D1_FIGURE_BEGIN_HOLLOW)
	arc := D2D1_ARC_SEGMENT{
		point = at(cx, cy, radius, start + sweep), size = {f32(radius), f32(radius)},
		sweep = sweep > 0 ? D2D1_SWEEP_DIRECTION_CLOCKWISE : D2D1_SWEEP_DIRECTION_COUNTER_CLOCKWISE,
		arc_size = abs(sweep) > 180 ? D2D1_ARC_SIZE_LARGE : D2D1_ARC_SIZE_SMALL,
	}
	sink->AddArc(&arc)
	sink->EndFigure(D2D1_FIGURE_END_OPEN)
	sink->Close()
	com_release(sink)
	target_of(p)->DrawGeometry((^ID2D1Geometry)(geo), brush_for(p, color), f32(width), nil)
	com_release(geo)
}

// One open figure: butt ends, round joins.
@(private)
_stroke_polyline :: proc(p: ^Painter, points: [][2]f64, color: Color, width: f64) {
	geo, sink, ok := path_open()
	if !ok do return
	pts := make([]D2D1_POINT_2F, len(points), context.temp_allocator)
	for q, i in points do pts[i] = {f32(q.x), f32(q.y)}
	sink->BeginFigure(pts[0], D2D1_FIGURE_BEGIN_HOLLOW)
	sink->AddLines(raw_data(pts[1:]), u32(len(pts) - 1))
	sink->EndFigure(D2D1_FIGURE_END_OPEN)
	sink->Close()
	com_release(sink)
	target_of(p)->DrawGeometry((^ID2D1Geometry)(geo), brush_for(p, color), f32(width), g_d2d.open)
	com_release(geo)
}

@(private)
_fill_polygon :: proc(p: ^Painter, points: [][2]f64, color: Color) {
	geo, sink, ok := path_open()
	if !ok do return
	pts := make([]D2D1_POINT_2F, len(points), context.temp_allocator)
	for q, i in points do pts[i] = {f32(q.x), f32(q.y)}
	sink->SetFillMode(D2D1_FILL_MODE_WINDING)
	sink->BeginFigure(pts[0], D2D1_FIGURE_BEGIN_FILLED)
	sink->AddLines(raw_data(pts[1:]), u32(len(pts) - 1))
	sink->EndFigure(D2D1_FIGURE_END_CLOSED)
	sink->Close()
	com_release(sink)
	target_of(p)->FillGeometry((^ID2D1Geometry)(geo), brush_for(p, color), nil)
	com_release(geo)
}

// (x, y) is the top-left of the line box: the uniform line spacing puts the baseline the ascent
// below it. The layout box is wide enough for any line; NO_WRAP keeps it one.
@(private)
_draw_text :: proc(p: ^Painter, text: string, x, y: f64, style: Text_Style) {
	if text == "" do return
	t := text_format(style)
	if t == nil do return
	w := win.utf8_to_utf16(text, context.temp_allocator)
	r := D2D1_RECT_F{f32(x), f32(y), f32(x) + 1e6, f32(y) + t.ascent + t.descent}
	target_of(p)->DrawText(raw_data(w), u32(len(w)), t.format, &r, brush_for(p, style.color), D2D1_DRAW_TEXT_OPTIONS_NONE, DWRITE_MEASURING_MODE_NATURAL)
}

// The same under a rotation about (x, y), clockwise for a positive angle.
@(private)
_draw_text_rotated :: proc(p: ^Painter, text: string, x, y, angle: f64, style: Text_Style) {
	rt := target_of(p)
	old: D2D1_MATRIX_3X2_F
	rt->GetTransform(&old)
	cs, sn := math.cos(angle), math.sin(angle)
	m := D2D1_MATRIX_3X2_F{f32(cs), f32(sn), f32(-sn), f32(cs), f32(x - x * cs + y * sn), f32(y - x * sn - y * cs)}
	rt->SetTransform(&m)
	_draw_text(p, text, x, y, style)
	rt->SetTransform(&old)
}

// The advance (trailing spaces included) and the line box's height, as _draw_text lays it out.
@(private)
_measure_text :: proc(p: ^Painter, text: string, style: Text_Style) -> (width, height: f64) {
	t := text_format(style)
	if t == nil do return 0, 0
	height = f64(t.ascent + t.descent)
	if text == "" do return 0, height
	w := win.utf8_to_utf16(text, context.temp_allocator)
	layout: ^IDWriteTextLayout
	if g_d2d.dwrite->CreateTextLayout(raw_data(w), u32(len(w)), t.format, 1e6, 1e6, &layout) < 0 do return 0, height
	m: DWRITE_TEXT_METRICS
	layout->GetMetrics(&m)
	com_release(layout)
	return f64(m.width_including_trailing_whitespace), height
}

// Aliased: the clip's edge cuts whole pixels, as GDI+'s did.
@(private)
_clip_push :: proc(p: ^Painter, x, y, w, h: f64) {
	r := rect_f(x, y, w, h)
	target_of(p)->PushAxisAlignedClip(&r, D2D1_ANTIALIAS_MODE_ALIASED)
}

@(private)
_clip_pop :: proc(p: ^Painter) {
	target_of(p)->PopAxisAlignedClip()
}

// The bitmap uploaded to the shared target: once, again when its pixels changed
// (bitmap_set_rgba), premultiplied from GDI+'s decode.
@(private)
canvas_bitmap :: proc(b: ^Bitmap) -> ^ID2D1Bitmap {
	id, gen, ok := bitmap_id(b)
	if !ok do return nil
	rt := (^ID2D1RenderTarget)(g_d2d.target)
	cb, has := &g_d2d.bitmaps[id]
	if has && cb.gen == gen {
		cb.used = g_d2d.paints
		return cb.bitmap
	}
	rect := GpRect{0, 0, i32(b.width), i32(b.height)}
	data: GpBitmapData
	if GdipBitmapLockBits(b.native, &rect, GP_IMAGE_LOCK_READ, GP_PIXEL_FORMAT_32BPP_PARGB, &data) != 0 do return nil
	defer GdipBitmapUnlockBits(b.native, &data)
	if has && cb.size == {b.width, b.height} {
		cb.bitmap->CopyFromMemory(nil, data.scan0, u32(data.stride))
		cb.gen, cb.used = gen, g_d2d.paints
		return cb.bitmap
	}
	if has do com_release(cb.bitmap)
	props := D2D1_BITMAP_PROPERTIES{{DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED}, 96, 96}
	bmp: ^ID2D1Bitmap
	if rt->CreateBitmap({u32(b.width), u32(b.height)}, data.scan0, u32(data.stride), &props, &bmp) < 0 {
		if has do delete_key(&g_d2d.bitmaps, id)
		return nil
	}
	g_d2d.bitmaps[id] = {bmp, gen, g_d2d.paints, {b.width, b.height}}
	return bmp
}

// Stretched over the rect, cubic where the target is a device context (Windows 8+).
@(private)
_draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	bmp := canvas_bitmap(b)
	if bmp == nil do return
	dest := rect_f(x, y, w, h)
	if g_d2d.dc != nil do g_d2d.dc->DrawBitmap1(bmp, &dest, 1, D2D1_INTERPOLATION_MODE_HIGH_QUALITY_CUBIC, nil, nil)
	else do target_of(p)->DrawBitmap(bmp, &dest, 1, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR, nil)
}

// The keyboard's Shift, Ctrl, Alt and Windows keys now.
@(private)
canvas_mods :: proc "contextless" () -> Modifiers {
	m: Modifiers
	if win.GetKeyState(win.VK_SHIFT) < 0 do m += {.Shift}
	if win.GetKeyState(win.VK_CONTROL) < 0 do m += {.Ctrl}
	if win.GetKeyState(win.VK_MENU) < 0 do m += {.Alt}
	if win.GetKeyState(win.VK_LWIN) < 0 || win.GetKeyState(win.VK_RWIN) < 0 do m += {.Cmd}
	return m
}

@(private)
dp :: proc "contextless" (v: i32) -> f64 {
	return f64(v) * 96 / f64(g_windows.dpi)
}

// The window's background (its container's colour, else the theme's), as the paint's clear colour.
@(private)
canvas_background :: proc(hwnd: win.HWND) -> D2D1_COLOR_F {
	lb: win.LOGBRUSH
	win.GetObjectW(win.HANDLE(background_brush_of(win.GetParent(hwnd))), size_of(lb), &lb)
	c := u32(lb.lbColor)
	return {f32(c & 0xff) / 255, f32(c >> 8 & 0xff) / 255, f32(c >> 16 & 0xff) / 255, 1}
}

@(private)
canvas_paint :: proc(hwnd: win.HWND, h: ^Canvas_Handle) {
	ps: win.PAINTSTRUCT
	dc := win.BeginPaint(hwnd, &ps)
	defer win.EndPaint(hwnd, &ps)
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	if rc.right <= 0 || rc.bottom <= 0 do return
	if g_d2d.drawing { // a paint from inside another's on_draw: the shared target is busy
		win.InvalidateRect(hwnd, nil, false)
		return
	}
	rt := (^ID2D1RenderTarget)(d2d_target())
	if rt == nil do return

	c := (^Windows_Canvas)(h.extra)
	if c.mem == nil || c.size != {rc.right, rc.bottom} {
		canvas_buffer_free(c)
		c.mem = win.CreateCompatibleDC(dc)
		c.bmp = dib_section(rc.right, rc.bottom)
		c.old = win.SelectObject(c.mem, win.HGDIOBJ(c.bmp))
		c.size = {rc.right, rc.bottom}
	}
	if g_d2d.dpi != g_windows.dpi {
		rt->SetDpi(f32(g_windows.dpi), f32(g_windows.dpi))
		g_d2d.dpi = g_windows.dpi
	}
	if g_d2d.target->BindDC(c.mem, &rc) < 0 do return
	g_d2d.drawing = true
	rt->BeginDraw()
	bg := canvas_background(hwnd)
	rt->Clear(&bg)
	g_d2d.paints += 1
	c.painting = true
	canvas_draw_notify(h, g_d2d.target, dp(rc.right), dp(rc.bottom))
	c.painting = false
	hr := rt->EndDraw(nil, nil) // the pixels are in the back buffer once it returns
	g_d2d.drawing = false
	if hr == D2DERR_RECREATE_TARGET {
		d2d_target_free()
		win.InvalidateRect(hwnd, nil, false)
		return
	}
	win.BitBlt(dc, 0, 0, rc.right, rc.bottom, c.mem, 0, 0, win.SRCCOPY)
	// Bitmaps not drawn for a while, or freed, go.
	gone := make([dynamic]u64, context.temp_allocator)
	for id, b in g_d2d.bitmaps {
		if bitmap_live(id) && g_d2d.paints - b.used < 600 do continue
		com_release(b.bitmap)
		append(&gone, id)
	}
	for id in gone do delete_key(&g_d2d.bitmaps, id)
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
			hires_drop_canvas(hwnd)
			win.InvalidateRect(hwnd, nil, false)
			return 0
		}
	case win.WM_SIZE:
		win.InvalidateRect(hwnd, nil, false)
		return 0
	case win.WM_LBUTTONDOWN:
		win.SetCapture(hwnd)
		canvas_pointer_notify(h, .Down, x, y, canvas_mods())
		return 0
	case win.WM_MOUSEMOVE:
		if win.GetCapture() == hwnd do canvas_pointer_notify(h, .Move, x, y, canvas_mods())
		return 0
	case win.WM_LBUTTONUP:
		if win.GetCapture() == hwnd {
			win.ReleaseCapture()
			canvas_pointer_notify(h, .Up, x, y, canvas_mods())
		}
		return 0
	case win.WM_MOUSEWHEEL, win.WM_MOUSEHWHEEL:
		// WHEEL_DELTA (120) per notch; the vertical wheel is positive away from the user (towards
		// the top), the horizontal one positive to the right; lparam is the pointer on the screen.
		// A precision touchpad sends these too, so they count as a wheel's. Without on_scroll,
		// DefWindowProc hands it to the parent.
		if h.canvas.on_scroll == nil do break
		d := f64(win.GET_WHEEL_DELTA_WPARAM(wparam)) / 120 * SCROLL_LINE
		pt := win.POINT{win.GET_X_LPARAM(lparam), win.GET_Y_LPARAM(lparam)}
		win.ScreenToClient(hwnd, &pt)
		src := Scroll_Source{dp(pt.x), dp(pt.y), true, false}
		if msg == win.WM_MOUSEWHEEL do canvas_scroll_notify(h, 0, -d, src, canvas_mods())
		else do canvas_scroll_notify(h, d, 0, src, canvas_mods())
		return 0
	case WM_GESTURE:
		// A touch screen's zoom: the scale from the fingers' distance against the first.
		if h.canvas.on_scale == nil do break
		gi := GESTUREINFO{cbSize = size_of(GESTUREINFO)}
		if !GetGestureInfo(win.HANDLE(uintptr(lparam)), &gi) || gi.dwID != GID_ZOOM do break
		pt := win.POINT{i32(gi.ptsLocation[0]), i32(gi.ptsLocation[1])}
		win.ScreenToClient(hwnd, &pt)
		dist := f64(gi.ullArguments & 0xFFFFFFFF)
		if gi.dwFlags & GF_BEGIN != 0 {
			h.scale_from = {dist, 1}
			canvas_scale_notify(h, .Down, 1, 1, dp(pt.x), dp(pt.y), canvas_mods())
		} else if h.scale_from.x > 0 {
			h.scale_from.y = dist / h.scale_from.x
			canvas_scale_notify(h, gi.dwFlags & GF_END != 0 ? .Up : .Move, h.scale_from.y, h.scale_from.y, dp(pt.x), dp(pt.y), canvas_mods())
		}
		CloseGestureInfoHandle(win.HANDLE(uintptr(lparam)))
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}
