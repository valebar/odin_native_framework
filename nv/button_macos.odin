#+build darwin
package nv

// macOS button backend: a bezel push button (NSButton buttonWithTitle:target:action:) whose
// action goes to an NVButtonTarget object. A custom font goes on the button (NSControl setFont:);
// the push bezel keeps its height, so a large size clips.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private) button_class: NS.Class

@(private)
_button_init :: proc(h: ^Button_Handle) {
	t := objc_own(button_target_alloc(h)) // weak target; lives as long as the handle's scope
	button := button_push(ns_string(h.button.title), t, intrinsics.objc_find_selector("nvClick:")) // autoreleased
	objc_own(button)->retain() // *_create returns owned views
	s := h.button.style
	if style_sets_font(s) do send(nil, button, "setFont:", apple_font(s, font_point_size(send(^NS.Object, button, "font")), false))
	if s.color.a > 0 do send(nil, button, "setContentTintColor:", canvas_color(s.color))
	if g_theme.accent.a > 0 do send(nil, button, "setBezelColor:", canvas_color(g_theme.accent))

	h.root = View(button)
	h.control = button
	h.target = t
}

@(private)
_button_set_title :: proc(h: ^Button_Handle, title: string) {
	button_set_title_ns((^Button_View)(h.control), ns_string(title))
}

@(private)
button_target_alloc :: proc(h: ^Button_Handle) -> NS.id {
	cls := objc_class(&button_class, "NVButtonTarget", "NSObject", {
		{"nvClick:", auto_cast button_clicked, "v@:@"},
	})
	return objc_alloc_with_handle(cls, h)
}

@(private)
button_clicked :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	h := objc_handle(self, Button_Handle)
	context = h.ctx
	button_notify(h)
}

}
