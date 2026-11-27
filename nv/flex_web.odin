#+build js
#+private
package nv

// Web Row / Column backend: a flexbox (.nv-row / .nv-col in nv.css) whose cross axis stretches. A
// flex child grows by its weight from a zero basis, so the weights are exact; the others keep their
// natural size. `gap` is the spacing, and a hidden child (display: none) takes neither space nor gap.

import "core:fmt"

@(private)
_flex_create :: proc(f: Flex) -> View {
	box := web_create("div", f.axis == .Horizontal ? "nv-row" : "nv-col")
	if f.spacing > 0 do js_style(box, "gap", web_px(f.spacing))
	for c in f.children {
		child := web_id(c.view)
		if c.flex > 0 {
			js_style(child, "flex", fmt.tprintf("%d 1 0px", c.flex))
			js_class(child, "nv-grow", true)
		} else {
			js_style(child, "flex", "none")
		}
		js_append(box, child)
	}
	return web_view(box)
}
