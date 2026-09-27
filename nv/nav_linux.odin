#+build linux:default
package nv

// Linux navigation backend: pages are children of a GtkStack that slides between them, the
// window title is the page title (shown by the header bar) and the header bar's back button
// appears on pushed pages.

import "core:strings"

@(private)
_nav_push :: proc(e: ^Nav_Page) {
	root := (^GtkWidget)(e.root)
	gtk_stack_add_child(g_linux.stack, root) // the stack owns the page from here on
	gtk_stack_set_visible_child(g_linux.stack, root) // a later child: slides left
	nav_update_chrome(e)
}

@(private)
_nav_pop :: proc(top, below: ^Nav_Page) -> bool {
	gtk_stack_set_visible_child(g_linux.stack, (^GtkWidget)(below.root)) // an earlier child: slides right
	nav_update_chrome(below)
	return true
}

// Removing a page from the stack while it slides out would cut the animation short (and could
// finalize a button inside its own "clicked" emission), so it waits for the transition to end.
@(private)
_nav_release :: proc(e: ^Nav_Page) {
	root := (^GtkWidget)(e.root)
	if gtk_stack_get_transition_running(g_linux.stack) {
		append(&g_linux.dying, root)
	} else {
		gtk_stack_remove(g_linux.stack, root) // drops the stack's reference: the page tree is finalized
	}
}

@(private)
nav_update_chrome :: proc(e: ^Nav_Page) {
	gtk_window_set_title(g_linux.window, strings.clone_to_cstring(e.page.title, context.temp_allocator))
	gtk_widget_set_visible(g_linux.back, len(g_nav) > 1)
}

@(private)
on_transition_running :: proc "c" (_: ^GObject, _: rawptr, _: gpointer) {
	context = g_linux.ctx
	if gtk_stack_get_transition_running(g_linux.stack) do return
	for w in g_linux.dying do gtk_stack_remove(g_linux.stack, w)
	clear(&g_linux.dying)
}
