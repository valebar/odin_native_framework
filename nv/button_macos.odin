#+build darwin
package nv

// macOS button backend: a bezel push button (NSButton buttonWithTitle:target:action:) whose
// action goes to an NVButtonTarget object.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private) button_class: NS.Class

@(private)
_button_init :: proc(h: ^Button_Handle) {
	t := button_target_alloc(h) // weak target; lives as long as the handle
	button := button_push(ns_string(h.button.title), t, intrinsics.objc_find_selector("nvClick:")) // autoreleased
	button->retain() // *_create returns owned views

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
