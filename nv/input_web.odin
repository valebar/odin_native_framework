#+build js
package nv

// Web input backend: an <input type=text>. Its `input` event reports the user's edits only (a
// value set from code fires nothing, h.silent is moot) and Enter submits.

import "core:strings"

@(private)
_input_init :: proc(h: ^Input_Handle) {
	field := web_create("input", "nv-input")
	js_attr(field, "type", "text")
	js_attr(field, "enterkeyhint", "done")
	js_attr(field, "autocomplete", "off")
	if h.input.placeholder != "" do js_attr(field, "placeholder", h.input.placeholder)
	js_set_value(field, h.input.text)
	web_style_text(field, h.input.style)
	js_listen(field, .Input_Change, h, 0)
	js_listen(field, .Input_Submit, h, 0)
	h.root = web_view(field)
	h.field = rawptr(uintptr(field))
}

@(private)
_input_text :: proc(h: ^Input_Handle, allocator := context.allocator) -> string {
	field := Web_Id(uintptr(h.field))
	buf: [256]u8
	n := js_value(field, buf[:])
	if n <= len(buf) do return strings.clone(string(buf[:n]), allocator)
	big := make([]u8, n, allocator)
	js_value(field, big)
	return string(big)
}

@(private)
_input_set_text :: proc(h: ^Input_Handle, text: string) {
	js_set_value(Web_Id(uintptr(h.field)), text)
}
