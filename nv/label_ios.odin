#+build darwin
package nv

// iOS label backend: a bold UILabel.

when IS_IOS {

@(private)
_label_init :: proc(h: ^Label_Handle) {
	label := ui_label_new() // owned
	ui_label_set_text(label, ns_string(h.label.text))
	ui_label_set_font(label, ui_font_bold_system(17))

	h.root = View(label)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	ui_label_set_text((^UI_Label)(h.root), ns_string(text))
}

}
