#+build darwin:ios
#+private
package nv

// iOS input backend: a rounded UITextField. UIControl target-action delivers the edits
// (EditingChanged) and Return (EditingDidEndOnExit, which also dismisses the keyboard) to an
// NVInputTarget object. setText: sends no events. The number pads have no Return key.

import "base:intrinsics"
import "core:strings"
import NS "core:sys/darwin/Foundation"

@(private) input_class: NS.Class

// UIKeyboardType by Keyboard; Text and Sentences keep the default keyboard.
@(private) input_keyboard_types := [Keyboard]NS.Integer{
	.Text          = 0,
	.Sentences     = 0,
	.Number        = 4, // NumberPad
	.Signed_Number = 2, // NumbersAndPunctuation: the number pad has no minus
	.Decimal       = 8, // DecimalPad
}

@(private)
_input_init :: proc(h: ^Input_Handle) {
	field := objc_own(ui_text_field_new())
	ui_text_field_set_border_style(field, UI_TEXT_BORDER_STYLE_ROUNDED_RECT)
	ui_text_field_set_return_key_type(field, UI_RETURN_KEY_DONE)
	ui_text_field_set_text(field, ns_string(h.input.text))
	if h.input.placeholder != "" do ui_text_field_set_placeholder(field, ns_string(h.input.placeholder))
	s := h.input.style
	if style_sets_font(s) do send(nil, field, "setFont:", apple_font(s, font_point_size(send(^NS.Object, field, "font")), false))
	if s.color.a > 0 do send(nil, field, "setTextColor:", canvas_color(s.color))
	// .Text keeps UITextField's defaults (which capitalize sentences already)
	if h.input.keyboard != .Text do send(nil, field, "setKeyboardType:", input_keyboard_types[h.input.keyboard])
	if h.input.keyboard == .Sentences do send(nil, field, "setAutocapitalizationType:", UI_TEXT_AUTOCAPITALIZATION_SENTENCES)
	if h.input.secure do send(nil, field, "setSecureTextEntry:", NS.BOOL(true))

	t := objc_own(input_target_alloc(h)) // not retained by the field; lives as long as the handle's scope
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
	cls := objc_class(&input_class, "NVInputTarget", "NSObject", {
		{"nvChanged:", auto_cast input_changed, "v@:@"},
		{"nvSubmit:", auto_cast input_submit, "v@:@"},
	})
	return objc_alloc_with_handle(cls, h)
}

@(private)
input_changed :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	h := objc_handle(self, Input_Handle)
	context = h.ctx
	input_notify(h, h.input.on_change)
}

@(private)
input_submit :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	h := objc_handle(self, Input_Handle)
	context = h.ctx
	input_notify(h, h.input.on_submit)
}

// The caret lands at the end. A selectAll: right after becomeFirstResponder may be dropped while
// the keyboard comes up, so it runs from the next turn of the main queue (the field retained).
@(private)
_input_focus :: proc(h: ^Input_Handle, select_all: bool) {
	field := (^NS.Object)(h.field)
	if !send(NS.BOOL, field, "becomeFirstResponder") || !select_all do return
	send(nil, field, "retain")
	dispatch_async_f(&_dispatch_main_q, field, input_select_all)
}

@(private)
input_select_all :: proc "c" (data: rawptr) {
	field := (^NS.Object)(data)
	if send(NS.BOOL, field, "isFirstResponder") do send(nil, field, "selectAll:", NS.id(nil))
	send(nil, field, "release")
}
