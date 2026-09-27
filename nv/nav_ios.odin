#+build darwin
package nv

// iOS navigation backend: every page is a UIViewController pushed on the UINavigationController
// from app_ios.odin, which provides the navigation bar, the back button and the swipe gesture.
// An NVNavDelegate keeps the Odin stack in sync with pops the user made.

import NS "core:sys/darwin/Foundation"

when IS_IOS {

// Returns an owned (+1) controller showing the page's view, pinned to the safe area: a stack
// view doesn't inset itself like a table view does, so it would slide under the navigation bar.
@(private)
page_controller_new :: proc(e: ^Nav_Page) -> ^UI_View_Controller {
	container := ui_view_new()
	ui_view_set_background_color(container, ui_color_system_background())
	ui_view_pin_to_safe_area((^UI_View)(e.root), container)
	vc := ui_view_controller_new()
	ui_view_controller_set_view(vc, container)
	container->release()
	ui_view_controller_set_title(vc, ns_string(e.page.title))
	return vc
}

@(private)
_nav_push :: proc(e: ^Nav_Page) {
	vc := page_controller_new(e)
	ui_navigation_controller_push(g_app.nav, vc, true)
	vc->release()
}

// UIKit refuses a pop while another transition is still animating and returns nil.
@(private)
_nav_pop :: proc(top, below: ^Nav_Page) -> bool {
	return ui_navigation_controller_pop(g_app.nav, true) != nil
}

// The page's container view still holds the root through the pop animation.
@(private)
_nav_release :: proc(e: ^Nav_Page) {
	send(nil, (^NS.Object)(e.root), "release")
}

// navigationController:didShowViewController:animated:. After a programmatic pop() the Odin
// stack already matches the controller count; after a back button or swipe it is one longer,
// and a cancelled swipe shows the same controller again with equal counts. So the stack is
// trimmed to the count rather than popped on every call (didShow, not willShow: the latter
// also fires for a swipe that is then cancelled).
@(private)
nav_did_show :: proc "c" (self: NS.id, _: NS.SEL, nav: NS.id, _: NS.id, _: NS.BOOL) {
	context = g_app.ctx
	callback_enter()
	defer callback_exit()
	count := int(ui_navigation_controller_view_controllers((^UI_Navigation_Controller)(nav))->count())
	for len(g_nav) > count do nav_system_pop()
}

}
