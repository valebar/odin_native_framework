#+build darwin
package nv

// macOS label backend: an NSTextField label in the system font (bold 17pt for a heading, 15pt
// otherwise) changed by the style.

import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private)
_label_init :: proc(h: ^Label_Handle) {
	label := text_field_label(ns_string(h.label.text)) // autoreleased; *_create returns owned views
	text_field_set_font(label, (^NS_Font)(apple_font(h.label.style, h.label.heading ? 17 : 15, h.label.heading)))
	if h.label.style.color.a > 0 do text_field_set_text_color(label, (^NS.Color)(canvas_color(h.label.style.color)))
	objc_own(label)->retain()

	h.root = View(label)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	text_field_set_string((^Text_Field)(h.root), ns_string(text))
}

}
