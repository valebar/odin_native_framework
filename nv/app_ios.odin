#+build darwin
package nv

// iOS app backend: UIApplicationMain + scene lifecycle (NVSceneDelegate is named in ios/Info.plist).

import "base:intrinsics"
import "base:runtime"
import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private) g_app: struct {
	title:  string,
	build:  Build_Proc,
	user:   rawptr,
	ctx:    runtime.Context,
	window: ^UI_Window,
}

@(private)
_run :: proc(title: string, build: Build_Proc, user: rawptr) {
	g_app = {title = title, build = build, user = user, ctx = context}

	UIResponder := intrinsics.objc_find_class("UIResponder")

	app_delegate := NS.objc_allocateClassPair(UIResponder, "NVAppDelegate", 0)
	NS.class_addMethod(app_delegate, intrinsics.objc_find_selector("application:didFinishLaunchingWithOptions:"), auto_cast did_finish_launching, "B@:@@")
	NS.class_addProtocol(app_delegate, NS.objc_getProtocol("UIApplicationDelegate"))
	NS.objc_registerClassPair(app_delegate)

	scene_delegate := NS.objc_allocateClassPair(UIResponder, "NVSceneDelegate", 0)
	NS.class_addMethod(scene_delegate, intrinsics.objc_find_selector("scene:willConnectToSession:options:"), auto_cast scene_will_connect, "v@:@@@")
	NS.class_addMethod(scene_delegate, intrinsics.objc_find_selector("window"), auto_cast scene_window, "@@:")
	NS.class_addProtocol(scene_delegate, NS.objc_getProtocol("UIWindowSceneDelegate"))
	NS.objc_registerClassPair(scene_delegate)

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

	root := ui_view_controller_new()
	ui_view_controller_set_view(root, (^UI_View)(g_app.build(g_app.user)))
	ui_view_controller_set_title(root, ns_string(g_app.title))
	nav := ui_navigation_controller_new(root)
	root->release()

	g_app.window = ui_window_new(scene)
	ui_window_set_root_view_controller(g_app.window, nav)
	nav->release()
	ui_window_make_key_and_visible(g_app.window)
}

}
