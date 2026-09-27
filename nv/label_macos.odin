#+build darwin
package nv

// macOS label backend: an NSTextField label in the system font, bold when asked.

when !IS_IOS {

@(private)
_label_init :: proc(h: ^Label_Handle) {
	label := text_field_label(ns_string(h.label.text)) // autoreleased; *_create returns owned views
	text_field_set_font(label, h.label.bold ? font_bold_system(17) : font_system(15))
	label->retain()

	h.root = View(label)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	text_field_set_string((^Text_Field)(h.root), ns_string(text))
}

}
