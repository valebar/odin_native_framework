#+build windows
#+private
package nv

// Windows label backend: a Static in the title font for a heading, else the message font (label_new
// in flex_windows.odin, shared with the navigation bar's title), changed by the style. The handle
// sits in the Static's GWLP_USERDATA for ctlcolor_static, which gives it its color. A text with a
// "\n" makes it SS_LEFTNOWORDWRAP instead: SS_ENDELLIPSIS draws one line only.

import "core:strings"
import win "core:sys/windows"

@(private)
_label_init :: proc(h: ^Label_Handle) {
	font := style_font(h.label.style, h.label.heading ? g_windows.title : g_windows.font)
	label := label_new(h.label.text, g_windows.parking, win.WS_VISIBLE, font)
	windows_label_lines(label, h.label.text)
	win.SetWindowLongPtrW(label, win.GWLP_USERDATA, win.LONG_PTR(uintptr(h)))
	h.root = View(label)
}

// Lays out again only when the natural size changed (the app may set the text on every keystroke).
@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	label := win.HWND(h.root)
	before := measure(label)
	windows_label_lines(label, text) // before the text's repaint
	win.SetWindowTextW(label, wstr(text))
	if measure(label) != before do flex_relayout_ancestors(label)
}

// One line with an ellipsis, or several lines clipped at the edge.
@(private)
windows_label_lines :: proc(label: win.HWND, text: string) {
	style := win.GetWindowLongPtrW(label, win.GWL_STYLE) &~ win.LONG_PTR(win.SS_TYPEMASK | win.SS_ENDELLIPSIS)
	style |= win.LONG_PTR(strings.contains(text, "\n") ? win.SS_LEFTNOWORDWRAP : win.SS_LEFT | win.SS_ENDELLIPSIS)
	win.SetWindowLongPtrW(label, win.GWL_STYLE, style)
}
