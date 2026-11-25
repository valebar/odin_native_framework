#+build darwin:default
package nv

// macOS app backend: one NSWindow whose content view is a container holding the pages
// (nav_macos.odin) and the dialogs (dialog_macos.odin), and whose title bar carries the back
// button and the page's action buttons.

import "base:runtime"
import NS "core:sys/darwin/Foundation"
import AK "vendor:darwin/AppKit"

@(private) nav_target_class: NS.Class // NVNavTarget, the back button's and the actions' target

@(private) g_macos: struct {
	ctx:    runtime.Context,
	window: ^AK.Window,
	content: ^AK.View, // the window's content view: pages and dialogs are its subviews
	back:   ^Titlebar_Accessory_View_Controller, // owned for the run; detached on the root page
	back_attached: bool,
	menu:   ^Titlebar_Accessory_View_Controller, // owned for the run; attached on a root page with a drawer (nav_shows_menu)
	menu_attached: bool,
	actions: ^Titlebar_Accessory_View_Controller, // trailing; the top page's action buttons, nil when it has none
	nav_target: NS.id, // NVNavTarget: receives the back button's and the actions' clicks
}

@(private)
_run :: proc() {
	g_macos.ctx = context
	app := AK.Application.sharedApplication()
	app->setActivationPolicy(.Regular)
	delegate := AK.application_delegate_register_and_alloc({
		applicationShouldTerminateAfterLastWindowClosed = proc(_: ^AK.Application) -> bool { return true },
	}, "NVAppDelegate", context)
	app->setDelegate(delegate)
	theme_start()

	wnd := AK.Window.alloc()->initWithContentRect(
		{{0, 0}, {400, 600}},
		{.Resizable, .Closable, .Titled, .Miniaturizable},
		.Buffered,
		false,
	)
	g_macos.window = wnd
	content := content_view_new({{0, 0}, {400, 600}})
	wnd->setContentView(content)
	content->release() // the window owns it
	g_macos.content = content
	nav_install_back_button()
	callback_enter()
	nav_show_root()
	callback_exit()
	wnd->center()
	wnd->makeKeyAndOrderFront(nil)

	app->activateIgnoringOtherApps(true)
	app->run()
}
