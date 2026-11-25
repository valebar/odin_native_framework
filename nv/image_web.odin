#+build js
package nv

// Web image backend. The browser decodes asynchronously (createImageBitmap for the canvas, a blob
// URL for <img>), so a Bitmap's size comes from the file's header (image_size, imagesize.odin) and
// the pixels follow: a canvas that drew the bitmap before it was decoded draws again once it is.
// The widget is an <img> filling its view with `object-fit` for the Fit; the view's natural size
// is image_natural_size (--nv-w / --nv-h, nv.css), so the <img> itself sizes nothing.

@(private)
_bitmap_decode :: proc(b: ^Bitmap, data: []u8) -> bool {
	w, h, ok := image_size(data)
	if !ok do return false
	b.width, b.height = w, h
	b.native = rawptr(uintptr(js_bitmap(data)))
	return true
}

@(private)
_bitmap_free :: proc(b: ^Bitmap) {
	js_bitmap_release(i32(uintptr(b.native)))
}

@(private)
_image_init :: proc(h: ^Image_Handle) {
	view := web_create("div", "nv-image nv-fw nv-fh")
	img := web_create("img")
	js_attr(img, "alt", "")
	js_attr(img, "draggable", "false")
	js_append(view, img)
	h.root = web_view(view)
	h.view = rawptr(uintptr(img))
	_image_set_bitmap(h)
}

@(private)
_image_set_bitmap :: proc(h: ^Image_Handle) {
	s := image_natural_size(h)
	view := web_id(h.root)
	js_style(view, "--nv-w", web_px(s.x))
	js_style(view, "--nv-h", web_px(s.y))
	bitmap: i32 = h.bitmap != nil ? i32(uintptr(h.bitmap.native)) : 0
	js_image_set(Web_Id(uintptr(h.view)), bitmap, i32(h.image.fit))
}
