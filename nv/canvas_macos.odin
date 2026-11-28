#+build darwin:default
#+private
package nv

// macOS canvas backend: an NSView subclass, NVCanvasView, registered at runtime. It is flipped
// (origin top-left), draws in drawRect: through cg.odin, and reports the left mouse button, the
// scroll wheel / trackpad (scrollWheel:) and the trackpad's pinch (magnifyWithEvent:), each passed
// on up the responder chain without its callback.

import NS "core:sys/darwin/Foundation"
import AK "vendor:darwin/AppKit"

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
		{"scrollWheel:", auto_cast canvas_scroll_wheel, "v@:@"},
		{"magnifyWithEvent:", auto_cast canvas_magnify, "v@:@"},
	})
	obj := objc_alloc_with_handle(cls, h)
	view := objc_own(send(^AK.View, (^AK.View)(obj), "initWithFrame:", NS.Rect{{0, 0}, {400, 300}}))

	h.root = View(view)
	h.view = view
	apple_canvas_init(h)
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	if apple_canvas_park_redraw(h) do return
	send(nil, (^AK.View)(h.view), "setNeedsDisplay:", NS.BOOL(true))
}

@(private)
canvas_color :: proc "c" (c: Color) -> ^NS.Object {
	return send(^AK.Color, AK.Color, "colorWithSRGBRed:green:blue:alpha:", NS.Float(c.r), NS.Float(c.g), NS.Float(c.b), NS.Float(c.a))
}

@(private)
canvas_yes :: proc "c" (_: NS.id, _: NS.SEL) -> NS.BOOL {
	return true
}

@(private)
canvas_draw_rect :: proc "c" (self: NS.id, _: NS.SEL, _: NS.Rect) {
	h := objc_handle(self, Canvas_Handle)
	context = h.ctx
	NS.scoped_autoreleasepool() // the frame's strings, colors and fonts go with the frame
	gc := send(^Graphics_Context, Graphics_Context, "currentContext")
	bounds := send(NS.Rect, (^NS.Object)(self), "bounds")
	apple_canvas_draw(h, send(rawptr, gc, "CGContext"), f64(bounds.size.width), f64(bounds.size.height))
}

// NSEventModifierFlags: Shift, Control, Option, Command.
@(private)
canvas_mods :: proc "c" (event: NS.id) -> Modifiers {
	f := send(NS.UInteger, (^NS.Object)(event), "modifierFlags")
	m: Modifiers
	if f & (1 << 17) != 0 do m += {.Shift}
	if f & (1 << 18) != 0 do m += {.Ctrl}
	if f & (1 << 19) != 0 do m += {.Alt}
	if f & (1 << 20) != 0 do m += {.Cmd}
	return m
}

@(private)
canvas_location :: proc "c" (self: NS.id, event: NS.id) -> NS.Point {
	return send(NS.Point, (^NS.Object)(self), "convertPoint:fromView:", send(NS.Point, (^NS.Object)(event), "locationInWindow"), NS.id(nil))
}

@(private)
canvas_mouse :: proc "c" (self: NS.id, event: NS.id, kind: Pointer) {
	h := objc_handle(self, Canvas_Handle)
	context = h.ctx
	p := canvas_location(self, event)
	canvas_pointer_notify(h, kind, f64(p.x), f64(p.y), canvas_mods(event))
}

@(private) canvas_mouse_down    :: proc "c" (self: NS.id, _: NS.SEL, e: NS.id) { canvas_mouse(self, e, .Down) }
@(private) canvas_mouse_dragged :: proc "c" (self: NS.id, _: NS.SEL, e: NS.id) { canvas_mouse(self, e, .Move) }
@(private) canvas_mouse_up      :: proc "c" (self: NS.id, _: NS.SEL, e: NS.id) { canvas_mouse(self, e, .Up) }

// scrollingDelta is positive when the content should move down / right (towards the top / left),
// the opposite of on_scroll; without precise deltas (a mouse wheel) it counts lines.
@(private)
canvas_scroll_wheel :: proc "c" (self: NS.id, _: NS.SEL, event: NS.id) {
	h := objc_handle(self, Canvas_Handle)
	context = h.ctx
	if h.canvas.on_scroll == nil {
		next := send(^NS.Object, (^NS.Object)(self), "nextResponder")
		if next != nil do send(nil, next, "scrollWheel:", event)
		return
	}
	e := (^NS.Object)(event)
	dx, dy := f64(send(NS.Float, e, "scrollingDeltaX")), f64(send(NS.Float, e, "scrollingDeltaY"))
	precise := bool(send(NS.BOOL, e, "hasPreciseScrollingDeltas"))
	if !precise {
		dx, dy = dx * SCROLL_LINE, dy * SCROLL_LINE
	}
	p := canvas_location(self, event)
	canvas_scroll_notify(h, -dx, -dy, {f64(p.x), f64(p.y), true, precise}, canvas_mods(event))
}

// The trackpad's pinch: NSEventPhase Began 1, Changed 4, Ended 8, Cancelled 16; the scale adds up
// the magnifications, as Flutter's macOS embedder does.
@(private)
canvas_magnify :: proc "c" (self: NS.id, _: NS.SEL, event: NS.id) {
	h := objc_handle(self, Canvas_Handle)
	context = h.ctx
	if h.canvas.on_scale == nil {
		next := send(^NS.Object, (^NS.Object)(self), "nextResponder")
		if next != nil do send(nil, next, "magnifyWithEvent:", event)
		return
	}
	e := (^NS.Object)(event)
	phase := send(NS.UInteger, e, "phase")
	mag := f64(send(NS.Float, e, "magnification"))
	p := canvas_location(self, event)
	mods := canvas_mods(event)
	if phase & 1 != 0 {
		h.scale_from = {1, 0}
		canvas_scale_notify(h, .Down, 1, 1, f64(p.x), f64(p.y), mods)
	}
	if phase & (1 | 4) != 0 && mag != 0 {
		h.scale_from.x += mag
		canvas_scale_notify(h, .Move, h.scale_from.x, h.scale_from.x, f64(p.x), f64(p.y), mods)
	}
	if phase & (8 | 16) != 0 do canvas_scale_notify(h, .Up, h.scale_from.x, h.scale_from.x, f64(p.x), f64(p.y), mods)
}
