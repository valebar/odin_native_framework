#+build darwin
package nv

// iOS canvas backend: a UIView subclass, NVCanvasView, registered at runtime. It draws in
// drawRect: through cg.odin and reports a single touch (UIView ignores extra touches by default).

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private) canvas_class: NS.Class

@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	if canvas_class == nil {
		canvas_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("UIView"), "NVCanvasView", 0)
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("drawRect:"), auto_cast canvas_draw_rect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("touchesBegan:withEvent:"), auto_cast canvas_touches_began, "v@:@@")
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("touchesMoved:withEvent:"), auto_cast canvas_touches_moved, "v@:@@")
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("touchesEnded:withEvent:"), auto_cast canvas_touches_ended, "v@:@@")
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("touchesCancelled:withEvent:"), auto_cast canvas_touches_ended, "v@:@@")
		NS.objc_registerClassPair(canvas_class)
	}
	obj := NS.class_createInstance(canvas_class, size_of(^Canvas_Handle)) // owned, like alloc
	(^^Canvas_Handle)(NS.object_getIndexedIvars(obj))^ = h
	view := send(^UI_View, (^UI_View)(obj), "initWithFrame:", NS.Rect{})
	send(nil, view, "setContentMode:", UI_VIEW_CONTENT_MODE_REDRAW) // redraw on resize instead of stretching

	h.root = View(view)
	h.view = view
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	send(nil, (^UI_View)(h.view), "setNeedsDisplay")
}

@(private)
canvas_font :: proc "c" (size: f64) -> ^NS.Object {
	return send(^UI_Font, UI_Font, "systemFontOfSize:", NS.Float(size))
}

@(private)
canvas_color :: proc "c" (c: Color) -> ^NS.Object {
	return send(^UI_Color, UI_Color, "colorWithRed:green:blue:alpha:", NS.Float(c.r), NS.Float(c.g), NS.Float(c.b), NS.Float(c.a))
}

@(private)
canvas_handle_of :: #force_inline proc "c" (self: NS.id) -> ^Canvas_Handle {
	return (^^Canvas_Handle)(NS.object_getIndexedIvars(self))^
}

@(private)
canvas_draw_rect :: proc "c" (self: NS.id, _: NS.SEL, _: NS.Rect) {
	h := canvas_handle_of(self)
	context = h.ctx
	bounds := send(NS.Rect, (^NS.Object)(self), "bounds")
	canvas_draw_notify(h, rawptr(UIGraphicsGetCurrentContext()), f64(bounds.size.width), f64(bounds.size.height))
}

@(private)
canvas_touch :: proc "c" (self: NS.id, touches: NS.id, kind: Pointer) {
	h := canvas_handle_of(self)
	context = h.ctx
	touch := send(^NS.Object, (^NS.Object)(touches), "anyObject")
	p := send(NS.Point, touch, "locationInView:", self)
	canvas_pointer_notify(h, kind, f64(p.x), f64(p.y))
}

@(private) canvas_touches_began :: proc "c" (self: NS.id, _: NS.SEL, t: NS.id, _: NS.id) { canvas_touch(self, t, .Down) }
@(private) canvas_touches_moved :: proc "c" (self: NS.id, _: NS.SEL, t: NS.id, _: NS.id) { canvas_touch(self, t, .Move) }
@(private) canvas_touches_ended :: proc "c" (self: NS.id, _: NS.SEL, t: NS.id, _: NS.id) { canvas_touch(self, t, .Up) }

}
