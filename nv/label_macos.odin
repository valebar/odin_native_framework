#+build darwin
package nv

// macOS label backend: an NSTextField label in the system font (15pt, or bold 17pt as a
// heading) or the given one.

when !IS_IOS {

@(private)
_label_init :: proc(h: ^Label_Handle) {
	label := text_field_label(ns_string(h.label.text)) // autoreleased; *_create returns owned views
	size := h.label.size != 0 ? h.label.size : (h.label.bold ? 17 : 15)
	text_field_set_font(label, (^NS_Font)(text_font(h.label.font, size, h.label.bold)))
	objc_own(label)->retain()

	h.root = View(label)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	text_field_set_string((^Text_Field)(h.root), ns_string(text))
}

}
