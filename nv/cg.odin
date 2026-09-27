#+build darwin
package nv

// CoreGraphics drawing shared by the macOS and iOS canvas backends. Both hand drawRect: a
// top-left-origin CGContext (the macOS view is flipped), so the primitives are identical.
// Only system_font / canvas_color differ (NSFont / UIFont, NSColor / UIColor). The image decode
// (ImageIO → CGImage), draw_image, the download helpers and the loaded fonts (a CGFont from the
// bytes, sized into a CTFont, which is toll-free bridged to NSFont and UIFont) are shared the
// same way.

import "base:runtime"
import NS "core:sys/darwin/Foundation"

foreign import cg "system:CoreGraphics.framework"

CGContextRef :: distinct rawptr

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
	CTFontCreateWithGraphicsFont :: proc(font: CGFontRef, size: NS.Float, matrix: rawptr, attributes: rawptr) -> CTFontRef ---
}

@(default_calling_convention="c")
foreign corefoundation {
	CFRelease     :: proc(cf: rawptr) ---
	CFAutorelease :: proc(cf: rawptr) -> rawptr ---
}

// Fonts: the bytes become a CGFont, kept for the Font's lifetime; no CTFontManager registration
// is needed to use it directly.
@(private)
_font_load :: proc(f: ^Font, data: []u8) -> bool {
	ns_data := send(^NS.Data, NS.Data, "dataWithBytes:length:", raw_data(data), NS.UInteger(len(data)))
	provider := CGDataProviderCreateWithCFData(ns_data)
	if provider == nil do return false
	defer CGDataProviderRelease(provider)
	font := CGFontCreateWithDataProvider(provider)
	if font == nil do return false
	f.native = rawptr(font)
	return true
}

@(private)
_font_free :: proc(f: ^Font) {
	CGFontRelease(CGFontRef(f.native))
}

// An autoreleased CTFont of the loaded face at `size`, usable wherever an NSFont / UIFont is.
@(private)
ct_font :: proc "c" (f: ^Font, size: f64) -> ^NS.Object {
	return (^NS.Object)(CFAutorelease(rawptr(CTFontCreateWithGraphicsFont(CGFontRef(f.native), NS.Float(size), nil, nil))))
}

// The font for a widget or for draw_text: the loaded face, or the system font, bold when asked.
@(private)
text_font :: proc "c" (font: ^Font, size: f64, bold: bool) -> ^NS.Object {
	return font != nil ? ct_font(font, size) : system_font(size, bold)
}

// libdispatch: the _f variants take a function pointer instead of a block.
@(default_calling_convention="c")
foreign libsystem {
	_dispatch_main_q: u8 // dispatch_get_main_queue() is a macro for its address
	dispatch_async_f :: proc(queue: rawptr, ctx: rawptr, work: proc "c" (ctx: rawptr)) ---
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

// Downloads: runs on the worker thread (fetch_thread.odin), which has no autorelease pool of its
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

// NSString drawAtPoint:withAttributes: draws into the current context, which is the canvas's
// during drawRect:. "NSFont" / "NSColor" are the values of NSFontAttributeName /
// NSForegroundColorAttributeName in both AppKit and UIKit.
@(private)
_draw_text :: proc(p: ^Painter, text: string, x, y: f64, size: f64, color: Color, font: ^Font) {
	keys := [2]^NS.Object{NS.AT("NSFont"), NS.AT("NSColor")}
	values := [2]^NS.Object{text_font(font, size, false), canvas_color(color)}
	attrs := NS.Dictionary.dictionaryWithObjects(&values[0], &keys[0], 2)
	send(nil, ns_string(text), "drawAtPoint:withAttributes:", NS.Point{NS.Float(x), NS.Float(y)}, attrs)
}
