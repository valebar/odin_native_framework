#+build linux:default
#+private
package nv

// Linux dialog backend: the card is a GtkBox with the "nv-dialog" style class (app_linux.odin),
// centered as a child of the window's GtkOverlay; a modal dialog adds a full-size "nv-scrim" box
// under it, whose GtkGestureClick reports a press for a dismissible dialog. GTK4 delivers pointer
// events to the topmost widget under the pointer and bubbles them to its ancestors only, so the
// scrim blocks the page from the pointer by existing (and never sees a press on the card); the
// keyboard is blocked by making the stack and the header bar's buttons insensitive while a modal
// dialog is visible. The card and the scrim hold a reference of their own (ref_sink) that goes in an idle
// callback, since the close often runs inside one of the card's own buttons' "clicked" emission;
// the body's scope is retired by the idle after them, once the card and the body are finalized.
// A light dialog adds "nv-light" (white, dark text and controls, whatever the theme); a radius or a
// scrim colour of its own is a rule in a provider of its own (dialog_load_css).

import "core:fmt"
import "core:strings"

@(private)
_dialog_show :: proc(h: ^Dialog_Handle) {
	if h.dialog.modal {
		scrim := gtk_box_new(.Vertical, 0)
		gtk_widget_set_hexpand(scrim, true)
		gtk_widget_set_vexpand(scrim, true)
		gtk_widget_add_css_class(scrim, "nv-scrim")
		click := gtk_gesture_click_new()
		g_signal_connect(click, "pressed", rawptr(on_dialog_scrim_pressed), scrim)
		gtk_widget_add_controller(scrim, click)
		g_object_ref_sink(scrim)
		gtk_overlay_add_overlay(g_linux.overlay, scrim)
		h.scrim = scrim
	}

	card := gtk_box_new(.Vertical, 0)
	gtk_widget_add_css_class(card, "nv-dialog")
	if h.dialog.light do gtk_widget_add_css_class(card, "nv-light")
	dialog_load_css(h, card, (^GtkWidget)(h.scrim))
	// Fill: on_dialog_position places and sizes it. With any other alignment GTK would shrink the
	// card to its natural size inside that allocation (a canvas body's natural width is ~0).
	gtk_widget_set_halign(card, .Fill)
	gtk_widget_set_valign(card, .Fill)
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
on_dialog_scrim_pressed :: proc "c" (_: ^GtkEventController, _: i32, _, _: f64, scrim: gpointer) {
	dialog_scrim_notify(rawptr(scrim))
}

// The window overlay's child placement for a card: its width (the 16px margins included) is
// dialog_width, at most the window's, at least what the body needs; centred at the height for that
// width. A size request would be a minimum, which GtkOverlay never allocates below. The scrims
// keep the default (they fill the window).
@(private)
on_dialog_position :: proc "c" (overlay, widget: ^GtkWidget, alloc: ^GdkRectangle, _: gpointer) -> gboolean {
	h: ^Dialog_Handle
	for d in g_dialogs do if d.card == rawptr(widget) do h = d
	if h == nil do return false
	ow, oh := gtk_widget_get_width(overlay), gtk_widget_get_height(overlay)
	min_w, nat_w, min_h, nat_h: i32
	gtk_widget_measure(widget, .Horizontal, -1, &min_w, &nat_w, nil, nil)
	w := max(min_w, min(i32(dialog_width(h) + 0.5) + 32, ow))
	gtk_widget_measure(widget, .Vertical, w, &min_h, &nat_h, nil, nil)
	hh := max(min_h, min(nat_h, oh))
	alloc^ = {(ow - w) / 2, (oh - hh) / 2, w, hh}
	return true
}

@(private) g_dialog_seq: int

// A dialog with its own radius or scrim colour: a class "nv-d<N>" on the card and the scrim and a
// provider holding its rules, removed when the dialog's scope dies (after both widgets went).
@(private)
dialog_load_css :: proc(h: ^Dialog_Handle, card, scrim: ^GtkWidget) {
	if h.dialog.radius <= 0 && (scrim == nil || h.dialog.scrim.a == 0) do return
	g_dialog_seq += 1
	lc := new(Linux_Container, scope_allocator(h.scope))
	lc^ = {gtk_css_provider_new(), g_dialog_seq}
	scope_on_dispose_in(h.scope, container_dispose, lc)
	class := fmt.tprintf("nv-d%d", lc.seq)
	gtk_widget_add_css_class(card, strings.clone_to_cstring(class, context.temp_allocator))
	b := strings.builder_make(context.temp_allocator)
	if h.dialog.radius > 0 do fmt.sbprintf(&b, ".nv-dialog.%s {{ border-radius: %dpx; }}\n", class, int(dialog_radius(h, 12) + 0.5))
	if scrim != nil && h.dialog.scrim.a > 0 {
		gtk_widget_add_css_class(scrim, strings.clone_to_cstring(class, context.temp_allocator))
		fmt.sbprintf(&b, ".nv-scrim.%s {{ background-color: %s; }}\n", class, css_color(dialog_scrim(h)))
	}
	gtk_css_provider_load_from_data(lc.provider, strings.to_cstring(&b), -1)
	gtk_style_context_add_provider_for_display(gdk_display_get_default(), lc.provider, GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
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
	gtk_widget_set_sensitive(g_linux.menu, enabled)
	for b in g_linux.actions do gtk_widget_set_sensitive(b, enabled)
}
