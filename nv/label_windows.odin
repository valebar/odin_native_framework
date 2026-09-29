#+build windows
package nv

// Windows label backend: a Static in the title font for a heading, else the message font (label_new
// in flex_windows.odin, shared with the navigation bar's title), changed by the style. The handle
// sits in the Static's GWLP_USERDATA for ctlcolor_static, which gives it its color.

import win "core:sys/windows"

@(private)
_label_init :: proc(h: ^Label_Handle) {
	font := style_font(h.label.style, h.label.heading ? g_windows.title : g_windows.font)
	label := label_new(h.label.text, g_windows.parking, win.WS_VISIBLE, font)
	win.SetWindowLongPtrW(label, win.GWLP_USERDATA, win.LONG_PTR(uintptr(h)))
	h.root = View(label)
}

// Lays out again only when the natural size changed (the app may set the text on every keystroke).
@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	label := win.HWND(h.root)
	before := measure(label)
	win.SetWindowTextW(label, wstr(text))
	if measure(label) != before do flex_relayout_ancestors(label)
}
