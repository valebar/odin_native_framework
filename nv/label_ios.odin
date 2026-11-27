#+build darwin:ios
#+private
package nv

// iOS label backend: a UILabel in the system font (17pt, bold for a heading) changed by the style,
// with one line per "\n" (numberOfLines follows the text).

import "core:strings"
import NS "core:sys/darwin/Foundation"

@(private)
_label_init :: proc(h: ^Label_Handle) {
	label := objc_own(ui_label_new())
	ui_label_set_text(label, ns_string(h.label.text))
	ui_label_set_font(label, (^UI_Font)(apple_font(h.label.style, 17, h.label.heading)))
	if h.label.style.color.a > 0 do send(nil, label, "setTextColor:", canvas_color(h.label.style.color))
	ios_label_set_lines(label, h.label.text)

	h.root = View(label)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	ui_label_set_text((^UI_Label)(h.root), ns_string(text))
	ios_label_set_lines((^UI_Label)(h.root), text)
}

@(private)
ios_label_set_lines :: proc(label: ^UI_Label, text: string) {
	send(nil, label, "setNumberOfLines:", NS.Integer(strings.count(text, "\n") + 1))
}
