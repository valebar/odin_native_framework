#+build darwin:default
package nv

// macOS input backend: an editable NSTextField. Its delegate (NVInputDelegate) gets
// controlTextDidChange: for every edit and control:textView:doCommandBySelector: for Return
// (insertNewline:). setStringValue: sends no change notification.

import "base:intrinsics"
import "core:strings"
import NS "core:sys/darwin/Foundation"

@(private) input_class: NS.Class

@(private)
_input_init :: proc(h: ^Input_Handle) {
	field := text_field_editable(ns_string(h.input.text)) // autoreleased; *_create returns owned views
	objc_own(field)->retain()
	if h.input.placeholder != "" do text_field_set_placeholder(field, ns_string(h.input.placeholder))
	s := h.input.style
	if style_sets_font(s) do text_field_set_font(field, (^NS_Font)(apple_font(s, font_point_size(send(^NS.Object, field, "font")), false)))
	if s.color.a > 0 do text_field_set_text_color(field, (^NS.Color)(canvas_color(s.color)))

	d := objc_own(input_delegate_alloc(h))
	text_field_set_delegate(field, d) // weak; the delegate lives as long as the handle's scope
	objc_clear_delegate_on_dispose(field)

	h.root = View(field)
	h.field = field
	h.delegate = d
}

@(private)
_input_text :: proc(h: ^Input_Handle, allocator := context.allocator) -> string {
	return strings.clone(text_field_string((^Text_Field)(h.field))->odinString(), allocator)
}

@(private)
_input_set_text :: proc(h: ^Input_Handle, text: string) {
	text_field_set_string((^Text_Field)(h.field), ns_string(text))
}

@(private)
input_delegate_alloc :: proc(h: ^Input_Handle) -> NS.id {
	cls := objc_class(&input_class, "NVInputDelegate", "NSObject", {
		{"controlTextDidChange:", auto_cast input_did_change, "v@:@"},
		{"control:textView:doCommandBySelector:", auto_cast input_do_command, "B@:@@:"},
	})
	return objc_alloc_with_handle(cls, h)
}

@(private)
input_did_change :: proc "c" (self: NS.id, _: NS.SEL, _: ^NS.Notification) {
	h := objc_handle(self, Input_Handle)
	context = h.ctx
	input_notify(h, h.input.on_change)
}

// Returns false so the field still handles the command (Return ends editing and selects the text).
@(private)
input_do_command :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id, _: NS.id, command: NS.SEL) -> NS.BOOL {
	h := objc_handle(self, Input_Handle)
	context = h.ctx
	if command == intrinsics.objc_find_selector("insertNewline:") do input_notify(h, h.input.on_submit)
	return false
}
