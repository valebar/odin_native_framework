#+build darwin
package nv

// iOS navigation backend: every page is a UIViewController pushed on the UINavigationController
// from app_ios.odin, which provides the navigation bar, the back button and the swipe gesture.
// The page's actions are the controller's right bar button items. An NVNavDelegate keeps the
// Odin stack in sync with pops the user made.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when IS_IOS {

// Returns an owned (+1) controller showing the page's view, pinned to the safe area: a stack
// view doesn't inset itself like a table view does, so it would slide under the navigation bar.
@(private)
page_controller_new :: proc(e: ^Page_Handle) -> ^UI_View_Controller {
	container := ui_view_new()
	ui_view_set_background_color(container, ui_color_system_background())
	ui_view_pin_to_safe_area((^UI_View)(e.root), container)
	vc := ui_view_controller_new()
	ui_view_controller_set_view(vc, container)
	container->release()
	ui_view_controller_set_title(vc, ns_string(e.page.title))
	ios_apply_actions(vc, e)
	e.native = vc // owned by the navigation controller
	return vc
}

// rightBarButtonItems lays out from the right, so the declared order goes in reversed. The old
// items may be inside their own action right now, so their array is autoreleased before it is
// replaced.
@(private)
ios_apply_actions :: proc(vc: ^UI_View_Controller, e: ^Page_Handle) {
	nav_item := ui_view_controller_navigation_item(vc)
	if old := ui_navigation_item_right_items(nav_item); old != nil {
		send(nil, old, "retain")
		send(nil, old, "autorelease")
	}
	items := make([]^NS.Object, len(e.actions), context.temp_allocator)
	for h, i in e.actions {
		action := intrinsics.objc_find_selector("nvAction:")
		title := ns_string(h.action.title)
		item: ^UI_Bar_Button_Item
		if name := sf_symbol_names[h.action.icon]; name != "" {
			item = ui_bar_button_item_with_image(ui_image_system(ns_string(name)), g_app.nav_target, action)
			ui_bar_button_item_set_accessibility_label(item, title)
		} else {
			item = ui_bar_button_item_with_title(title, g_app.nav_target, action)
		}
		object_set_tag(item, NS.Integer(uintptr(h)))
		items[len(items) - 1 - i] = item
	}
	array := array_with_objects(raw_data(items), len(items)) // retains the items
	for item in items do send(nil, item, "release")
	ui_navigation_item_set_right_items(nav_item, array)
}

// Every page has its own controller, so a lower page can be updated too.
@(private)
_nav_title_changed :: proc(e: ^Page_Handle) {
	if vc := (^UI_View_Controller)(e.native); vc != nil do ui_view_controller_set_title(vc, ns_string(e.page.title))
}

@(private)
_nav_actions_changed :: proc(e: ^Page_Handle) {
	if vc := (^UI_View_Controller)(e.native); vc != nil do ios_apply_actions(vc, e)
}

@(private)
_nav_push :: proc(e: ^Page_Handle) {
	vc := page_controller_new(e)
	ui_navigation_controller_push(g_app.nav, vc, true)
	vc->release()
}

// UIKit refuses a pop while another transition is still animating and returns nil.
@(private)
_nav_pop :: proc(top, below: ^Page_Handle) -> bool {
	return ui_navigation_controller_pop(g_app.nav, true) != nil
}

// The page's container view still holds the root through the pop animation.
@(private)
_nav_release :: proc(e: ^Page_Handle) {
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
