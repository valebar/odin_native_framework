#+build js
package nv

// Web button backend: a <button>, in the accent color when the theme sets one (as on GTK).

@(private)
_button_init :: proc(h: ^Button_Handle) {
	button := web_create("button", g_theme.accent.a > 0 ? "nv-button nv-accent" : "nv-button")
	js_attr(button, "type", "button")
	js_text(button, h.button.title)
	web_style_text(button, h.button.style)
	js_listen(button, .Button, h, 0)
	h.root = web_view(button)
	h.control = rawptr(uintptr(button))
}

@(private)
_button_set_title :: proc(h: ^Button_Handle, title: string) {
	js_text(web_id(h.root), title)
}
