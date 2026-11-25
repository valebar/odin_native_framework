#+build darwin:ios
package nv

// iOS canvas backend: a UIView subclass, NVCanvasView, registered at runtime. It draws in
// drawRect: through cg.odin and reports a single touch (UIView ignores extra touches by default).
// There is no wheel: on_scroll is never called, and a list drags through on_pointer.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(private) canvas_class: NS.Class

@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	cls := objc_class(&canvas_class, "NVCanvasView", "UIView", {
		{"drawRect:", auto_cast canvas_draw_rect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}"},
		{"nvFrame:", auto_cast canvas_link_frame, "v@:@"},
		{"touchesBegan:withEvent:", auto_cast canvas_touches_began, "v@:@@"},
		{"touchesMoved:withEvent:", auto_cast canvas_touches_moved, "v@:@@"},
		{"touchesEnded:withEvent:", auto_cast canvas_touches_ended, "v@:@@"},
		{"touchesCancelled:withEvent:", auto_cast canvas_touches_ended, "v@:@@"},
	})
	obj := objc_alloc_with_handle(cls, h)
	view := objc_own(send(^UI_View, (^UI_View)(obj), "initWithFrame:", NS.Rect{}))
	send(nil, view, "setContentMode:", UI_VIEW_CONTENT_MODE_REDRAW) // redraw on resize instead of stretching
	// CG queues the draw calls and rasterizes them off the main thread, instead of on it after drawRect:.
	send(nil, send(^NS.Object, view, "layer"), "setDrawsAsynchronously:", NS.BOOL(true))

	h.root = View(view)
	h.view = view
	apple_canvas_init(h)
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	if apple_canvas_park_redraw(h) do return
	send(nil, (^UI_View)(h.view), "setNeedsDisplay")
}

// A redraw asked for inside on_draw waits for the next frame of a CADisplayLink, which also asks
// a ProMotion display for 120 Hz (UIKit alone commits at 60). The run loop owns the link until
// apple_canvas_dispose invalidates it.
@(private)
canvas_link_resume :: proc "c" (h: ^Canvas_Handle) {
	c := (^Apple_Canvas)(h.extra)
	if c.link != nil {
		send(nil, c.link, "setPaused:", NS.BOOL(false))
		return
	}
	c.link = send(^NS.Object, CA_Display_Link, "displayLinkWithTarget:selector:", (^NS.Object)(h.view), intrinsics.objc_find_selector("nvFrame:"))
	send(nil, c.link, "setPreferredFrameRateRange:", CA_Frame_Rate_Range{80, 120, 120})
	send(nil, c.link, "addToRunLoop:forMode:", send(^NS.Object, NS.RunLoop, "mainRunLoop"), NS.RunLoopCommonModes)
}

// Pauses on the first frame with nothing to redraw (also a canvas that is no longer displayed).
@(private)
canvas_link_frame :: proc "c" (self: NS.id, _: NS.SEL, link: NS.id) {
	c := (^Apple_Canvas)(objc_handle(self, Canvas_Handle).extra)
	if c.redraw_queued {
		c.redraw_queued = false
		send(nil, (^NS.Object)(self), "setNeedsDisplay")
	} else {
		send(nil, (^NS.Object)(link), "setPaused:", NS.BOOL(true))
	}
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
	apple_canvas_draw(h, rawptr(UIGraphicsGetCurrentContext()), f64(bounds.size.width), f64(bounds.size.height))
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
