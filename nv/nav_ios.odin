#+build darwin:ios
package nv

// iOS navigation backend: every page is an NVPageController (a UIViewController) pushed on the
// UINavigationController from app_ios.odin, which provides the navigation bar, the back button and
// the swipe gesture. The page's actions are the controller's right bar button items. The
// controller's didMoveToParentViewController: keeps the Odin stack in sync with pops the user made
// and says when a popped page's tree is really gone.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"
import OBJC "core:sys/darwin/ObjectiveC"

@(private) page_controller_class: NS.Class

// A page pop() removed, until its controller leaves the navigation controller.
@(private) Retiring :: struct {
	vc:    NS.id, // retained
	scope: ^Scope,
}

// Returns an owned (+1) controller showing the page's view, pinned to the safe area: a stack
// view doesn't inset itself like a table view does, so it would slide under the navigation bar.
@(private)
page_controller_new :: proc(e: ^Page_Handle) -> ^UI_View_Controller {
	cls := objc_class(&page_controller_class, "NVPageController", "UIViewController", {
		{"didMoveToParentViewController:", auto_cast page_did_move, "v@:@"},
	})
	container := ui_view_new()
	ui_view_set_background_color(container, ui_color_system_background())
	ui_view_pin_to_safe_area((^UI_View)(e.root), container)
	vc := send(^UI_View_Controller, (^UI_View_Controller)(OBJC.class_createInstance(cls, 0)), "init")
	ui_view_controller_set_view(vc, container)
	container->release()
	ui_view_controller_set_title(vc, ns_string(e.page.title))
	ios_apply_actions(vc, e)
	if nav_shows_menu(e) { // the root page with a drawer: Flutter's hamburger where a back button would be
		item := ui_bar_button_item_with_image(ui_image_system(ns_string(sf_symbol_names[.Menu])), g_app.nav_target, intrinsics.objc_find_selector("nvMenu:"))
		ui_bar_button_item_set_accessibility_label(item, ns_string("Menu"))
		send(nil, ui_view_controller_navigation_item(vc), "setLeftBarButtonItem:", item)
		send(nil, item, "release")
	}
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

// UIKit refuses a pop while another transition is still animating and returns nil, or queues it
// behind that transition; page_did_move covers the queued case.
@(private)
_nav_pop :: proc(top, below: ^Page_Handle) -> bool {
	return ui_navigation_controller_pop(g_app.nav, true) != nil
}

// A page popped by pop() is still on screen through the pop animation (drawRect:, table cells and
// touches can still reach its handles), and a transition queued behind the pop lays it out once
// more, so its scope waits for the controller's didMoveToParentViewController:nil. A back button
// or swipe gets here from inside that call, with the tree already gone.
@(private)
_nav_release :: proc(e: ^Page_Handle) {
	if e == g_app.removing {
		scope_retire(e.scope)
		return
	}
	vc := (^NS.Object)(e.native)
	send(nil, vc, "retain") // keeps the pointer unique until page_did_move matches it
	append(&g_app.retiring, Retiring{NS.id(vc), e.scope})
}

// didMoveToParentViewController:. UIKit sends nil once a popped controller has left the navigation
// controller, after its transition, whoever popped it. Unlike the delegate's didShow, it names the
// page, so a push queued behind the pop is left alone. A controller that still has a parent was not
// removed (a cancelled swipe keeps it), so nothing is done for it. UIViewController's own
// implementation does nothing, so no super call.
@(private)
page_did_move :: proc "c" (self: NS.id, _: NS.SEL, parent: NS.id) {
	if parent != nil || send(^NS.Object, (^NS.Object)(self), "parentViewController") != nil do return
	context = g_app.ctx
	callback_enter()
	defer callback_exit()
	for r, i in g_app.retiring do if r.vc == self { // pop(): the bookkeeping ran, only the scope waited
		ordered_remove(&g_app.retiring, i)
		scope_retire(r.scope)
		send(nil, (^NS.Object)(self), "autorelease")
		return
	}
	for e in g_nav[1:] do if e.native == rawptr(self) { // the back button or a swipe
		g_app.removing = e
		nav_system_pop_page(e)
		g_app.removing = nil
		return
	}
}

// The menu button; the scrim of a modal dialog covers the bar, so it needs no check of its own.
@(private)
nav_menu_clicked :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	context = g_app.ctx
	nav_menu_notify()
}
