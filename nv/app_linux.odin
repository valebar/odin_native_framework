#+build linux:default
package nv

// Linux (GTK4) app backend. GtkApplication emits `activate` once GTK is ready, and that is
// where `build` runs (like UIApplicationMain on iOS). The app quits when the window closes.

import "base:runtime"
import "core:strings"

@(private) g_linux: struct {
	title: string,
	build: Build_Proc,
	user:  rawptr,
	ctx:   runtime.Context,
}

@(private)
_run :: proc(title: string, build: Build_Proc, user: rawptr) {
	g_linux = {title, build, user, context}
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
	gtk_window_set_title(wnd, strings.clone_to_cstring(g_linux.title, context.temp_allocator))
	gtk_window_set_default_size(wnd, 400, 600)
	gtk_window_set_child(wnd, (^GtkWidget)(g_linux.build(g_linux.user)))
	gtk_window_present(wnd)
}
