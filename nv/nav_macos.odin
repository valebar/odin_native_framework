#+build darwin
package nv

// macOS navigation backend: the top page is the window's content view and the page title is the
// window title. The back button is a chevron NSButton in an NSTitlebarAccessoryViewController on
// the leading edge of the title bar, next to the window buttons, hidden on the root page. The
// page's actions are NSButtons in a second accessory on the trailing edge, rebuilt on every
// chrome update.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private)
_nav_push :: proc(e: ^Nav_Page) {
	root := (^NS.View)(e.root)
	view_set_autoresizing(root, RESIZE_WIDTH | RESIZE_HEIGHT)
	g_macos.window->setContentView(root)
	nav_update_chrome(e)
}

@(private)
_nav_pop :: proc(top, below: ^Nav_Page) -> bool {
	g_macos.window->setContentView((^NS.View)(below.root))
	nav_update_chrome(below)
	return true
}

// Autoreleased rather than released: when pop() runs from a button on the page itself, the
// window already dropped its reference in setContentView: and the button's action is still on
// the stack. The pool drains once the event is handled.
@(private)
_nav_release :: proc(e: ^Nav_Page) {
	send(nil, (^NS.Object)(e.root), "autorelease")
}

@(private)
_nav_actions_changed :: proc(e: ^Nav_Page) {
	nav_update_chrome(e)
}

@(private)
nav_update_chrome :: proc(e: ^Nav_Page) {
	g_macos.window->setTitle(ns_string(e.page.title))
	titlebar_accessory_set_hidden(g_macos.back, len(g_nav) <= 1)
	nav_rebuild_actions(e)
}

// The accessory is recreated rather than resized: AppKit sizes it from its view's frame when it
// is added. The old buttons may be inside their own action right now, so their container is
// autoreleased before it is removed, like a popped page's root.
@(private)
nav_rebuild_actions :: proc(e: ^Nav_Page) {
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
	cls := NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "NVNavTarget", 0)
	NS.class_addMethod(cls, intrinsics.objc_find_selector("nvBack:"), auto_cast nav_back_clicked, "v@:@")
	NS.class_addMethod(cls, intrinsics.objc_find_selector("nvAction:"), auto_cast nav_action_clicked, "v@:@")
	NS.objc_registerClassPair(cls)
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
	callback_enter()
	defer callback_exit()
	pop()
}

// `sender` is the action's NSButton; its tag is the handle.
@(private)
nav_action_clicked :: proc "c" (self: NS.id, _: NS.SEL, sender: NS.id) {
	context = g_macos.ctx
	action_notify((^Action_Handle)(uintptr(object_tag((^NS.Object)(sender)))))
}

}
