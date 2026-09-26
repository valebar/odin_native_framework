#+build linux:default
package nv

// Linux input backend: a GtkEntry. GtkEditable's "changed" reports every edit (including
// gtk_editable_set_text, muted by h.silent) and "activate" is Enter.

import "core:strings"

@(private)
_input_init :: proc(h: ^Input_Handle) {
	entry := gtk_entry_new()
	gtk_editable_set_text(entry, strings.clone_to_cstring(h.input.text, context.temp_allocator))
	if h.input.placeholder != "" {
		gtk_entry_set_placeholder_text(entry, strings.clone_to_cstring(h.input.placeholder, context.temp_allocator))
	}
	g_signal_connect(entry, "changed", rawptr(on_input_changed), h)
	g_signal_connect(entry, "activate", rawptr(on_input_activate), h)
	free_all(context.temp_allocator)

	h.root = View(entry)
	h.field = entry
}

@(private)
_input_text :: proc(h: ^Input_Handle, allocator := context.allocator) -> string {
	return strings.clone_from_cstring(gtk_editable_get_text((^GtkWidget)(h.field)), allocator)
}

@(private)
_input_set_text :: proc(h: ^Input_Handle, text: string) {
	gtk_editable_set_text((^GtkWidget)(h.field), strings.clone_to_cstring(text, context.temp_allocator))
	free_all(context.temp_allocator)
}

@(private)
on_input_changed :: proc "c" (_: ^GtkWidget, user: gpointer) {
	h := (^Input_Handle)(user)
	context = h.ctx
	input_notify(h, h.input.on_change)
}

@(private)
on_input_activate :: proc "c" (_: ^GtkWidget, user: gpointer) {
	h := (^Input_Handle)(user)
	context = h.ctx
	input_notify(h, h.input.on_submit)
}
