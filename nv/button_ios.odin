#+build darwin
package nv

// iOS button backend: a system UIButton; target-action delivers TouchUpInside to an
// NVButtonTarget object.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private) button_class: NS.Class

@(private)
_button_init :: proc(h: ^Button_Handle) {
	button := ui_button_system() // autoreleased
	button->retain() // *_create returns owned views
	ui_button_set_title(button, ns_string(h.button.title))

	t := button_target_alloc(h) // not retained by the button; lives as long as the handle
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
	if button_class == nil {
		button_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "NVButtonTarget", 0)
		NS.class_addMethod(button_class, intrinsics.objc_find_selector("nvClick:"), auto_cast button_clicked, "v@:@")
		NS.objc_registerClassPair(button_class)
	}
	obj := NS.class_createInstance(button_class, size_of(^Button_Handle))
	(^^Button_Handle)(NS.object_getIndexedIvars(obj))^ = h
	return obj
}

@(private)
button_clicked :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	h := (^^Button_Handle)(NS.object_getIndexedIvars(self))^
	context = h.ctx
	button_notify(h)
}

}
