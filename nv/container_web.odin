#+build js
package nv

// Web container backend: the root (.nv-container) is the margin box, its padding the margin; the
// box inside (.nv-box) has the border, the background, the corners and the padding and clips the
// child, which fills it. A fixed width / height is the margin box's natural size (--nv-w / --nv-h,
// nv.css), which the cross axis of a Row / Column still stretches.

import "core:fmt"

@(private)
_container_init :: proc(h: ^Container_Handle) {
	c := &h.container
	root := web_create("div", "nv-container")
	m := c.margin
	if m != {} do js_style(root, "padding", web_insets(m))
	if c.width > 0 {
		js_class(root, "nv-fw", true)
		js_style(root, "--nv-w", web_px(c.width + m.left + m.right))
	}
	if c.height > 0 {
		js_class(root, "nv-fh", true)
		js_style(root, "--nv-h", web_px(c.height + m.top + m.bottom))
	}

	box := web_create("div", "nv-box nv-col")
	if c.border_width > 0 do js_style(box, "border", fmt_border(c.border_width, c.border_color))
	if c.radius > 0 do js_style(box, "border-radius", web_px(c.radius))
	if c.padding != {} do js_style(box, "padding", web_insets(c.padding))
	js_append(root, box)
	h.box = rawptr(uintptr(box))
	h.root = web_view(root)
	_container_set_color(h)
	if c.child != nil do js_append(box, web_id(c.child))
}

@(private)
_container_set_color :: proc(h: ^Container_Handle) {
	c := h.container.color
	js_style(Web_Id(uintptr(h.box)), "background-color", c.a > 0 ? web_color(c) : "transparent")
}

@(private)
fmt_border :: proc(width: f64, color: Color) -> string {
	return fmt.tprintf("%s solid %s", web_px(width), web_color(color))
}
