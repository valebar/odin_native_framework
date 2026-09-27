#+build darwin
package nv

// iOS label backend: a UILabel in the system font (17pt, bold as a heading) or the given one.

when IS_IOS {

@(private)
_label_init :: proc(h: ^Label_Handle) {
	label := ui_label_new() // owned
	ui_label_set_text(label, ns_string(h.label.text))
	size := h.label.size != 0 ? h.label.size : 17
	ui_label_set_font(label, (^UI_Font)(text_font(h.label.font, size, h.label.bold)))

	h.root = View(label)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	ui_label_set_text((^UI_Label)(h.root), ns_string(text))
}

}
