#+build darwin
package nv

// iOS input backend: a rounded UITextField. UIControl target-action delivers the edits
// (EditingChanged) and Return (EditingDidEndOnExit, which also dismisses the keyboard) to an
// NVInputTarget object. setText: sends no events.

import "base:intrinsics"
import "core:strings"
import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private) input_class: NS.Class

@(private)
_input_init :: proc(h: ^Input_Handle) {
	field := ui_text_field_new()
	ui_text_field_set_border_style(field, UI_TEXT_BORDER_STYLE_ROUNDED_RECT)
	ui_text_field_set_return_key_type(field, UI_RETURN_KEY_DONE)
	ui_text_field_set_text(field, ns_string(h.input.text))
	if h.input.placeholder != "" do ui_text_field_set_placeholder(field, ns_string(h.input.placeholder))

	t := input_target_alloc(h) // not retained by the field; lives as long as the handle
	ui_control_add_target(field, t, intrinsics.objc_find_selector("nvChanged:"), UI_CONTROL_EVENT_EDITING_CHANGED)
	ui_control_add_target(field, t, intrinsics.objc_find_selector("nvSubmit:"), UI_CONTROL_EVENT_EDITING_DID_END_ON_EXIT)

	h.root = View(field)
	h.field = field
	h.delegate = t
}

@(private)
_input_text :: proc(h: ^Input_Handle, allocator := context.allocator) -> string {
	s := ui_text_field_text((^UI_Text_Field)(h.field))
	return s == nil ? "" : strings.clone(s->odinString(), allocator)
}

@(private)
_input_set_text :: proc(h: ^Input_Handle, text: string) {
	ui_text_field_set_text((^UI_Text_Field)(h.field), ns_string(text))
}

@(private)
input_target_alloc :: proc(h: ^Input_Handle) -> NS.id {
	if input_class == nil {
		input_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "NVInputTarget", 0)
		NS.class_addMethod(input_class, intrinsics.objc_find_selector("nvChanged:"), auto_cast input_changed, "v@:@")
		NS.class_addMethod(input_class, intrinsics.objc_find_selector("nvSubmit:"), auto_cast input_submit, "v@:@")
		NS.objc_registerClassPair(input_class)
	}
	obj := NS.class_createInstance(input_class, size_of(^Input_Handle))
	(^^Input_Handle)(NS.object_getIndexedIvars(obj))^ = h
	return obj
}

@(private)
input_handle_of :: #force_inline proc "c" (self: NS.id) -> ^Input_Handle {
	return (^^Input_Handle)(NS.object_getIndexedIvars(self))^
}

@(private)
input_changed :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	h := input_handle_of(self)
	context = h.ctx
	input_notify(h, h.input.on_change)
}

@(private)
input_submit :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	h := input_handle_of(self)
	context = h.ctx
	input_notify(h, h.input.on_submit)
}

}
