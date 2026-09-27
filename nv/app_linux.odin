#+build linux:default
package nv

// Linux (GTK4) app backend. GtkApplication emits `activate` once GTK is ready, and that is
// where the root page is built (like UIApplicationMain on iOS). The app quits when the window
// closes. The window gets a GtkHeaderBar with a back button and a GtkStack holding the pages
// (nav_linux.odin).

import "base:runtime"
import "core:strings"

@(private) g_linux: struct {
	ctx:    runtime.Context,
	window: ^GtkWidget,
	back:   ^GtkWidget, // header bar back button, visible on pushed pages
	stack:  ^GtkWidget, // one child per page
	dying:  [dynamic]^GtkWidget, // popped pages waiting for the slide animation to end
}

@(private)
_run :: proc() {
	g_linux.ctx = context
	app := gtk_application_new(nil, G_APPLICATION_DEFAULT_FLAGS)
	g_signal_connect(app, "activate", rawptr(on_activate), nil)
	g_application_run(app, 0, nil)
	g_object_unref(app)
}

@(private)
on_activate :: proc "c" (app: ^GtkApplication, _: gpointer) {
	context = g_linux.ctx
	callback_enter()
	defer callback_exit()

	wnd := gtk_application_window_new(app)
	gtk_window_set_default_size(wnd, 400, 600)
	g_linux.window = wnd

	header := gtk_header_bar_new() // shows the window title
	back := gtk_button_new_from_icon_name("go-previous-symbolic")
	gtk_widget_set_visible(back, false)
	g_signal_connect(back, "clicked", rawptr(on_back_clicked), nil)
	gtk_header_bar_pack_start(header, back)
	gtk_window_set_titlebar(wnd, header)
	g_linux.back = back

	stack := gtk_stack_new()
	gtk_stack_set_transition_type(stack, .Slide_Left_Right)
	g_signal_connect(stack, "notify::transition-running", rawptr(on_transition_running), nil)
	gtk_window_set_child(wnd, stack)
	g_linux.stack = stack

	nav_show_root()
	gtk_window_present(wnd)
}

@(private)
on_back_clicked :: proc "c" (_: ^GtkWidget, _: gpointer) {
	context = g_linux.ctx
	callback_enter()
	defer callback_exit()
	pop()
}
