#+build darwin:default
package nv

// macOS theme backend. The mode is NSApp.appearance (Aqua, DarkAqua, or nil to follow the
// system), and the widgets use AppKit's dynamic colors, so they recolor themselves. The window's
// content view is an NVContentView (app_macos.odin) whose viewDidChangeEffectiveAppearance
// reports every change, the system's included.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(private) APPEARANCE_AQUA      :: "NSAppearanceNameAqua"
@(private) APPEARANCE_DARK_AQUA :: "NSAppearanceNameDarkAqua"

@(private)
_theme_system_dark :: proc() -> bool {
	appearance := send(^NS.Object, NS.Application.sharedApplication(), "effectiveAppearance")
	names := [2]^NS.Object{NS.AT(APPEARANCE_AQUA), NS.AT(APPEARANCE_DARK_AQUA)}
	best := send(^NS.String, appearance, "bestMatchFromAppearancesWithNames:", array_with_objects(&names[0], 2))
	return best != nil && send(NS.BOOL, best, "isEqualToString:", NS.AT(APPEARANCE_DARK_AQUA))
}

@(private)
_theme_system_accent :: proc() -> Color {
	return apple_color_components(send(^NS.Object, NS.Color, "controlAccentColor"))
}

@(private)
_theme_apply_mode :: proc() {
	appearance := NS.id(nil)
	switch g_theme.mode {
	case .System:
	case .Light: appearance = NS.id(send(^Appearance, Appearance, "appearanceNamed:", NS.AT(APPEARANCE_AQUA)))
	case .Dark:  appearance = NS.id(send(^Appearance, Appearance, "appearanceNamed:", NS.AT(APPEARANCE_DARK_AQUA)))
	}
	send(nil, NS.Application.sharedApplication(), "setAppearance:", appearance)
}

// Dynamic colors follow on their own.
@(private)
_theme_recolor :: proc() {}

// The window's content view: a plain NSView that reports appearance changes.
@(private)
content_view_new :: proc(frame: NS.Rect) -> ^NS.View {
	@(static) cls: NS.Class
	if cls == nil {
		cls = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSView"), "NVContentView", 0)
		NS.class_addMethod(cls, intrinsics.objc_find_selector("viewDidChangeEffectiveAppearance"), auto_cast content_appearance_changed, "v@:")
		NS.objc_registerClassPair(cls)
	}
	return send(^NS.View, (^NS.View)(NS.class_createInstance(cls, 0)), "initWithFrame:", frame) // owned
}

@(private)
content_appearance_changed :: proc "c" (self: NS.id, _: NS.SEL) {
	context = g_macos.ctx
	theme_notify()
}
