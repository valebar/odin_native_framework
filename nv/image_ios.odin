#+build darwin
package nv

// iOS image backend: a UIImageView subclass, NVImageView, registered at runtime only to report the
// natural size as its intrinsicContentSize. UIKit scales the image by contentMode and clips.

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
	cls := objc_class(&image_class, "NVImageView", "UIImageView", {
		{"intrinsicContentSize", auto_cast image_intrinsic_size, "{CGSize=dd}@:"},
	})
	obj := objc_alloc_with_handle(cls, h)
	view := objc_own(send(^UI_View, (^UI_View)(obj), "initWithFrame:", NS.Rect{}))
	send(nil, view, "setContentMode:", image_content_modes[h.image.fit])
	send(nil, view, "setClipsToBounds:", NS.BOOL(true))

	h.root = View(view)
	h.view = view
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
	s := image_natural_size(objc_handle(self, Image_Handle))
	return {NS.Float(s.x), NS.Float(s.y)}
}

}
