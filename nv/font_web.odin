#+build js
#+private
package nv

// Web font backend: a FontFace from the bytes, added to document.fonts under a family of its own
// (nv-font-<id>, so it never mixes with an installed face of the same name), with the face's
// weight and slant as its descriptors. The browser loads it asynchronously: widgets reflow by
// themselves once it is ready, and nv.js redraws every canvas.

@(private)
_font_load :: proc(f: ^Font, data: []u8) -> bool {
	id := js_font(data, i32(f.weight), b32(f.italic))
	if id == 0 do return false
	f.native = rawptr(uintptr(id))
	return true
}

@(private)
_font_free :: proc(f: ^Font) {
	js_font_release(i32(uintptr(f.native)))
}
