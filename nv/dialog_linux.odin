#+build linux:default
package nv

// Linux dialog backend: the card is a GtkBox with the "nv-dialog" style class (app_linux.odin),
// centered as a child of the window's GtkOverlay; a modal dialog adds a full-size "nv-scrim" box
// under it. GTK4 delivers pointer events to the topmost widget under the pointer and bubbles them
// to its ancestors only, so the scrim blocks the page from the pointer by existing; the keyboard
// is blocked by making the stack and the header bar's buttons insensitive while a modal dialog is
// visible. The card and the scrim hold a reference of their own (ref_sink) that goes in an idle
// callback, since the close often runs inside one of the card's own buttons' "clicked" emission;
// the body's scope is retired by the idle after them, once the card and the body are finalized.

@(private)
_dialog_show :: proc(h: ^Dialog_Handle) {
	if h.dialog.modal {
		scrim := gtk_box_new(.Vertical, 0)
		gtk_widget_set_hexpand(scrim, true)
		gtk_widget_set_vexpand(scrim, true)
		gtk_widget_add_css_class(scrim, "nv-scrim")
		g_object_ref_sink(scrim)
		gtk_overlay_add_overlay(g_linux.overlay, scrim)
		h.scrim = scrim
	}

	card := gtk_box_new(.Vertical, 0)
	gtk_widget_add_css_class(card, "nv-dialog")
	gtk_widget_set_halign(card, .Center)
	gtk_widget_set_valign(card, .Center)
	gtk_widget_set_size_request(card, 320, -1)
	gtk_widget_set_margin_start(card, 16)
	gtk_widget_set_margin_end(card, 16)
	gtk_box_append(card, (^GtkWidget)(h.body))
	g_object_ref_sink(card)
	gtk_overlay_add_overlay(g_linux.overlay, card) // after the scrim: above it
	h.card = card

	linux_dialog_apply_modal()
	// A non-modal dialog leaves the focus where it is: the page stays in use.
	if h.dialog.modal && len(h.buttons) > 0 do gtk_widget_grab_focus((^GtkWidget)(h.buttons[0].handle.root))
}

@(private)
_dialog_close :: proc(h: ^Dialog_Handle) {
	for w in ([]rawptr{h.card, h.scrim}) {
		if w == nil do continue
		gtk_overlay_remove_overlay(g_linux.overlay, (^GtkWidget)(w))
		g_idle_add(unref_widget_idle, w)
	}
	g_idle_add(dialog_retire_idle, h.scope) // same priority: runs after the unrefs
	linux_dialog_apply_modal()
}

@(private)
dialog_retire_idle :: proc "c" (data: gpointer) -> gboolean {
	context = g_linux.ctx
	scope_retire((^Scope)(data))
	return G_SOURCE_REMOVE
}

@(private)
_dialog_set_hidden :: proc(h: ^Dialog_Handle, hidden: bool) {
	gtk_widget_set_visible((^GtkWidget)(h.card), !hidden)
	if h.scrim != nil do gtk_widget_set_visible((^GtkWidget)(h.scrim), !hidden)
	linux_dialog_apply_modal()
}

// The page stack and the header bar's buttons follow the top page's modal state.
@(private)
linux_dialog_apply_modal :: proc() {
	enabled := gboolean(dialog_top_modal() == nil)
	gtk_widget_set_sensitive(g_linux.stack, enabled)
	gtk_widget_set_sensitive(g_linux.back, enabled)
	for b in g_linux.actions do gtk_widget_set_sensitive(b, enabled)
}
