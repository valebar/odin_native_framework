#+build darwin
package nv

// CoreGraphics drawing shared by the macOS and iOS canvas backends. Both hand drawRect: a
// top-left-origin CGContext (the macOS view is flipped), so the primitives are identical.
// Only canvas_font / canvas_color differ (NSFont / UIFont, NSColor / UIColor).

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
_draw_text :: proc(p: ^Painter, text: string, x, y: f64, size: f64, color: Color) {
	keys := [2]^NS.Object{NS.AT("NSFont"), NS.AT("NSColor")}
	values := [2]^NS.Object{canvas_font(size), canvas_color(color)}
	attrs := NS.Dictionary.dictionaryWithObjects(&values[0], &keys[0], 2)
	send(nil, ns_string(text), "drawAtPoint:withAttributes:", NS.Point{NS.Float(x), NS.Float(y)}, attrs)
}
