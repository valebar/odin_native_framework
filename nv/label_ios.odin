#+build darwin
package nv

// iOS label backend: a UILabel in the system font (17pt, bold for a heading) changed by the style.

when IS_IOS {

@(private)
_label_init :: proc(h: ^Label_Handle) {
	label := objc_own(ui_label_new())
	ui_label_set_text(label, ns_string(h.label.text))
	ui_label_set_font(label, (^UI_Font)(apple_font(h.label.style, 17, h.label.heading)))
	if h.label.style.color.a > 0 do send(nil, label, "setTextColor:", canvas_color(h.label.style.color))

	h.root = View(label)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	ui_label_set_text((^UI_Label)(h.root), ns_string(text))
}

}
