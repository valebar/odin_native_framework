#+build darwin:ios
#+private
package nv

// iOS canvas backend: a UIView subclass, NVCanvasView, registered at runtime. It draws in
// drawRect: through cg.odin and reports a single touch: the first one down (with on_scale the view
// takes several, and a UIPinchGestureRecognizer reports the pinch, leaving the touches to the view).
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
		{"nvPinch:", auto_cast canvas_pinch, "v@:@"},
	})
	obj := objc_alloc_with_handle(cls, h)
	view := objc_own(send(^UI_View, (^UI_View)(obj), "initWithFrame:", NS.Rect{}))
	send(nil, view, "setContentMode:", UI_VIEW_CONTENT_MODE_REDRAW) // redraw on resize instead of stretching
	// Transparent like the other backends: an opaque UIView is not cleared before drawRect:, so
	// undrawn pixels show black or the previous frame instead of what is behind it.
	send(nil, view, "setOpaque:", NS.BOOL(false))
	// CG queues the draw calls and rasterizes them off the main thread, instead of on it after drawRect:.
	send(nil, send(^NS.Object, view, "layer"), "setDrawsAsynchronously:", NS.BOOL(true))

	h.root = View(view)
	h.view = view
	apple_canvas_init(h)
	if h.canvas.on_scale != nil {
		send(nil, view, "setMultipleTouchEnabled:", NS.BOOL(true))
		pinch := send(^NS.Object, objc_class_object("UIPinchGestureRecognizer"), "alloc")
		pinch = send(^NS.Object, pinch, "initWithTarget:action:", (^NS.Object)(view), intrinsics.objc_find_selector("nvPinch:"))
		send(nil, pinch, "setCancelsTouchesInView:", NS.BOOL(false))
		send(nil, view, "addGestureRecognizer:", pinch)
		pinch->release() // the view owns it
	}
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

// The first touch down is the pointer; the others are a pinch's.
@(private)
canvas_touch :: proc "c" (self: NS.id, touches: NS.id, kind: Pointer) {
	h := objc_handle(self, Canvas_Handle)
	context = h.ctx
	c := (^Apple_Canvas)(h.extra)
	set := (^NS.Object)(touches)
	touch: ^NS.Object
	if kind == .Down {
		if c.touch != nil do return
		touch = send(^NS.Object, set, "anyObject")
		c.touch = touch
	} else {
		if c.touch == nil || !bool(send(NS.BOOL, set, "containsObject:", c.touch)) do return
		touch = c.touch
		if kind == .Up do c.touch = nil
	}
	p := send(NS.Point, touch, "locationInView:", self)
	canvas_pointer_notify(h, kind, f64(p.x), f64(p.y))
}

// UIPinchGestureRecognizer: state Began 1, Changed 2, Ended 3, Cancelled 4; the vertical scale
// from its two touches' span against the one it began with.
@(private)
canvas_pinch :: proc "c" (self: NS.id, _: NS.SEL, rec: NS.id) {
	h := objc_handle(self, Canvas_Handle)
	context = h.ctx
	r := (^NS.Object)(rec)
	state := send(NS.Integer, r, "state")
	scale := f64(send(NS.Float, r, "scale"))
	p := send(NS.Point, r, "locationInView:", self)
	span := 0.0
	if send(NS.UInteger, r, "numberOfTouches") >= 2 {
		a := send(NS.Point, r, "locationOfTouch:inView:", NS.UInteger(0), self)
		b := send(NS.Point, r, "locationOfTouch:inView:", NS.UInteger(1), self)
		span = abs(f64(b.y - a.y))
	}
	switch state {
	case 1:
		h.scale_from = {span, 0}
		canvas_scale_notify(h, .Down, 1, 1, f64(p.x), f64(p.y))
	case 2:
		v := h.scale_from.x > 0 && span > 0 ? span / h.scale_from.x : 1
		canvas_scale_notify(h, .Move, scale, v, f64(p.x), f64(p.y))
	case 3, 4, 5:
		canvas_scale_notify(h, .Up, scale, 1, f64(p.x), f64(p.y))
	}
}

@(private) canvas_touches_began :: proc "c" (self: NS.id, _: NS.SEL, t: NS.id, _: NS.id) { canvas_touch(self, t, .Down) }
@(private) canvas_touches_moved :: proc "c" (self: NS.id, _: NS.SEL, t: NS.id, _: NS.id) { canvas_touch(self, t, .Move) }
@(private) canvas_touches_ended :: proc "c" (self: NS.id, _: NS.SEL, t: NS.id, _: NS.id) { canvas_touch(self, t, .Up) }
