#+build windows
package nv

// Windows label backend: a Static in the title font when bold, else the message font, or in the
// given font and size (windows_font); label_new in flex_windows.odin is shared with the
// navigation bar's title.

import win "core:sys/windows"

@(private)
_label_init :: proc(h: ^Label_Handle) {
	h.root = View(label_new(h.label.text, g_windows.parking, win.WS_VISIBLE, windows_font(h.label.font, h.label.size, h.label.bold)))
}

// Lays out again only when the natural size changed (the app may set the text on every keystroke).
@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	label := win.HWND(h.root)
	before := measure(label)
	win.SetWindowTextW(label, wstr(text))
	if measure(label) != before do flex_relayout_ancestors(label)
}
