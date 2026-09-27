#+build darwin
package nv

// macOS app backend: one NSWindow whose content view is the top page (nav_macos.odin) and whose
// title bar carries the back button.

import "base:runtime"
import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private) g_macos: struct {
	ctx:    runtime.Context,
	window: ^NS.Window,
	back:   ^Titlebar_Accessory_View_Controller, // hidden on the root page
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

	wnd := NS.Window.alloc()->initWithContentRect(
		{{0, 0}, {400, 600}},
		{.Resizable, .Closable, .Titled, .Miniaturizable},
		.Buffered,
		false,
	)
	g_macos.window = wnd
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
