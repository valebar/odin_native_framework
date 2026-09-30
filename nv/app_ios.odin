#+build darwin
package nv

// iOS app backend: UIApplicationMain + scene lifecycle (NVSceneDelegate is named in ios/Info.plist).
// The window's root is a UINavigationController whose root view controller wraps the root page
// (nav_ios.odin).

import "base:runtime"
import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private) app_delegate_class, scene_delegate_class, nav_target_class: NS.Class

@(private) g_app: struct {
	ctx:          runtime.Context,
	window:       ^UI_Window,
	nav:          ^UI_Navigation_Controller, // owned by the window
	nav_target:   NS.id,                     // NVNavTarget: receives the bar button items' actions
	removing:     ^Page_Handle,              // the page whose controller is inside didMoveToParentViewController:nil
	retiring:     [dynamic]Retiring,         // pages pop() removed, until their controllers leave (nav_ios.odin)
}

@(private)
_run :: proc() {
	g_app.ctx = context

	// UIKit instantiates the app and scene delegates itself (the scene delegate by the name in
	// ios/Info.plist); the nav target is a singleton with no ivars.
	objc_class(&app_delegate_class, "NVAppDelegate", "UIResponder", {
		{"application:didFinishLaunchingWithOptions:", auto_cast did_finish_launching, "B@:@@"},
	}, {"UIApplicationDelegate"})
	objc_class(&scene_delegate_class, "NVSceneDelegate", "UIResponder", {
		{"scene:willConnectToSession:options:", auto_cast scene_will_connect, "v@:@@@"},
		{"window", auto_cast scene_window, "@@:"},
	}, {"UIWindowSceneDelegate"})
	nav_target := objc_class(&nav_target_class, "NVNavTarget", "NSObject", {
		{"nvAction:", auto_cast nav_action_clicked, "v@:@"},
	})
	g_app.nav_target = NS.class_createInstance(nav_target, 0)

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
	theme_start()

	// The navigation controller wants its root view controller up front, so the root page
	// doesn't go through _nav_push.
	nav_build(g_nav[0])
	root := page_controller_new(g_nav[0])
	nav := ui_navigation_controller_new(root)
	root->release()
	g_app.nav = nav

	g_app.window = ui_window_new(scene)
	theme_install(g_app.window)
	ui_window_set_root_view_controller(g_app.window, nav)
	nav->release()
	ui_window_make_key_and_visible(g_app.window)
	nav_flush_pending() // pages the root build pushed
}

}
