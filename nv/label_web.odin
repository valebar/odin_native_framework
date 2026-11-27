#+build js
#+private
package nv

// Web label backend: a div centering one line of text (a span, cut with an ellipsis) in the box a
// Row / Column stretches it to, as the other toolkits do, with the heading class for a heading and
// the style inline over it.

@(private)
_label_init :: proc(h: ^Label_Handle) {
	label := js_label(h.label.heading ? "nv-label nv-heading" : "nv-label")
	scope_on_dispose(web_release, rawptr(uintptr(label)))
	js_text(label, h.label.text)
	web_style_text(label, h.label.style)
	h.root = web_view(label)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	js_text(web_id(h.root), text)
}
