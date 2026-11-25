#+build darwin
package nv

// CoreGraphics drawing shared by the macOS and iOS canvas backends. Both hand drawRect: a
// top-left-origin CGContext (the macOS view is flipped), so the primitives are identical.
// Only canvas_color differs (NSColor / UIColor); fonts come from apple_font below: the system font,
// or a loaded one (a CGFont from the bytes, sized into a CTFont, which is toll-free bridged to
// NSFont and UIFont). The image decode (ImageIO → CGImage), draw_image and the download helpers
// are shared the same way.

import "base:runtime"
import "core:math"
import NS "core:sys/darwin/Foundation"

foreign import cg "system:CoreGraphics.framework"

CGContextRef :: distinct rawptr

CG_LINE_CAP_BUTT  :: i32(0)
CG_LINE_CAP_ROUND :: i32(1)

@(default_calling_convention="c")
foreign cg {
	CGContextSetRGBFillColor   :: proc(c: CGContextRef, r, g, b, a: NS.Float) ---
	CGContextSetRGBStrokeColor :: proc(c: CGContextRef, r, g, b, a: NS.Float) ---
	CGContextSetLineWidth      :: proc(c: CGContextRef, width: NS.Float) ---
	CGContextSetLineCap        :: proc(c: CGContextRef, cap: i32) ---
	CGContextFillRect          :: proc(c: CGContextRef, rect: NS.Rect) ---
	CGContextStrokeRectWithWidth :: proc(c: CGContextRef, rect: NS.Rect, width: NS.Float) ---
	CGContextFillEllipseInRect   :: proc(c: CGContextRef, rect: NS.Rect) ---
	CGContextStrokeEllipseInRect :: proc(c: CGContextRef, rect: NS.Rect) ---
	CGContextBeginPath         :: proc(c: CGContextRef) ---
	CGContextMoveToPoint       :: proc(c: CGContextRef, x, y: NS.Float) ---
	CGContextAddLineToPoint    :: proc(c: CGContextRef, x, y: NS.Float) ---
	CGContextAddArc            :: proc(c: CGContextRef, x, y, radius, start_angle, end_angle: NS.Float, clockwise: i32) ---
	CGContextStrokePath        :: proc(c: CGContextRef) ---
	CGContextSaveGState        :: proc(c: CGContextRef) ---
	CGContextRestoreGState     :: proc(c: CGContextRef) ---
	CGContextTranslateCTM      :: proc(c: CGContextRef, tx, ty: NS.Float) ---
	CGContextScaleCTM          :: proc(c: CGContextRef, sx, sy: NS.Float) ---
	CGContextSetInterpolationQuality :: proc(c: CGContextRef, quality: i32) ---
	CGContextDrawImage         :: proc(c: CGContextRef, rect: NS.Rect, image: CGImageRef) ---
	CGImageGetWidth            :: proc(image: CGImageRef) -> uint ---
	CGImageGetHeight           :: proc(image: CGImageRef) -> uint ---
	CGImageRelease             :: proc(image: CGImageRef) ---
	CGDataProviderCreateWithCFData :: proc(data: ^NS.Data) -> CGDataProviderRef --- // CFDataRef: toll-free bridged
	CGDataProviderRelease          :: proc(provider: CGDataProviderRef) ---
	CGFontCreateWithDataProvider   :: proc(provider: CGDataProviderRef) -> CGFontRef ---
	CGFontRelease                  :: proc(font: CGFontRef) ---
}

CGImageRef        :: distinct rawptr
CGImageSourceRef  :: distinct rawptr
CGDataProviderRef :: distinct rawptr
CGFontRef         :: distinct rawptr
CTFontRef         :: distinct rawptr

CG_INTERPOLATION_HIGH :: i32(3)

foreign import imageio "system:ImageIO.framework"
foreign import coretext "system:CoreText.framework"
foreign import corefoundation "system:CoreFoundation.framework"
foreign import libsystem "system:System"

@(default_calling_convention="c")
foreign imageio {
	CGImageSourceCreateWithData     :: proc(data: ^NS.Data, options: rawptr) -> CGImageSourceRef --- // CFDataRef: toll-free bridged
	CGImageSourceCreateImageAtIndex :: proc(source: CGImageSourceRef, index: uint, options: rawptr) -> CGImageRef ---
}

@(default_calling_convention="c")
foreign coretext {
	CTFontCreateWithGraphicsFont :: proc(font: CGFontRef, size: NS.Float, mtx: rawptr, attributes: rawptr) -> CTFontRef ---
}

@(default_calling_convention="c")
foreign corefoundation {
	CFRelease     :: proc(cf: rawptr) ---
	CFAutorelease :: proc(cf: rawptr) -> rawptr ---
}

// Fonts: the bytes become a CGFont, kept for the Font's lifetime; no CTFontManager registration
// is needed to use it directly. The CTFonts made from it are cached by size (Font.extra), since
// every widget and every canvas text draw would otherwise create one.
@(private) Apple_Font_Cache :: struct {
	entries: [8]struct { size: f64, font: CTFontRef }, // retained
	n, next: int, // filled count; the slot the next eviction takes
}

@(private)
_font_load :: proc(f: ^Font, data: []u8) -> bool {
	ns_data := send(^NS.Data, NS.Data, "dataWithBytes:length:", raw_data(data), NS.UInteger(len(data)))
	provider := CGDataProviderCreateWithCFData(ns_data)
	if provider == nil do return false
	defer CGDataProviderRelease(provider)
	font := CGFontCreateWithDataProvider(provider)
	if font == nil do return false
	f.native = rawptr(font)
	f.extra = new(Apple_Font_Cache)
	return true
}

@(private)
_font_free :: proc(f: ^Font) {
	cache := (^Apple_Font_Cache)(f.extra)
	for e in cache.entries[:cache.n] do CFRelease(rawptr(e.font))
	free(cache)
	CGFontRelease(CGFontRef(f.native))
}

// A CTFont of the loaded face at `size`, usable wherever an NSFont / UIFont is. The Font's cache
// owns it; a caller that keeps it retains it (setFont: does), since the oldest of the 8 cached
// sizes is released when a ninth is made.
@(private)
ct_font :: proc "c" (f: ^Font, size: f64) -> ^NS.Object {
	cache := (^Apple_Font_Cache)(f.extra)
	for e in cache.entries[:cache.n] do if e.size == size do return (^NS.Object)(e.font)
	font := CTFontCreateWithGraphicsFont(CGFontRef(f.native), NS.Float(size), nil, nil)
	if cache.n < len(cache.entries) {
		cache.entries[cache.n] = {size, font}
		cache.n += 1
	} else {
		e := &cache.entries[cache.next]
		CFRelease(rawptr(e.font))
		e^ = {size, font}
		cache.next = (cache.next + 1) % len(cache.entries)
	}
	return (^NS.Object)(font)
}

// libdispatch: the _f variants take a function pointer instead of a block.
@(default_calling_convention="c")
foreign libsystem {
	_dispatch_main_q: u8 // dispatch_get_main_queue() is a macro for its address
	dispatch_async_f :: proc(queue: rawptr, ctx: rawptr, work: proc "c" (ctx: rawptr)) ---
	dispatch_after_f :: proc(when_: u64, queue: rawptr, ctx: rawptr, work: proc "c" (ctx: rawptr)) ---
	dispatch_time    :: proc(when_: u64, delta: i64) -> u64 --- // dispatch_time_t; DISPATCH_TIME_NOW is 0
}

// Images: ImageIO decodes into a CGImage, shared by both canvases and both image views. EXIF
// orientation is not applied.
@(private)
_bitmap_decode :: proc(b: ^Bitmap, data: []u8) -> bool {
	ns_data := send(^NS.Data, NS.Data, "dataWithBytes:length:", raw_data(data), NS.UInteger(len(data)))
	source := CGImageSourceCreateWithData(ns_data, nil)
	if source == nil do return false
	defer CFRelease(rawptr(source))
	image := CGImageSourceCreateImageAtIndex(source, 0, nil)
	if image == nil do return false
	b.native = rawptr(image)
	b.width, b.height = int(CGImageGetWidth(image)), int(CGImageGetHeight(image))
	return true
}

@(private)
_bitmap_free :: proc(b: ^Bitmap) {
	CGImageRelease(CGImageRef(b.native))
}

// CGContextDrawImage draws bottom-up, so the image is flipped back inside the rect.
@(private)
_draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	ctx := CGContextRef(p.native)
	CGContextSaveGState(ctx)
	CGContextSetInterpolationQuality(ctx, CG_INTERPOLATION_HIGH)
	CGContextTranslateCTM(ctx, NS.Float(x), NS.Float(y + h))
	CGContextScaleCTM(ctx, 1, -1)
	CGContextDrawImage(ctx, cg_rect(0, 0, w, h), CGImageRef(b.native))
	CGContextRestoreGState(ctx)
}

// Downloads: runs on the worker thread (fetch_darwin.odin), which has no autorelease pool of its
// own; allocates on the heap only.
@(private)
_http_get :: proc(url: string) -> []u8 {
	NS.scoped_autoreleasepool()
	ns_url := send(^NS.URL, NS.URL, "URLWithString:", ns_string(url))
	if ns_url == nil do return nil
	data := send(^NS.Data, NS.Data, "dataWithContentsOfURL:", ns_url)
	if data == nil do return nil
	n := int(send(NS.UInteger, data, "length"))
	out := make([]u8, n, runtime.heap_allocator())
	send(nil, data, "getBytes:length:", raw_data(out), NS.UInteger(n))
	return out
}

@(private)
_post_main :: proc(f: ^Fetch) {
	dispatch_async_f(&_dispatch_main_q, f, fetch_main)
}

@(private)
fetch_main :: proc "c" (data: rawptr) {
	f := (^Fetch)(data)
	context = f.ctx
	fetch_notify(f)
}

@(private)
cg_rect :: #force_inline proc "contextless" (x, y, w, h: f64) -> NS.Rect {
	return {{NS.Float(x), NS.Float(y)}, {NS.Float(w), NS.Float(h)}}
}

@(private)
cg_fill :: proc "contextless" (p: ^Painter, c: Color) -> CGContextRef {
	ctx := CGContextRef(p.native)
	CGContextSetRGBFillColor(ctx, NS.Float(c.r), NS.Float(c.g), NS.Float(c.b), NS.Float(c.a))
	return ctx
}

@(private)
cg_stroke :: proc "contextless" (p: ^Painter, c: Color, width: f64) -> CGContextRef {
	ctx := CGContextRef(p.native)
	CGContextSetRGBStrokeColor(ctx, NS.Float(c.r), NS.Float(c.g), NS.Float(c.b), NS.Float(c.a))
	CGContextSetLineWidth(ctx, NS.Float(width))
	return ctx
}

@(private)
_fill_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	CGContextFillRect(cg_fill(p, color), cg_rect(x, y, w, h))
}

@(private)
_stroke_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	CGContextStrokeRectWithWidth(cg_stroke(p, color, width), cg_rect(x, y, w, h), NS.Float(width))
}

@(private)
_draw_line :: proc(p: ^Painter, x0, y0, x1, y1: f64, color: Color, width: f64) {
	ctx := cg_stroke(p, color, width)
	CGContextSetLineCap(ctx, CG_LINE_CAP_ROUND)
	CGContextBeginPath(ctx)
	CGContextMoveToPoint(ctx, NS.Float(x0), NS.Float(y0))
	CGContextAddLineToPoint(ctx, NS.Float(x1), NS.Float(y1))
	CGContextStrokePath(ctx)
}

@(private)
_fill_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	CGContextFillEllipseInRect(cg_fill(p, color), cg_rect(x, y, w, h))
}

@(private)
_stroke_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	CGContextStrokeEllipseInRect(cg_stroke(p, color, width), cg_rect(x, y, w, h))
}

// Angles grow clockwise on screen: in these top-left contexts CoreGraphics' counterclockwise
// (clockwise = 0) is clockwise. The cap is reset to butt, since _draw_line leaves it round.
@(private)
_stroke_arc :: proc(p: ^Painter, cx, cy, radius, start, sweep: f64, color: Color, width: f64) {
	ctx := cg_stroke(p, color, width)
	CGContextSetLineCap(ctx, CG_LINE_CAP_BUTT)
	CGContextBeginPath(ctx)
	a0 := start * math.PI / 180
	CGContextAddArc(ctx, NS.Float(cx), NS.Float(cy), NS.Float(radius), NS.Float(a0), NS.Float(a0 + sweep * math.PI / 180), 0)
	CGContextStrokePath(ctx)
}

// Per-canvas draw state (Canvas_Handle.extra, in the page's arena): the attribute dictionary of
// the last text style drawn, retained and reused while the style repeats (the font, the color
// and the dictionary itself are all objects a text draw would otherwise make), and a redraw asked
// for from inside on_draw (apple_canvas_flush_redraw).
@(private) Apple_Canvas :: struct {
	style:         Text_Style,
	attrs:         ^NS.Object, // nil until the first text draw
	drawing:       bool,       // inside drawRect:
	redraw_queued: bool,       // canvas_redraw was called while drawing
	pending:       ^Apple_Canvas_Redraw, // macOS: the main-queue hop in flight, nil when none
	link:          ^NS.Object,           // iOS: the CADisplayLink (canvas_link_resume), nil until needed
}

// A redraw asked for during drawRect:. CoreAnimation drops a setNeedsDisplay issued while the
// layer displays (the flag is cleared when the draw returns), so it is re-issued later: on iOS
// from the canvas's display link, on macOS from the next turn of the main queue. On the heap like
// Image_Fetch: the page can die before the hop lands, and apple_canvas_dispose detaches it.
@(private) Apple_Canvas_Redraw :: struct {
	h: ^Canvas_Handle, // nil once the canvas's scope died
}

@(private)
apple_canvas_init :: proc(h: ^Canvas_Handle) {
	c := scope_new_in(Apple_Canvas)
	h.extra = c
	scope_on_dispose(apple_canvas_dispose, c)
}

@(private)
apple_canvas_dispose :: proc(data: rawptr) {
	c := (^Apple_Canvas)(data)
	if c.attrs != nil do send(nil, c.attrs, "autorelease")
	if c.pending != nil do c.pending.h = nil // the hop lands on nothing
	if c.link != nil do send(nil, c.link, "invalidate") // leaves the run loop and lets go of the view
}

// drawRect: on both OSes. Its own callback bracket keeps `h` alive through the flush when on_draw
// popped the page (the outermost callback_exit destroys the retired scope).
@(private)
apple_canvas_draw :: proc(h: ^Canvas_Handle, ctx: rawptr, width, height: f64) {
	callback_enter()
	defer callback_exit()
	c := (^Apple_Canvas)(h.extra)
	c.drawing = true
	canvas_draw_notify(h, ctx, width, height)
	c.drawing = false
	apple_canvas_flush_redraw(h)
}

// True inside drawRect:, where CoreAnimation would drop the setNeedsDisplay; the request is
// parked for apple_canvas_flush_redraw instead.
@(private)
apple_canvas_park_redraw :: proc(h: ^Canvas_Handle) -> bool {
	c := (^Apple_Canvas)(h.extra)
	if c.drawing do c.redraw_queued = true
	return c.drawing
}

// Re-issues a parked redraw: on iOS the display link's next frame takes it, on macOS the next
// turn of the main queue; one hop in flight is enough, since it invalidates the whole view.
@(private)
apple_canvas_flush_redraw :: proc(h: ^Canvas_Handle) {
	c := (^Apple_Canvas)(h.extra)
	if !c.redraw_queued do return
	when IS_IOS {
		canvas_link_resume(h)
	} else {
		c.redraw_queued = false
		if c.pending != nil do return
		t := new(Apple_Canvas_Redraw, runtime.heap_allocator())
		t.h = h
		c.pending = t
		dispatch_async_f(&_dispatch_main_q, t, apple_canvas_redraw_main)
	}
}

@(private)
apple_canvas_redraw_main :: proc "c" (data: rawptr) {
	t := (^Apple_Canvas_Redraw)(data)
	h := t.h
	context = h != nil ? h.ctx : runtime.default_context()
	free(t, runtime.heap_allocator())
	if h == nil do return // the page was popped meanwhile
	(^Apple_Canvas)(h.extra).pending = nil
	_canvas_redraw(h) // not drawing now, so setNeedsDisplay sticks
}

// NSString drawAtPoint:withAttributes: draws into the current context, which is the canvas's
// during drawRect:. "NSFont" / "NSColor" are the values of NSFontAttributeName /
// NSForegroundColorAttributeName in both AppKit and UIKit.
@(private)
_draw_text :: proc(p: ^Painter, text: string, x, y: f64, style: Text_Style) {
	send(nil, ns_string(text), "drawAtPoint:withAttributes:", NS.Point{NS.Float(x), NS.Float(y)}, apple_text_attrs(p, style))
}

// sizeWithAttributes: is the box drawAtPoint:withAttributes: fills: the advance and the line height.
@(private)
_measure_text :: proc(p: ^Painter, text: string, style: Text_Style) -> (width, height: f64) {
	size := send(NS.Size, ns_string(text), "sizeWithAttributes:", apple_text_attrs(p, style))
	return f64(size.width), f64(size.height)
}

// The canvas's attribute dictionary for `style`, kept while the style repeats.
@(private)
apple_text_attrs :: proc(p: ^Painter, style: Text_Style) -> ^NS.Object {
	c := (^Apple_Canvas)(p.h.extra)
	if c.attrs == nil || c.style != style {
		keys := [2]^NS.Object{NS.AT("NSFont"), NS.AT("NSColor")}
		values := [2]^NS.Object{apple_font(style, style.size, false), canvas_color(style.color)}
		attrs := (^NS.Object)(NS.Dictionary.dictionaryWithObjects((^NS.id)(&values[0]), (^^NS.Copying)(&keys[0]), 2))
		send(nil, attrs, "retain")
		if c.attrs != nil do send(nil, c.attrs, "release")
		c.attrs, c.style = attrs, style
	}
	return c.attrs
}

// Sys_Font / Sys_Color (NSFont / UIFont, NSColor / UIColor, which share the selectors used here)
// are aliased in appkit_macos.odin and uikit.odin.

// True when the style changes the font, so a widget keeps its native one otherwise.
@(private)
style_sets_font :: proc "contextless" (s: Text_Style) -> bool {
	return s.font != nil || s.size > 0 || s.weight != .Default || s.italic
}

// The font for `s` (autoreleased): the loaded face at the size (one face: its own weight and
// slant), else the system font; `size` and `bold` are the widget's defaults for the zero fields.
// Italic goes through the font descriptor's symbolic traits (Italic is 1 << 0 in both
// NSFontDescriptorSymbolicTraits and UIFontDescriptorSymbolicTraits).
@(private)
apple_font :: proc "contextless" (s: Text_Style, size: f64, bold: bool) -> ^NS.Object {
	sz := NS.Float(s.size > 0 ? s.size : size)
	if s.font != nil do return ct_font(s.font, f64(sz))
	weight: NS.Float // NSFontWeight / UIFontWeight values
	#partial switch text_weight(s.weight, bold) {
	case .Medium:   weight = 0.23
	case .Semibold: weight = 0.3
	case .Bold:     weight = 0.4
	}
	f := send(^NS.Object, Sys_Font, "systemFontOfSize:weight:", sz, weight)
	if s.italic {
		d := send(^NS.Object, f, "fontDescriptor")
		traits := send(u32, d, "symbolicTraits")
		d = send(^NS.Object, d, "fontDescriptorWithSymbolicTraits:", traits | 1)
		if italic := send(^NS.Object, Sys_Font, "fontWithDescriptor:size:", d, sz); italic != nil do f = italic
	}
	return f
}

@(private)
font_point_size :: proc "contextless" (f: ^NS.Object) -> f64 {
	return f64(send(NS.Float, f, "pointSize"))
}

// The sRGB components of an NSColor / UIColor (a dynamic color resolved for the current appearance).
@(private)
apple_color_components :: proc "contextless" (c: ^NS.Object) -> Color {
	c := c
	when !IS_IOS {
		space := send(^NS.Object, Color_Space, "sRGBColorSpace")
		c = send(^NS.Object, c, "colorUsingColorSpace:", space)
		if c == nil do return {}
	}
	r, g, b, a: NS.Float
	send(NS.BOOL, c, "getRed:green:blue:alpha:", &r, &g, &b, &a)
	return {f32(r), f32(g), f32(b), f32(a)}
}

// Height of a line of a label in `f`, in points (rounded up, plus a little room for the field).
@(private)
font_line_height :: proc "contextless" (f: ^NS.Object) -> NS.Float {
	asc, desc := send(NS.Float, f, "ascender"), send(NS.Float, f, "descender")
	return NS.Float(int(asc - desc + 0.999)) + 2
}
