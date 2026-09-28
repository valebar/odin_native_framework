#+build darwin
package nv

// macOS canvas backend: an NSView subclass, NVCanvasView, registered at runtime. It is flipped
// (origin top-left), draws in drawRect: through cg.odin, and reports the left mouse button.

import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private) canvas_class: NS.Class

@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	cls := objc_class(&canvas_class, "NVCanvasView", "NSView", {
		{"drawRect:", auto_cast canvas_draw_rect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}"},
		{"isFlipped", auto_cast canvas_yes, "B@:"},
		{"acceptsFirstMouse:", auto_cast canvas_yes, "B@:@"},
		{"mouseDown:", auto_cast canvas_mouse_down, "v@:@"},
		{"mouseDragged:", auto_cast canvas_mouse_dragged, "v@:@"},
		{"mouseUp:", auto_cast canvas_mouse_up, "v@:@"},
	})
	obj := objc_alloc_with_handle(cls, h)
	view := send(^NS.View, (^NS.View)(obj), "initWithFrame:", NS.Rect{{0, 0}, {400, 300}})

	h.root = View(view)
	h.view = view
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	send(nil, (^NS.View)(h.view), "setNeedsDisplay:", NS.BOOL(true))
}

@(private)
system_font :: proc "c" (size: f64, bold: bool) -> ^NS.Object {
	return bold ? font_bold_system(NS.Float(size)) : font_system(NS.Float(size))
}

@(private)
canvas_color :: proc "c" (c: Color) -> ^NS.Object {
	return send(^NS.Color, NS.Color, "colorWithSRGBRed:green:blue:alpha:", NS.Float(c.r), NS.Float(c.g), NS.Float(c.b), NS.Float(c.a))
}

@(private)
canvas_yes :: proc "c" (_: NS.id, _: NS.SEL) -> NS.BOOL {
	return true
}

@(private)
canvas_draw_rect :: proc "c" (self: NS.id, _: NS.SEL, _: NS.Rect) {
	h := objc_handle(self, Canvas_Handle)
	context = h.ctx
	gc := send(^Graphics_Context, Graphics_Context, "currentContext")
	bounds := send(NS.Rect, (^NS.Object)(self), "bounds")
	canvas_draw_notify(h, send(rawptr, gc, "CGContext"), f64(bounds.size.width), f64(bounds.size.height))
}

@(private)
canvas_mouse :: proc "c" (self: NS.id, event: NS.id, kind: Pointer) {
	h := objc_handle(self, Canvas_Handle)
	context = h.ctx
	p := send(NS.Point, (^NS.Object)(self), "convertPoint:fromView:", send(NS.Point, (^NS.Object)(event), "locationInWindow"), NS.id(nil))
	canvas_pointer_notify(h, kind, f64(p.x), f64(p.y))
}

@(private) canvas_mouse_down    :: proc "c" (self: NS.id, _: NS.SEL, e: NS.id) { canvas_mouse(self, e, .Down) }
@(private) canvas_mouse_dragged :: proc "c" (self: NS.id, _: NS.SEL, e: NS.id) { canvas_mouse(self, e, .Move) }
@(private) canvas_mouse_up      :: proc "c" (self: NS.id, _: NS.SEL, e: NS.id) { canvas_mouse(self, e, .Up) }

}
