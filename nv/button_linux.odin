#+build linux:default
package nv

// Linux button backend: a GtkButton with a text label and its "clicked" signal.

import "core:strings"

@(private)
_button_init :: proc(h: ^Button_Handle) {
	button := gtk_button_new_with_label(strings.clone_to_cstring(h.button.title, context.temp_allocator))
	g_signal_connect(button, "clicked", rawptr(on_button_clicked), h)

	h.root = View(button)
	h.control = button
}

@(private)
_button_set_title :: proc(h: ^Button_Handle, title: string) {
	gtk_button_set_label((^GtkWidget)(h.control), strings.clone_to_cstring(title, context.temp_allocator))
}

@(private)
on_button_clicked :: proc "c" (_: ^GtkWidget, user: gpointer) {
	h := (^Button_Handle)(user)
	context = h.ctx
	button_notify(h)
}
