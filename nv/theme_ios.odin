#+build darwin:ios
package nv

// iOS theme backend. The mode is the window's overrideUserInterfaceStyle (0 follows the system,
// 1 light, 2 dark), the accent its tintColor, and the widgets use UIKit's dynamic colors. An
// invisible NVTraitView in the window reports trait changes, the system's appearance included
// (UIView's traitCollectionDidChange: does nothing, so it needs no super call).

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"
import OBJC "core:sys/darwin/ObjectiveC"

@(private)
_theme_system_dark :: proc() -> bool {
	screen := send(^UI_Screen, UI_Screen, "mainScreen")
	traits := send(^NS.Object, screen, "traitCollection")
	return send(NS.Integer, traits, "userInterfaceStyle") == 2 // UIUserInterfaceStyleDark
}

@(private)
_theme_system_accent :: proc() -> Color {
	return apple_color_components(send(^NS.Object, UI_Color, "systemBlueColor"))
}

// The window doesn't exist before the scene connects; scene_will_connect runs this again then.
@(private)
_theme_apply_mode :: proc() {
	if g_app.window == nil do return
	style: NS.Integer
	switch g_theme.mode {
	case .System: style = 0
	case .Light:  style = 1
	case .Dark:   style = 2
	}
	send(nil, g_app.window, "setOverrideUserInterfaceStyle:", style)
}

@(private)
_theme_recolor :: proc() {}

// Sets the accent on the new window, the bar title's font on the navigation bar's title (UIKit's
// is 17pt semibold) and adds the view that watches the traits.
@(private)
theme_install :: proc(w: ^UI_Window) {
	_theme_apply_mode()
	if g_theme.accent.a > 0 do send(nil, w, "setTintColor:", canvas_color(g_theme.accent))
	if title := theme_bar_title(); style_sets_font(title) {
		keys := [1]^NS.Object{NS.AT("NSFont")}
		values := [1]^NS.Object{apple_font(title, 17, true)}
		attrs := NS.Dictionary.dictionaryWithObjects((^NS.id)(&values[0]), (^^NS.Copying)(&keys[0]), 1)
		send(nil, send(^NS.Object, g_app.nav, "navigationBar"), "setTitleTextAttributes:", attrs)
	}

	cls := OBJC.objc_allocateClassPair(intrinsics.objc_find_class("UIView"), "NVTraitView", 0)
	OBJC.class_addMethod(cls, intrinsics.objc_find_selector("traitCollectionDidChange:"), auto_cast trait_view_changed, "v@:@")
	OBJC.objc_registerClassPair(cls)
	v := send(^UI_View, (^UI_View)(OBJC.class_createInstance(cls, 0)), "initWithFrame:", NS.Rect{})
	send(nil, v, "setUserInteractionEnabled:", NS.BOOL(false))
	ui_view_add_subview(w, v)
	v->release()
}

@(private)
trait_view_changed :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	context = g_app.ctx
	theme_notify()
}
