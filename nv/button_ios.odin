#+build darwin
package nv

// iOS button backend: a system UIButton; target-action delivers TouchUpInside to an
// NVButtonTarget object. A custom font goes on the title label (a system button has no
// UIButtonConfiguration, so the label's font is honoured).

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private) button_class: NS.Class

@(private)
_button_init :: proc(h: ^Button_Handle) {
	button := ui_button_system() // autoreleased
	objc_own(button)->retain()
	ui_button_set_title(button, ns_string(h.button.title))
	if h.button.font != nil || h.button.size != 0 { // else the button's own 15pt system font
		title_label := send(^NS.Object, button, "titleLabel")
		send(nil, title_label, "setFont:", text_font(h.button.font, h.button.size != 0 ? h.button.size : 15, false))
	}

	t := objc_own(button_target_alloc(h)) // not retained by the button; lives as long as the handle's scope
	ui_control_add_target(button, t, intrinsics.objc_find_selector("nvClick:"), UI_CONTROL_EVENT_TOUCH_UP_INSIDE)

	h.root = View(button)
	h.control = button
	h.target = t
}

@(private)
_button_set_title :: proc(h: ^Button_Handle, title: string) {
	ui_button_set_title((^UI_Button)(h.control), ns_string(title))
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
