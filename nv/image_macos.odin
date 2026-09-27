#+build darwin
package nv

// macOS image backend: an NSView subclass, NVImageView, registered at runtime. NSImageView has no
// aspect-fill mode, so the view draws the CGImage itself (cg.odin) at image_fit_rect; it is
// flipped like the canvas, and its intrinsicContentSize is the natural size.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private) image_class: NS.Class

@(private)
_image_init :: proc(h: ^Image_Handle) {
	if image_class == nil {
		image_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSView"), "NVImageView", 0)
		NS.class_addMethod(image_class, intrinsics.objc_find_selector("drawRect:"), auto_cast image_draw_rect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
		NS.class_addMethod(image_class, intrinsics.objc_find_selector("isFlipped"), auto_cast canvas_yes, "B@:")
		NS.class_addMethod(image_class, intrinsics.objc_find_selector("intrinsicContentSize"), auto_cast image_intrinsic_size, "{CGSize=dd}@:")
		NS.objc_registerClassPair(image_class)
	}
	obj := NS.class_createInstance(image_class, size_of(^Image_Handle)) // owned, like alloc
	(^^Image_Handle)(NS.object_getIndexedIvars(obj))^ = h
	view := send(^NS.View, (^NS.View)(obj), "initWithFrame:", NS.Rect{})

	h.root = View(view)
	h.view = send(^NS.View, view, "retain") // the handle's own reference: a download may land after its page popped
}

@(private)
_image_set_bitmap :: proc(h: ^Image_Handle) {
	view := (^NS.View)(h.view)
	send(nil, view, "invalidateIntrinsicContentSize")
	send(nil, view, "setNeedsDisplay:", NS.BOOL(true))
}

@(private)
image_handle_of :: #force_inline proc "c" (self: NS.id) -> ^Image_Handle {
	return (^^Image_Handle)(NS.object_getIndexedIvars(self))^
}

@(private)
image_draw_rect :: proc "c" (self: NS.id, _: NS.SEL, _: NS.Rect) {
	h := image_handle_of(self)
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
	s := image_natural_size(image_handle_of(self))
	return {NS.Float(s.x), NS.Float(s.y)}
}

}
