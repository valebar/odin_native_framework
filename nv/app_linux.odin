#+build linux:default
package nv

// Linux (GTK4) app backend. GtkApplication emits `activate` once GTK is ready, and that is
// where the root page is built (like UIApplicationMain on iOS). The app quits when the window
// closes. The window gets a GtkHeaderBar with a back button and the page's action buttons, and a
// GtkOverlay whose main child is a GtkStack holding the pages (nav_linux.odin); dialogs are
// overlay children (dialog_linux.odin), styled by the CSS below.

import "base:runtime"

@(private) g_linux: struct {
	ctx:    runtime.Context,
	window: ^GtkWidget,
	header: ^GtkWidget, // the title bar
	back:   ^GtkWidget, // header bar back button, visible on pushed pages
	menu:   ^GtkWidget, // header bar menu button, visible on a root page with a drawer (nav_shows_menu)
	actions: [dynamic]^GtkWidget, // the top page's action buttons, packed at the end of the header
	overlay: ^GtkWidget, // the window child: the stack below, dialogs on top
	stack:  ^GtkWidget, // one child per page
	dying:  [dynamic]Linux_Dying, // popped pages waiting for the slide animation to end
}

// GTK4's default theme has no card style (libadwaita's .card), so the dialog brings its own,
// from the theme's named colors.
@(private) NV_CSS :: `
.nv-scrim  { background-color: rgba(0, 0, 0, 0.4); }
.nv-dialog { background-color: @theme_base_color; color: @theme_fg_color; border: 1px solid @borders;
             border-radius: 12px; padding: 16px; box-shadow: 0 6px 24px rgba(0, 0, 0, 0.3); }
button.nv-fab { min-width: 56px; min-height: 56px; padding: 0; border-radius: 28px; color: white;
                background-image: none; background-color: @theme_selected_bg_color;
                box-shadow: 0 3px 8px rgba(0, 0, 0, 0.35); }
button.nv-fab:hover  { background-color: mix(@theme_selected_bg_color, white, 0.1); }
button.nv-fab.nv-extended { padding: 0 20px; }
.nv-tabbar { background-color: @theme_bg_color; border-top: 1px solid @borders; padding: 4px; }
.nv-tabbar button { padding: 4px 0; }
.nv-tabbar button:checked { background: none; color: @theme_selected_bg_color; }
`

@(private)
_run :: proc() {
	g_linux.ctx = context
	curl_global_init(CURL_GLOBAL_DEFAULT) // before any download thread (image_linux.odin)
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
	menu := gtk_button_new_from_icon_name(gtk_icon_names[.Menu])
	gtk_widget_set_visible(menu, false)
	g_signal_connect(menu, "clicked", rawptr(on_menu_clicked), nil)
	gtk_header_bar_pack_start(header, menu)
	g_linux.menu = menu
	gtk_window_set_titlebar(wnd, header)
	g_linux.header = header
	g_linux.back = back

	stack := gtk_stack_new()
	gtk_stack_set_transition_type(stack, .Slide_Left_Right)
	g_signal_connect(stack, "notify::transition-running", rawptr(on_transition_running), nil)
	overlay := gtk_overlay_new()
	gtk_overlay_set_child(overlay, stack)
	gtk_window_set_child(wnd, overlay)
	g_linux.overlay = overlay
	g_linux.stack = stack

	css := gtk_css_provider_new() // NV_CSS, the accent and the text styles (theme_linux.odin)
	g_theme_linux.css = css
	theme_css_reload()
	gtk_style_context_add_provider_for_display(gdk_display_get_default(), css, GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
	theme_start()

	nav_show_root()
	gtk_window_present(wnd)
}

@(private)
on_back_clicked :: proc "c" (_: ^GtkWidget, _: gpointer) {
	context = g_linux.ctx
	nav_back_notify()
}

@(private)
on_menu_clicked :: proc "c" (_: ^GtkWidget, _: gpointer) {
	context = g_linux.ctx
	nav_menu_notify()
}
