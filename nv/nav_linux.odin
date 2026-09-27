#+build linux:default
package nv

// Linux navigation backend: pages are children of a GtkStack that slides between them, the
// window title is the page title (shown by the header bar), the header bar's back button appears
// on pushed pages and the top page's actions are buttons packed at the header bar's end.

import "core:strings"

// GTK icon names by Icon; "" shows the title as text.
@(private) gtk_icon_names := [Icon]cstring{
	.None     = "",
	.Add      = "list-add-symbolic",
	.Edit     = "document-edit-symbolic",
	.Delete   = "user-trash-symbolic",
	.Search   = "system-search-symbolic",
	.Share    = "emblem-shared-symbolic",
	.Settings = "emblem-system-symbolic",
	.Refresh  = "view-refresh-symbolic",
	.Done     = "emblem-ok-symbolic",
	.Info     = "dialog-information-symbolic",
	.More     = "view-more-symbolic",
	.Close    = "window-close-symbolic",
}

@(private)
_nav_push :: proc(e: ^Page_Handle) {
	root := (^GtkWidget)(e.root)
	gtk_stack_add_child(g_linux.stack, root) // the stack owns the page from here on
	gtk_stack_set_visible_child(g_linux.stack, root) // a later child: slides left
	nav_update_chrome(e)
}

@(private)
_nav_pop :: proc(top, below: ^Page_Handle) -> bool {
	gtk_stack_set_visible_child(g_linux.stack, (^GtkWidget)(below.root)) // an earlier child: slides right
	nav_update_chrome(below)
	return true
}

// Removing a page from the stack while it slides out would cut the animation short (and could
// finalize a button inside its own "clicked" emission), so it waits for the transition to end.
@(private)
_nav_release :: proc(e: ^Page_Handle) {
	root := (^GtkWidget)(e.root)
	if gtk_stack_get_transition_running(g_linux.stack) {
		append(&g_linux.dying, root)
	} else {
		gtk_stack_remove(g_linux.stack, root) // drops the stack's reference: the page tree is finalized
	}
}

// The header bar shows the top page only; a lower page's changes are picked up when it is shown again.
@(private)
_nav_title_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do nav_set_title(e)
}

@(private)
_nav_actions_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do nav_rebuild_actions(e)
}

@(private)
nav_update_chrome :: proc(e: ^Page_Handle) {
	nav_set_title(e)
	gtk_widget_set_visible(g_linux.back, len(g_nav) > 1)
	nav_rebuild_actions(e)
}

@(private)
nav_set_title :: proc(e: ^Page_Handle) {
	gtk_window_set_title(g_linux.window, strings.clone_to_cstring(e.page.title, context.temp_allocator))
}

@(private)
nav_rebuild_actions :: proc(e: ^Page_Handle) {
	// The header bar drops its reference on remove, so each button holds one of its own (ref_sink at
	// creation) until an idle callback: this often runs inside one of these buttons' own "clicked"
	// emission, and a finalized button is not allowed there.
	for b in g_linux.actions {
		gtk_header_bar_remove(g_linux.header, b)
		g_idle_add(unref_widget_idle, b)
	}
	clear(&g_linux.actions)

	// pack_end packs right to left, so the declared order is packed reversed to read left to right.
	#reverse for h in e.actions {
		icon := gtk_icon_names[h.action.icon]
		title := strings.clone_to_cstring(h.action.title, context.temp_allocator)
		b: ^GtkWidget
		if icon != "" {
			b = gtk_button_new_from_icon_name(icon)
			gtk_widget_set_tooltip_text(b, title)
		} else {
			b = gtk_button_new_with_label(title)
		}
		g_object_ref_sink(b)
		g_signal_connect(b, "clicked", rawptr(on_action_clicked), h)
		gtk_widget_set_sensitive(b, dialog_top_modal() == nil) // a modal dialog keeps the bar disabled
		gtk_header_bar_pack_end(g_linux.header, b)
		append(&g_linux.actions, b)
	}
}

@(private)
on_action_clicked :: proc "c" (_: ^GtkWidget, user: gpointer) {
	h := (^Action_Handle)(user)
	context = h.ctx
	action_notify(h)
}

@(private)
unref_widget_idle :: proc "c" (data: gpointer) -> gboolean {
	g_object_unref(data)
	return G_SOURCE_REMOVE
}

@(private)
on_transition_running :: proc "c" (_: ^GObject, _: rawptr, _: gpointer) {
	context = g_linux.ctx
	if gtk_stack_get_transition_running(g_linux.stack) do return
	for w in g_linux.dying do gtk_stack_remove(g_linux.stack, w)
	clear(&g_linux.dying)
}
