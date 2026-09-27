#+build darwin
package nv

// iOS image backend: a UIImageView subclass, NVImageView, registered at runtime only to report the
// natural size as its intrinsicContentSize. UIKit scales the image by contentMode and clips.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private) image_class: NS.Class

// UIViewContentMode, indexed by Fit.
@(private) image_content_modes := [Fit]NS.Integer{
	.Contain = 1, // ScaleAspectFit
	.Cover   = 2, // ScaleAspectFill
	.Fill    = 0, // ScaleToFill
}

@(private)
_image_init :: proc(h: ^Image_Handle) {
	if image_class == nil {
		image_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("UIImageView"), "NVImageView", 0)
		NS.class_addMethod(image_class, intrinsics.objc_find_selector("intrinsicContentSize"), auto_cast image_intrinsic_size, "{CGSize=dd}@:")
		NS.objc_registerClassPair(image_class)
	}
	obj := NS.class_createInstance(image_class, size_of(^Image_Handle)) // owned, like alloc
	(^^Image_Handle)(NS.object_getIndexedIvars(obj))^ = h
	view := send(^UI_View, (^UI_View)(obj), "initWithFrame:", NS.Rect{})
	send(nil, view, "setContentMode:", image_content_modes[h.image.fit])
	send(nil, view, "setClipsToBounds:", NS.BOOL(true))

	h.root = View(view)
	h.view = send(^UI_View, view, "retain") // the handle's own reference: a download may land after its page popped
	_image_set_bitmap(h)
}

@(private)
_image_set_bitmap :: proc(h: ^Image_Handle) {
	view := (^UI_View)(h.view)
	image: ^NS.Object
	if h.bitmap != nil do image = send(^NS.Object, UI_Image, "imageWithCGImage:", h.bitmap.native)
	send(nil, view, "setImage:", image)
	send(nil, view, "invalidateIntrinsicContentSize")
}

@(private)
image_intrinsic_size :: proc "c" (self: NS.id, _: NS.SEL) -> NS.Size {
	s := image_natural_size((^^Image_Handle)(NS.object_getIndexedIvars(self))^)
	return {NS.Float(s.x), NS.Float(s.y)}
}

}
