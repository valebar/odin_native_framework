#+build darwin
package nv

// macOS image backend: an NSView subclass, NVImageView, registered at runtime. NSImageView has no
// aspect-fill mode, so the view draws the CGImage itself (cg.odin) at image_fit_rect; it is
// flipped like the canvas, and its intrinsicContentSize is the natural size.

import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private) image_class: NS.Class

@(private)
_image_init :: proc(h: ^Image_Handle) {
	cls := objc_class(&image_class, "NVImageView", "NSView", {
		{"drawRect:", auto_cast image_draw_rect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}"},
		{"isFlipped", auto_cast canvas_yes, "B@:"},
		{"intrinsicContentSize", auto_cast image_intrinsic_size, "{CGSize=dd}@:"},
	})
	obj := objc_alloc_with_handle(cls, h)
	view := objc_own(send(^NS.View, (^NS.View)(obj), "initWithFrame:", NS.Rect{}))

	h.root = View(view)
	h.view = view
}

@(private)
_image_set_bitmap :: proc(h: ^Image_Handle) {
	view := (^NS.View)(h.view)
	send(nil, view, "invalidateIntrinsicContentSize")
	send(nil, view, "setNeedsDisplay:", NS.BOOL(true))
}

@(private)
image_draw_rect :: proc "c" (self: NS.id, _: NS.SEL, _: NS.Rect) {
	h := objc_handle(self, Image_Handle)
	if h.bitmap == nil do return
	context = h.ctx
	gc := send(^Graphics_Context, Graphics_Context, "currentContext")
	bounds := send(NS.Rect, (^NS.Object)(self), "bounds")
	r := image_fit_rect(h.image.fit, h.bitmap, f64(bounds.size.width), f64(bounds.size.height))
	p := Painter{native = send(rawptr, gc, "CGContext")}
	_draw_image(&p, h.bitmap, r[0], r[1], r[2], r[3])
}

@(private)
image_intrinsic_size :: proc "c" (self: NS.id, _: NS.SEL) -> NS.Size {
	s := image_natural_size(objc_handle(self, Image_Handle))
	return {NS.Float(s.x), NS.Float(s.y)}
}

}
