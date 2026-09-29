#+build darwin
package nv

// iOS canvas backend: a UIView subclass, NVCanvasView, registered at runtime. It draws in
// drawRect: through cg.odin and reports a single touch (UIView ignores extra touches by default).

import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private) canvas_class: NS.Class

@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	cls := objc_class(&canvas_class, "NVCanvasView", "UIView", {
		{"drawRect:", auto_cast canvas_draw_rect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}"},
		{"touchesBegan:withEvent:", auto_cast canvas_touches_began, "v@:@@"},
		{"touchesMoved:withEvent:", auto_cast canvas_touches_moved, "v@:@@"},
		{"touchesEnded:withEvent:", auto_cast canvas_touches_ended, "v@:@@"},
		{"touchesCancelled:withEvent:", auto_cast canvas_touches_ended, "v@:@@"},
	})
	obj := objc_alloc_with_handle(cls, h)
	view := objc_own(send(^UI_View, (^UI_View)(obj), "initWithFrame:", NS.Rect{}))
	send(nil, view, "setContentMode:", UI_VIEW_CONTENT_MODE_REDRAW) // redraw on resize instead of stretching

	h.root = View(view)
	h.view = view
	apple_canvas_init(h)
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	send(nil, (^UI_View)(h.view), "setNeedsDisplay")
}

@(private)
canvas_color :: proc "c" (c: Color) -> ^NS.Object {
	return send(^UI_Color, UI_Color, "colorWithRed:green:blue:alpha:", NS.Float(c.r), NS.Float(c.g), NS.Float(c.b), NS.Float(c.a))
}

@(private)
canvas_draw_rect :: proc "c" (self: NS.id, _: NS.SEL, _: NS.Rect) {
	h := objc_handle(self, Canvas_Handle)
	context = h.ctx
	NS.scoped_autoreleasepool() // the frame's strings, colors and fonts go with the frame
	bounds := send(NS.Rect, (^NS.Object)(self), "bounds")
	canvas_draw_notify(h, rawptr(UIGraphicsGetCurrentContext()), f64(bounds.size.width), f64(bounds.size.height))
}

@(private)
canvas_touch :: proc "c" (self: NS.id, touches: NS.id, kind: Pointer) {
	h := objc_handle(self, Canvas_Handle)
	context = h.ctx
	touch := send(^NS.Object, (^NS.Object)(touches), "anyObject")
	p := send(NS.Point, touch, "locationInView:", self)
	canvas_pointer_notify(h, kind, f64(p.x), f64(p.y))
}

@(private) canvas_touches_began :: proc "c" (self: NS.id, _: NS.SEL, t: NS.id, _: NS.id) { canvas_touch(self, t, .Down) }
@(private) canvas_touches_moved :: proc "c" (self: NS.id, _: NS.SEL, t: NS.id, _: NS.id) { canvas_touch(self, t, .Move) }
@(private) canvas_touches_ended :: proc "c" (self: NS.id, _: NS.SEL, t: NS.id, _: NS.id) { canvas_touch(self, t, .Up) }

}
