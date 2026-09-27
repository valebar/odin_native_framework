#+build windows
package nv

// Windows label backend: a Static in the title font (label_new in flex_windows.odin, shared with
// the navigation bar's title).

import win "core:sys/windows"

@(private)
_label_init :: proc(h: ^Label_Handle) {
	h.root = View(label_new(h.label.text, g_windows.parking, win.WS_VISIBLE))
}

// Lays out again only when the natural size changed (the app may set the text on every keystroke).
@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	label := win.HWND(h.root)
	before := measure(label)
	win.SetWindowTextW(label, wstr(text))
	if measure(label) != before do flex_relayout_ancestors(label)
}
