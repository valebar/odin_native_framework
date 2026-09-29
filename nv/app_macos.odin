#+build darwin
package nv

// macOS app backend: one NSWindow whose content view is a container holding the pages
// (nav_macos.odin) and the dialogs (dialog_macos.odin), and whose title bar carries the back
// button and the page's action buttons.

import "base:runtime"
import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private) nav_target_class: NS.Class // NVNavTarget, the back button's and the actions' target

@(private) g_macos: struct {
	ctx:    runtime.Context,
	window: ^NS.Window,
	content: ^NS.View, // the window's content view: pages and dialogs are its subviews
	back:   ^Titlebar_Accessory_View_Controller, // hidden on the root page
	actions: ^Titlebar_Accessory_View_Controller, // trailing; the top page's action buttons, nil when it has none
	nav_target: NS.id, // NVNavTarget: receives the back button's and the actions' clicks
}

@(private)
_run :: proc() {
	g_macos.ctx = context
	app := NS.Application.sharedApplication()
	app->setActivationPolicy(.Regular)
	delegate := NS.application_delegate_register_and_alloc({
		applicationShouldTerminateAfterLastWindowClosed = proc(_: ^NS.Application) -> NS.BOOL { return true },
	}, "NVAppDelegate", context)
	app->setDelegate(delegate)
	theme_start()

	wnd := NS.Window.alloc()->initWithContentRect(
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
	nav_install_back_button(wnd)
	callback_enter()
	nav_show_root()
	callback_exit()
	wnd->center()
	wnd->makeKeyAndOrderFront(nil)

	app->activateIgnoringOtherApps(true)
	app->run()
}

}
