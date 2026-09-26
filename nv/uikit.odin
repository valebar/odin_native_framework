#+build darwin
package nv

// Minimal hand-written UIKit bindings (iOS only).

import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(require) foreign import uikit "system:UIKit.framework"

foreign uikit {
	UIApplicationMain :: proc "c" (argc: i32, argv: [^]cstring, principal: ^NS.String, delegate: ^NS.String) -> i32 ---
}

@(objc_class="UIView")
UI_View :: struct { using _: NS.Object }

@(objc_class="UIWindow")
UI_Window :: struct { using _: UI_View }

@(objc_class="UIViewController")
UI_View_Controller :: struct { using _: NS.Object }

@(objc_class="UINavigationController")
UI_Navigation_Controller :: struct { using _: UI_View_Controller }

@(objc_class="UITableView")
UI_Table_View :: struct { using _: UI_View }

@(objc_class="UITableViewCell")
UI_Table_View_Cell :: struct { using _: UI_View }

@(objc_class="UIListContentConfiguration")
UI_List_Content_Configuration :: struct { using _: NS.Object }

@(objc_class="NSIndexPath")
Index_Path :: struct { using _: NS.Object }

@(objc_class="UIStackView")
UI_Stack_View :: struct { using _: UI_View }

@(objc_class="UILabel")
UI_Label :: struct { using _: UI_View }

@(objc_class="UIFont")
UI_Font :: struct { using _: NS.Object }

@(objc_class="UITextField")
UI_Text_Field :: struct { using _: UI_View }

@(objc_class="UIButton")
UI_Button :: struct { using _: UI_View }

@(objc_class="UIColor")
UI_Color :: struct { using _: NS.Object }

@(objc_class="UILayoutGuide")
UI_Layout_Guide :: struct { using _: NS.Object }

@(objc_class="NSLayoutAnchor")
Layout_Anchor :: struct { using _: NS.Object }

UI_TABLE_VIEW_STYLE_PLAIN        :: NS.Integer(0)
UI_TABLE_VIEW_AUTOMATIC_DIMENSION :: NS.Float(-1)
UI_TABLE_VIEW_CELL_STYLE_DEFAULT  :: NS.Integer(0)

UI_TEXT_BORDER_STYLE_ROUNDED_RECT       :: NS.Integer(3)
UI_RETURN_KEY_DONE                      :: NS.Integer(9)
UI_BUTTON_TYPE_SYSTEM                   :: NS.Integer(1)
UI_CONTROL_STATE_NORMAL                 :: NS.UInteger(0)
UI_CONTROL_EVENT_TOUCH_UP_INSIDE        :: NS.UInteger(1 << 6)
UI_CONTROL_EVENT_EDITING_CHANGED        :: NS.UInteger(1 << 17)
UI_CONTROL_EVENT_EDITING_DID_END_ON_EXIT :: NS.UInteger(1 << 19) // Return; also dismisses the keyboard

// Returns an owned (+1) window.
ui_window_new :: proc "c" (scene: NS.id) -> ^UI_Window {
	w := send(^UI_Window, UI_Window, "alloc")
	return send(^UI_Window, w, "initWithWindowScene:", scene)
}

ui_window_set_root_view_controller :: proc "c" (w: ^UI_Window, vc: ^UI_View_Controller) {
	send(nil, w, "setRootViewController:", vc)
}

ui_window_make_key_and_visible :: proc "c" (w: ^UI_Window) {
	send(nil, w, "makeKeyAndVisible")
}

// Returns an owned (+1) view.
ui_view_new :: proc "c" () -> ^UI_View {
	return send(^UI_View, UI_View, "new")
}

ui_view_set_background_color :: proc "c" (v: ^UI_View, c: ^UI_Color) {
	send(nil, v, "setBackgroundColor:", c)
}

ui_color_system_background :: proc "c" () -> ^UI_Color {
	return send(^UI_Color, UI_Color, "systemBackgroundColor")
}

// Adds `child` to `parent` and pins its edges to the parent's safe area.
ui_view_pin_to_safe_area :: proc "c" (child, parent: ^UI_View) {
	send(nil, child, "setTranslatesAutoresizingMaskIntoConstraints:", NS.BOOL(false))
	send(nil, parent, "addSubview:", child)
	guide := send(^UI_Layout_Guide, parent, "safeAreaLayoutGuide")
	layout_anchor_equal(send(^Layout_Anchor, child, "topAnchor"), send(^Layout_Anchor, guide, "topAnchor"))
	layout_anchor_equal(send(^Layout_Anchor, child, "bottomAnchor"), send(^Layout_Anchor, guide, "bottomAnchor"))
	layout_anchor_equal(send(^Layout_Anchor, child, "leadingAnchor"), send(^Layout_Anchor, guide, "leadingAnchor"))
	layout_anchor_equal(send(^Layout_Anchor, child, "trailingAnchor"), send(^Layout_Anchor, guide, "trailingAnchor"))
}

// Activates `a == b`.
layout_anchor_equal :: proc "c" (a, b: ^Layout_Anchor) {
	c := send(^Layout_Constraint, a, "constraintEqualToAnchor:", b)
	send(nil, c, "setActive:", NS.BOOL(true))
}

// Returns an owned (+1) controller.
ui_view_controller_new :: proc "c" () -> ^UI_View_Controller {
	return send(^UI_View_Controller, UI_View_Controller, "new")
}

ui_view_controller_set_view :: proc "c" (vc: ^UI_View_Controller, v: ^UI_View) {
	send(nil, vc, "setView:", v)
}

ui_view_controller_set_title :: proc "c" (vc: ^UI_View_Controller, s: ^NS.String) {
	send(nil, vc, "setTitle:", s)
}

// Returns an owned (+1) controller.
ui_navigation_controller_new :: proc "c" (root: ^UI_View_Controller) -> ^UI_Navigation_Controller {
	nc := send(^UI_Navigation_Controller, UI_Navigation_Controller, "alloc")
	return send(^UI_Navigation_Controller, nc, "initWithRootViewController:", root)
}

// Returns an owned (+1) table view.
ui_table_view_new :: proc "c" (style: NS.Integer) -> ^UI_Table_View {
	tv := send(^UI_Table_View, UI_Table_View, "alloc")
	return send(^UI_Table_View, tv, "initWithFrame:style:", NS.Rect{}, style)
}

ui_table_view_set_data_source :: proc "c" (tv: ^UI_Table_View, ds: NS.id) {
	send(nil, tv, "setDataSource:", ds)
}

ui_table_view_set_delegate :: proc "c" (tv: ^UI_Table_View, d: NS.id) {
	send(nil, tv, "setDelegate:", d)
}

ui_table_view_set_row_height :: proc "c" (tv: ^UI_Table_View, h: NS.Float) {
	send(nil, tv, "setRowHeight:", h)
}

ui_table_view_set_estimated_row_height :: proc "c" (tv: ^UI_Table_View, h: NS.Float) {
	send(nil, tv, "setEstimatedRowHeight:", h)
}

ui_table_view_reload_data :: proc "c" (tv: ^UI_Table_View) {
	send(nil, tv, "reloadData")
}

ui_table_view_dequeue_cell :: proc "c" (tv: ^UI_Table_View, ident: ^NS.String) -> ^UI_Table_View_Cell {
	return send(^UI_Table_View_Cell, tv, "dequeueReusableCellWithIdentifier:", ident)
}

ui_table_view_deselect_row :: proc "c" (tv: ^UI_Table_View, ip: ^Index_Path, animated: NS.BOOL) {
	send(nil, tv, "deselectRowAtIndexPath:animated:", ip, animated)
}

// Autoreleased.
ui_table_view_cell_new :: proc "c" (style: NS.Integer, ident: ^NS.String) -> ^UI_Table_View_Cell {
	c := send(^UI_Table_View_Cell, UI_Table_View_Cell, "alloc")
	c = send(^UI_Table_View_Cell, c, "initWithStyle:reuseIdentifier:", style, ident)
	send(nil, c, "autorelease")
	return c
}

ui_table_view_cell_set_content_configuration :: proc "c" (c: ^UI_Table_View_Cell, cfg: ^UI_List_Content_Configuration) {
	send(nil, c, "setContentConfiguration:", cfg)
}

// Autoreleased.
ui_list_content_subtitle :: proc "c" () -> ^UI_List_Content_Configuration {
	return send(^UI_List_Content_Configuration, UI_List_Content_Configuration, "subtitleCellConfiguration")
}

ui_list_content_set_text :: proc "c" (cfg: ^UI_List_Content_Configuration, s: ^NS.String) {
	send(nil, cfg, "setText:", s)
}

ui_list_content_set_secondary_text :: proc "c" (cfg: ^UI_List_Content_Configuration, s: ^NS.String) {
	send(nil, cfg, "setSecondaryText:", s)
}

index_path_row :: proc "c" (ip: ^Index_Path) -> NS.Integer {
	return send(NS.Integer, ip, "row")
}

// axis: UILayoutConstraintAxis, same values as Axis.
ui_view_set_content_hugging_priority :: proc "c" (v: ^UI_View, priority: f32, axis: NS.Integer) {
	send(nil, v, "setContentHuggingPriority:forAxis:", priority, axis)
}

// Returns an owned (+1) stack view. Distribution and alignment default to Fill.
ui_stack_view_new :: proc "c" () -> ^UI_Stack_View {
	sv := send(^UI_Stack_View, UI_Stack_View, "alloc")
	return send(^UI_Stack_View, sv, "initWithFrame:", NS.Rect{})
}

// UILayoutConstraintAxis, same values as Axis.
ui_stack_view_set_axis :: proc "c" (sv: ^UI_Stack_View, axis: NS.Integer) {
	send(nil, sv, "setAxis:", axis)
}

ui_stack_view_set_spacing :: proc "c" (sv: ^UI_Stack_View, spacing: NS.Float) {
	send(nil, sv, "setSpacing:", spacing)
}

// Also clears translatesAutoresizingMaskIntoConstraints on the child.
ui_stack_view_add_arranged_subview :: proc "c" (sv: ^UI_Stack_View, v: ^UI_View) {
	send(nil, sv, "addArrangedSubview:", v)
}

// Returns an owned (+1) label.
ui_label_new :: proc "c" () -> ^UI_Label {
	return send(^UI_Label, UI_Label, "new")
}

ui_label_set_text :: proc "c" (l: ^UI_Label, s: ^NS.String) {
	send(nil, l, "setText:", s)
}

ui_label_set_font :: proc "c" (l: ^UI_Label, f: ^UI_Font) {
	send(nil, l, "setFont:", f)
}

ui_font_bold_system :: proc "c" (size: NS.Float) -> ^UI_Font {
	return send(^UI_Font, UI_Font, "boldSystemFontOfSize:", size)
}

// Returns an owned (+1) text field.
ui_text_field_new :: proc "c" () -> ^UI_Text_Field {
	return send(^UI_Text_Field, UI_Text_Field, "new")
}

ui_text_field_set_text :: proc "c" (tf: ^UI_Text_Field, s: ^NS.String) {
	send(nil, tf, "setText:", s)
}

ui_text_field_text :: proc "c" (tf: ^UI_Text_Field) -> ^NS.String {
	return send(^NS.String, tf, "text")
}

ui_text_field_set_placeholder :: proc "c" (tf: ^UI_Text_Field, s: ^NS.String) {
	send(nil, tf, "setPlaceholder:", s)
}

ui_text_field_set_border_style :: proc "c" (tf: ^UI_Text_Field, style: NS.Integer) {
	send(nil, tf, "setBorderStyle:", style)
}

ui_text_field_set_return_key_type :: proc "c" (tf: ^UI_Text_Field, t: NS.Integer) {
	send(nil, tf, "setReturnKeyType:", t)
}

// Autoreleased.
ui_button_system :: proc "c" () -> ^UI_Button {
	return send(^UI_Button, UI_Button, "buttonWithType:", UI_BUTTON_TYPE_SYSTEM)
}

ui_button_set_title :: proc "c" (b: ^UI_Button, title: ^NS.String) {
	send(nil, b, "setTitle:forState:", title, UI_CONTROL_STATE_NORMAL)
}

// UIControl target-action; the control does not retain `target`.
ui_control_add_target :: proc "c" (c: ^UI_View, target: NS.id, action: NS.SEL, events: NS.UInteger) {
	send(nil, c, "addTarget:action:forControlEvents:", target, action, events)
}

}
