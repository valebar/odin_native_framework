#+build darwin
package nv

// macOS navigation backend: the top page is the window's content view and the page title is the
// window title. The back button is a chevron NSButton in an NSTitlebarAccessoryViewController on
// the leading edge of the title bar, next to the window buttons, hidden on the root page.

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
nav_update_chrome :: proc(e: ^Nav_Page) {
	g_macos.window->setTitle(ns_string(e.page.title))
	titlebar_accessory_set_hidden(g_macos.back, len(g_nav) <= 1)
}

@(private)
nav_install_back_button :: proc(wnd: ^NS.Window) {
	cls := NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "NVNavTarget", 0)
	NS.class_addMethod(cls, intrinsics.objc_find_selector("nvBack:"), auto_cast nav_back_clicked, "v@:@")
	NS.objc_registerClassPair(cls)
	target := NS.class_createInstance(cls, 0) // lives for the whole run

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

}
