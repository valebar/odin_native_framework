#+build darwin
package nv

import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private)
_run :: proc(title: string, build: Build_Proc, user: rawptr) {
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
	wnd->setTitle(ns_string(title))
	root := (^NS.View)(build(user))
	view_set_autoresizing(root, RESIZE_WIDTH | RESIZE_HEIGHT)
	wnd->setContentView(root)
	wnd->center()
	wnd->makeKeyAndOrderFront(nil)

	app->activateIgnoringOtherApps(true)
	app->run()
}

}
