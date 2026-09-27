#+build linux:default
package nv

// Linux label backend: a left-aligned GtkLabel, with the "title-4" style class when bold.

import "core:strings"

@(private)
_label_init :: proc(h: ^Label_Handle) {
	label := gtk_label_new(strings.clone_to_cstring(h.label.text, context.temp_allocator))
	gtk_label_set_xalign(label, 0)
	if h.label.bold do gtk_widget_add_css_class(label, "title-4")

	h.root = View(label)
}

@(private)
_label_set_text :: proc(h: ^Label_Handle, text: string) {
	gtk_label_set_text((^GtkWidget)(h.root), strings.clone_to_cstring(text, context.temp_allocator))
}
