#+build darwin
package nv

// macOS canvas backend: an NSView subclass, NVCanvasView, registered at runtime. It is flipped
// (origin top-left), draws in drawRect: through cg.odin, and reports the left mouse button.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private) canvas_class: NS.Class

@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	if canvas_class == nil {
		canvas_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSView"), "NVCanvasView", 0)
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("drawRect:"), auto_cast canvas_draw_rect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("isFlipped"), auto_cast canvas_yes, "B@:")
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("acceptsFirstMouse:"), auto_cast canvas_yes, "B@:@")
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("mouseDown:"), auto_cast canvas_mouse_down, "v@:@")
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("mouseDragged:"), auto_cast canvas_mouse_dragged, "v@:@")
		NS.class_addMethod(canvas_class, intrinsics.objc_find_selector("mouseUp:"), auto_cast canvas_mouse_up, "v@:@")
		NS.objc_registerClassPair(canvas_class)
	}
	obj := NS.class_createInstance(canvas_class, size_of(^Canvas_Handle)) // owned, like alloc
	(^^Canvas_Handle)(NS.object_getIndexedIvars(obj))^ = h
	view := send(^NS.View, (^NS.View)(obj), "initWithFrame:", NS.Rect{{0, 0}, {400, 300}})

	h.root = View(view)
	h.view = view
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	send(nil, (^NS.View)(h.view), "setNeedsDisplay:", NS.BOOL(true))
}

@(private)
canvas_font :: proc "c" (size: f64) -> ^NS.Object {
	return font_system(NS.Float(size))
}

@(private)
canvas_color :: proc "c" (c: Color) -> ^NS.Object {
	return send(^NS.Color, NS.Color, "colorWithSRGBRed:green:blue:alpha:", NS.Float(c.r), NS.Float(c.g), NS.Float(c.b), NS.Float(c.a))
}

@(private)
canvas_handle_of :: #force_inline proc "c" (self: NS.id) -> ^Canvas_Handle {
	return (^^Canvas_Handle)(NS.object_getIndexedIvars(self))^
}

@(private)
canvas_yes :: proc "c" (_: NS.id, _: NS.SEL) -> NS.BOOL {
	return true
}

@(private)
canvas_draw_rect :: proc "c" (self: NS.id, _: NS.SEL, _: NS.Rect) {
	h := canvas_handle_of(self)
	context = h.ctx
	gc := send(^Graphics_Context, Graphics_Context, "currentContext")
	bounds := send(NS.Rect, (^NS.Object)(self), "bounds")
	canvas_draw_notify(h, send(rawptr, gc, "CGContext"), f64(bounds.size.width), f64(bounds.size.height))
}

@(private)
canvas_mouse :: proc "c" (self: NS.id, event: NS.id, kind: Pointer) {
	h := canvas_handle_of(self)
	context = h.ctx
	p := send(NS.Point, (^NS.Object)(self), "convertPoint:fromView:", send(NS.Point, (^NS.Object)(event), "locationInWindow"), NS.id(nil))
	canvas_pointer_notify(h, kind, f64(p.x), f64(p.y))
}

@(private) canvas_mouse_down    :: proc "c" (self: NS.id, _: NS.SEL, e: NS.id) { canvas_mouse(self, e, .Down) }
@(private) canvas_mouse_dragged :: proc "c" (self: NS.id, _: NS.SEL, e: NS.id) { canvas_mouse(self, e, .Move) }
@(private) canvas_mouse_up      :: proc "c" (self: NS.id, _: NS.SEL, e: NS.id) { canvas_mouse(self, e, .Up) }

}
