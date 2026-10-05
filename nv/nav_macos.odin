#+build darwin:default
package nv

// macOS navigation backend: the pages are full-size subviews of the window's content view
// (g_macos.content), the pages below the top hidden, and the page title is the window title. The
// back button is a chevron NSButton in an NSTitlebarAccessoryViewController on the leading edge
// of the title bar, next to the window buttons, hidden on the root page. The page's actions are
// NSButtons in a second accessory on the trailing edge, rebuilt on every chrome update.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(private)
_nav_push :: proc(e: ^Page_Handle) {
	root := (^NS.View)(e.root)
	view_set_translates_autoresizing_mask(root, false)
	if len(g_nav) > 1 do view_set_hidden((^NS.View)(g_nav[len(g_nav) - 2].root), true)
	g_macos.content->addSubview(root) // added last: above the lower pages and their dialogs
	layout_pin_page(root, g_macos.content)
	nav_update_chrome(e)
}

@(private)
_nav_pop :: proc(top, below: ^Page_Handle) -> bool {
	view_remove_from_superview((^NS.View)(top.root))
	view_set_hidden((^NS.View)(below.root), false)
	nav_update_chrome(below)
	return true
}

// _nav_pop already removed the root from the window, so the scope can go: it autoreleases the
// page's views rather than releasing them, since when pop() runs from a button on the page itself
// the button's action is still on the stack. The pool drains once the event is handled.
@(private)
_nav_release :: proc(e: ^Page_Handle) {
	scope_retire(e.scope)
}

// The bar shows the top page only; a lower page's changes are picked up when it is shown again.
@(private)
_nav_title_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do g_macos.window->setTitle(ns_string(e.page.title))
}

@(private)
_nav_actions_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do nav_rebuild_actions(e)
}

@(private)
nav_update_chrome :: proc(e: ^Page_Handle) {
	g_macos.window->setTitle(ns_string(e.page.title))
	titlebar_accessory_set_hidden(g_macos.back, len(g_nav) <= 1)
	nav_rebuild_actions(e)
}

// The accessory is recreated rather than resized: AppKit sizes it from its view's frame when it
// is added. The old buttons may be inside their own action right now, so their container is
// autoreleased before it is removed, like a popped page's root.
@(private)
nav_rebuild_actions :: proc(e: ^Page_Handle) {
	if g_macos.actions != nil {
		container := send(^NS.View, g_macos.actions, "view")
		send(nil, container, "retain")
		send(nil, container, "autorelease")
		window_remove_titlebar_accessory(g_macos.window, g_macos.actions)
		g_macos.actions = nil
	}
	if len(e.actions) == 0 do return

	container := NS.View.alloc()->initWithFrame({})
	x, height: NS.Float = 6, 0
	for h in e.actions {
		action := intrinsics.objc_find_selector("nvAction:")
		title := ns_string(h.action.title)
		button: ^Button_View
		if name := sf_symbol_names[h.action.icon]; name != "" {
			button = button_with_image(image_system_symbol(ns_string(name), title), g_macos.nav_target, action)
			view_set_tool_tip(button, title)
		} else {
			button = button_push(title, g_macos.nav_target, action)
		}
		button_set_bezel_style(button, BEZEL_STYLE_TEXTURED_ROUNDED)
		object_set_tag(button, NS.Integer(uintptr(h)))
		send(nil, button, "sizeToFit")
		size := send(NS.Rect, button, "frame").size
		view_set_frame(button, {{x, 2}, size})
		view_set_autoresizing(button, RESIZE_MIN_Y_MARGIN | RESIZE_MAX_Y_MARGIN)
		container->addSubview(button)
		x += size.width + 6
		height = max(height, size.height)
	}
	view_set_frame(container, {{0, 0}, {x, height + 4}})

	vc := titlebar_accessory_new()
	titlebar_accessory_set_view(vc, container)
	container->release()
	titlebar_accessory_set_layout_attribute(vc, LAYOUT_ATTRIBUTE_TRAILING)
	window_add_titlebar_accessory(g_macos.window, vc)
	vc->release()
	g_macos.actions = vc
}

@(private)
nav_install_back_button :: proc(wnd: ^NS.Window) {
	cls := objc_class(&nav_target_class, "NVNavTarget", "NSObject", {
		{"nvBack:", auto_cast nav_back_clicked, "v@:@"},
		{"nvAction:", auto_cast nav_action_clicked, "v@:@"},
	})
	target := NS.class_createInstance(cls, 0) // lives for the whole run
	g_macos.nav_target = target

	image := image_system_symbol(ns_string("chevron.backward"), ns_string("Back"))
	button := button_with_image(image, target, intrinsics.objc_find_selector("nvBack:"))
	button_set_bezel_style(button, BEZEL_STYLE_TEXTURED_ROUNDED)
	send(nil, button, "sizeToFit")
	size := send(NS.Rect, button, "frame").size

	// A plain container keeps the button centered in whatever height AppKit gives the accessory.
	container := NS.View.alloc()->initWithFrame({{0, 0}, {size.width + 12, size.height + 4}})
	view_set_frame(button, {{6, 2}, size})
	view_set_autoresizing(button, RESIZE_MIN_X_MARGIN | RESIZE_MAX_X_MARGIN | RESIZE_MIN_Y_MARGIN | RESIZE_MAX_Y_MARGIN)
	container->addSubview(button)

	vc := titlebar_accessory_new()
	titlebar_accessory_set_view(vc, container)
	container->release()
	titlebar_accessory_set_layout_attribute(vc, LAYOUT_ATTRIBUTE_LEADING)
	titlebar_accessory_set_hidden(vc, true)
	window_add_titlebar_accessory(wnd, vc)
	vc->release()
	g_macos.back = vc
}

@(private)
nav_back_clicked :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	context = g_macos.ctx
	nav_back_notify()
}
