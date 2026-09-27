#+build linux:default
package nv

// Linux button backend: a GtkButton with a text label and its "clicked" signal. A custom font
// goes on the label child, which gtk_button_set_label keeps.

import "core:strings"

@(private)
_button_init :: proc(h: ^Button_Handle) {
	button := gtk_button_new_with_label(strings.clone_to_cstring(h.button.title, context.temp_allocator))
	if attrs := pango_font_attrs(h.button.font, h.button.size); attrs != nil {
		gtk_label_set_attributes(gtk_button_get_child(button), attrs)
		pango_attr_list_unref(attrs)
	}
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
