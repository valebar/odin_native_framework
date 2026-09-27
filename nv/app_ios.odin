#+build darwin
package nv

// iOS app backend: UIApplicationMain + scene lifecycle (NVSceneDelegate is named in ios/Info.plist).
// The window's root is a UINavigationController whose root view controller wraps the root page
// (nav_ios.odin).

import "base:intrinsics"
import "base:runtime"
import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private) g_app: struct {
	ctx:          runtime.Context,
	window:       ^UI_Window,
	nav:          ^UI_Navigation_Controller, // owned by the window
	nav_delegate: NS.id,                     // NVNavDelegate; the controller's delegate is weak
}

@(private)
_run :: proc() {
	g_app.ctx = context

	UIResponder := intrinsics.objc_find_class("UIResponder")
	NSObject := intrinsics.objc_find_class("NSObject")

	app_delegate := NS.objc_allocateClassPair(UIResponder, "NVAppDelegate", 0)
	NS.class_addMethod(app_delegate, intrinsics.objc_find_selector("application:didFinishLaunchingWithOptions:"), auto_cast did_finish_launching, "B@:@@")
	NS.class_addProtocol(app_delegate, NS.objc_getProtocol("UIApplicationDelegate"))
	NS.objc_registerClassPair(app_delegate)

	scene_delegate := NS.objc_allocateClassPair(UIResponder, "NVSceneDelegate", 0)
	NS.class_addMethod(scene_delegate, intrinsics.objc_find_selector("scene:willConnectToSession:options:"), auto_cast scene_will_connect, "v@:@@@")
	NS.class_addMethod(scene_delegate, intrinsics.objc_find_selector("window"), auto_cast scene_window, "@@:")
	NS.class_addProtocol(scene_delegate, NS.objc_getProtocol("UIWindowSceneDelegate"))
	NS.objc_registerClassPair(scene_delegate)

	nav_delegate := NS.objc_allocateClassPair(NSObject, "NVNavDelegate", 0)
	NS.class_addMethod(nav_delegate, intrinsics.objc_find_selector("navigationController:didShowViewController:animated:"), auto_cast nav_did_show, "v@:@@B")
	NS.class_addProtocol(nav_delegate, NS.objc_getProtocol("UINavigationControllerDelegate"))
	NS.objc_registerClassPair(nav_delegate)
	g_app.nav_delegate = NS.class_createInstance(nav_delegate, 0)

	args := runtime.args__
	UIApplicationMain(i32(len(args)), raw_data(args), nil, NS.AT("NVAppDelegate"))
}

@(private)
did_finish_launching :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id, _: NS.id) -> NS.BOOL {
	return true
}

@(private)
scene_window :: proc "c" (self: NS.id, _: NS.SEL) -> ^UI_Window {
	return g_app.window
}

@(private)
scene_will_connect :: proc "c" (self: NS.id, _: NS.SEL, scene: NS.id, _: NS.id, _: NS.id) {
	context = g_app.ctx
	callback_enter()
	defer callback_exit()

	// The navigation controller wants its root view controller up front, so the root page
	// doesn't go through _nav_push.
	nav_build(&g_nav[0])
	root := page_controller_new(&g_nav[0])
	nav := ui_navigation_controller_new(root)
	root->release()
	ui_navigation_controller_set_delegate(nav, g_app.nav_delegate)
	g_app.nav = nav

	g_app.window = ui_window_new(scene)
	ui_window_set_root_view_controller(g_app.window, nav)
	nav->release()
	ui_window_make_key_and_visible(g_app.window)
	nav_flush_pending() // pages the root build pushed
}

}
