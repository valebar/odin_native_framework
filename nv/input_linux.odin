#+build linux:default
#+private
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
	style_widget(entry, h.input.style)
	input_keyboard(entry, h.input)
	g_signal_connect(entry, "changed", rawptr(on_input_changed), h)
	g_signal_connect(entry, "activate", rawptr(on_input_activate), h)

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

// The purpose and hints only steer an on-screen keyboard (GTK filters nothing); .Text sets none.
@(private)
input_keyboard :: proc(entry: ^GtkWidget, i: Input) {
	numeric := i.keyboard == .Number || i.keyboard == .Signed_Number || i.keyboard == .Decimal
	if i.secure {
		gtk_entry_set_visibility(entry, false)
		gtk_entry_set_input_purpose(entry, numeric ? GTK_INPUT_PURPOSE_PIN : GTK_INPUT_PURPOSE_PASSWORD)
		return
	}
	#partial switch i.keyboard {
	case .Sentences:     gtk_entry_set_input_hints(entry, GTK_INPUT_HINT_UPPERCASE_SENTENCES)
	case .Number:        gtk_entry_set_input_purpose(entry, GTK_INPUT_PURPOSE_DIGITS)
	case .Signed_Number, .Decimal: gtk_entry_set_input_purpose(entry, GTK_INPUT_PURPOSE_NUMBER)
	}
}

// A GtkEntry selects all on grab_focus; without select_all the caret goes to the end instead.
@(private)
_input_focus :: proc(h: ^Input_Handle, select_all: bool) {
	entry := (^GtkWidget)(h.field)
	if select_all {
		gtk_widget_grab_focus(entry)
		gtk_editable_select_region(entry, 0, -1)
	} else {
		gtk_entry_grab_focus_without_selecting(entry)
		gtk_editable_set_position(entry, -1)
	}
}
