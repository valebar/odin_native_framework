#+build darwin:default
package nv

// Minimal hand-written AppKit bindings not covered by core:sys/darwin/Foundation, for the macOS
// backend only; what it shares with the iOS backend is in appkit.odin.

import NS "core:sys/darwin/Foundation"

// NSAutoresizingMaskOptions
RESIZE_MIN_X_MARGIN :: NS.UInteger(1)
RESIZE_WIDTH        :: NS.UInteger(2)
RESIZE_MAX_X_MARGIN :: NS.UInteger(4)
RESIZE_MIN_Y_MARGIN :: NS.UInteger(8)
RESIZE_HEIGHT       :: NS.UInteger(16)
RESIZE_MAX_Y_MARGIN :: NS.UInteger(32)

// NSLayoutAttributeLeading: a titlebar accessory next to the window buttons (macOS 11+);
// Trailing: at the far end of the title bar.
LAYOUT_ATTRIBUTE_LEADING  :: NS.Integer(5)
LAYOUT_ATTRIBUTE_TRAILING :: NS.Integer(6)

// NSBezelStyleTexturedRounded (NSBezelStyleToolbar): the look of a title bar button.
BEZEL_STYLE_TEXTURED_ROUNDED :: NS.Integer(11)

@(objc_class="NSTitlebarAccessoryViewController")
Titlebar_Accessory_View_Controller :: struct { using _: NS.Object }

Table_View_Style_Plain :: 4

@(objc_class="NSScrollView")
Scroll_View :: struct { using _: NS.View }

@(objc_class="NSStackView")
Stack_View :: struct { using _: NS.View }

// NSStackViewDistribution (GravityAreas is -1, so Fill is 0 like UIStackViewDistributionFill).
STACK_DISTRIBUTION_FILL :: NS.Integer(0)

@(objc_class="NSTableView")
Table_View :: struct { using _: NS.View }

@(objc_class="NSTableColumn")
Table_Column :: struct { using _: NS.Object }

@(objc_class="NSTextField")
Text_Field :: struct { using _: NS.View }

@(objc_class="NSButton")
Button_View :: struct { using _: NS.View }

@(objc_class="NSFont")
NS_Font :: struct { using _: NS.Object } // `Font` is the public loaded-font type

@(objc_class="NSColorSpace")
Color_Space :: struct { using _: NS.Object }

@(objc_class="NSAppearance")
Appearance :: struct { using _: NS.Object }

@(objc_class="NSGraphicsContext")
Graphics_Context :: struct { using _: NS.Object }

@(objc_class="NSBox")
Box :: struct { using _: NS.View }

// NSBoxCustom: no title, the fill and corner radius are the box's own.
BOX_TYPE_CUSTOM   :: NS.Integer(4)
BOX_TITLE_NONE    :: NS.Integer(0)

view_set_frame :: proc "c" (v: ^NS.View, frame: NS.Rect) {
	send(nil, v, "setFrame:", frame)
}

view_set_hidden :: proc "c" (v: ^NS.View, hidden: NS.BOOL) {
	send(nil, v, "setHidden:", hidden)
}

view_remove_from_superview :: proc "c" (v: ^NS.View) {
	send(nil, v, "removeFromSuperview")
}

// Returns an owned (+1) custom box: a plain filled rectangle with optional rounded corners.
box_new :: proc "c" (frame: NS.Rect) -> ^Box {
	b := send(^Box, Box, "alloc")
	b = send(^Box, b, "initWithFrame:", frame)
	send(nil, b, "setBoxType:", BOX_TYPE_CUSTOM)
	send(nil, b, "setTitlePosition:", BOX_TITLE_NONE)
	send(nil, b, "setBorderWidth:", NS.Float(0))
	send(nil, b, "setContentViewMargins:", NS.Size{0, 0})
	return b
}

box_set_fill_color :: proc "c" (b: ^Box, c: ^NS.Color) {
	send(nil, b, "setFillColor:", c)
}

box_set_corner_radius :: proc "c" (b: ^Box, r: NS.Float) {
	send(nil, b, "setCornerRadius:", r)
}

// The border of a custom box, drawn inside its bounds.
box_set_border :: proc "c" (b: ^Box, c: ^NS.Color, width: NS.Float) {
	send(nil, b, "setBorderColor:", c)
	send(nil, b, "setBorderWidth:", width)
}

// The box's inner view, which holds its subviews.
box_content_view :: proc "c" (b: ^Box) -> ^NS.View {
	return send(^NS.View, b, "contentView")
}

color_window_background :: proc "c" () -> ^NS.Color {
	return send(^NS.Color, NS.Color, "windowBackgroundColor")
}

view_set_autoresizing :: proc "c" (v: ^NS.View, mask: NS.UInteger) {
	send(nil, v, "setAutoresizingMask:", mask)
}

view_with_tag :: proc "c" (v: ^NS.View, tag: NS.Integer) -> ^NS.View {
	return send(^NS.View, v, "viewWithTag:", tag)
}

view_set_tool_tip :: proc "c" (v: ^NS.View, s: ^NS.String) {
	send(nil, v, "setToolTip:", s)
}

view_set_identifier :: proc "c" (v: ^NS.View, ident: ^NS.String) {
	send(nil, v, "setIdentifier:", ident)
}

view_set_translates_autoresizing_mask :: proc "c" (v: ^NS.View, translates: NS.BOOL) {
	send(nil, v, "setTranslatesAutoresizingMaskIntoConstraints:", translates)
}

// orientation: NSLayoutConstraintOrientation, same values as Axis.
view_set_content_hugging_priority :: proc "c" (v: ^NS.View, priority: f32, orientation: NS.Integer) {
	send(nil, v, "setContentHuggingPriority:forOrientation:", priority, orientation)
}

view_set_content_compression_resistance_priority :: proc "c" (v: ^NS.View, priority: f32, orientation: NS.Integer) {
	send(nil, v, "setContentCompressionResistancePriority:forOrientation:", priority, orientation)
}

// Returns an owned (+1) stack view.
stack_view_new :: proc "c" (frame: NS.Rect) -> ^Stack_View {
	sv := send(^Stack_View, Stack_View, "alloc")
	return send(^Stack_View, sv, "initWithFrame:", frame)
}

// NSUserInterfaceLayoutOrientation, same values as Axis.
stack_view_set_orientation :: proc "c" (sv: ^Stack_View, orientation: NS.Integer) {
	send(nil, sv, "setOrientation:", orientation)
}

stack_view_set_spacing :: proc "c" (sv: ^Stack_View, spacing: NS.Float) {
	send(nil, sv, "setSpacing:", spacing)
}

stack_view_set_distribution :: proc "c" (sv: ^Stack_View, distribution: NS.Integer) {
	send(nil, sv, "setDistribution:", distribution)
}

// NSLayoutAttribute; Width / Height stretch children across the cross axis.
stack_view_set_alignment :: proc "c" (sv: ^Stack_View, alignment: NS.Integer) {
	send(nil, sv, "setAlignment:", alignment)
}

stack_view_add_arranged_subview :: proc "c" (sv: ^Stack_View, v: ^NS.View) {
	send(nil, sv, "addArrangedSubview:", v)
}

scroll_view_new :: proc "c" (frame: NS.Rect) -> ^Scroll_View {
	sv := send(^Scroll_View, Scroll_View, "alloc")
	return send(^Scroll_View, sv, "initWithFrame:", frame)
}

scroll_view_set_document_view :: proc "c" (sv: ^Scroll_View, v: ^NS.View) {
	send(nil, sv, "setDocumentView:", v)
}

scroll_view_set_has_vertical_scroller :: proc "c" (sv: ^Scroll_View, has: NS.BOOL) {
	send(nil, sv, "setHasVerticalScroller:", has)
}

table_view_new :: proc "c" (frame: NS.Rect) -> ^Table_View {
	tv := send(^Table_View, Table_View, "alloc")
	return send(^Table_View, tv, "initWithFrame:", frame)
}

table_view_add_column :: proc "c" (tv: ^Table_View, col: ^Table_Column) {
	send(nil, tv, "addTableColumn:", col)
}

table_view_set_data_source :: proc "c" (tv: ^Table_View, ds: NS.id) {
	send(nil, tv, "setDataSource:", ds)
}

table_view_set_delegate :: proc "c" (tv: ^Table_View, d: NS.id) {
	send(nil, tv, "setDelegate:", d)
}

table_view_set_header_view :: proc "c" (tv: ^Table_View, v: ^NS.View) {
	send(nil, tv, "setHeaderView:", v)
}

table_view_set_style :: proc "c" (tv: ^Table_View, style: NS.Integer) {
	send(nil, tv, "setStyle:", style)
}

table_view_set_row_height :: proc "c" (tv: ^Table_View, h: NS.Float) {
	send(nil, tv, "setRowHeight:", h)
}

table_view_reload_data :: proc "c" (tv: ^Table_View) {
	send(nil, tv, "reloadData")
}

table_view_make_view :: proc "c" (tv: ^Table_View, ident: ^NS.String) -> ^NS.View {
	return send(^NS.View, tv, "makeViewWithIdentifier:owner:", ident, NS.id(nil))
}

table_view_selected_row :: proc "c" (tv: ^Table_View) -> NS.Integer {
	return send(NS.Integer, tv, "selectedRow")
}

table_view_size_last_column_to_fit :: proc "c" (tv: ^Table_View) {
	send(nil, tv, "sizeLastColumnToFit")
}

// Returns an owned (+1) column.
table_column_new :: proc "c" (ident: ^NS.String) -> ^Table_Column {
	col := send(^Table_Column, Table_Column, "alloc")
	return send(^Table_Column, col, "initWithIdentifier:", ident)
}

table_column_set_resizing_mask :: proc "c" (col: ^Table_Column, mask: NS.UInteger) {
	send(nil, col, "setResizingMask:", mask)
}

// Autoreleased.
text_field_label :: proc "c" (s: ^NS.String) -> ^Text_Field {
	return send(^Text_Field, Text_Field, "labelWithString:", s)
}

text_field_set_string :: proc "c" (tf: ^Text_Field, s: ^NS.String) {
	send(nil, tf, "setStringValue:", s)
}

text_field_set_font :: proc "c" (tf: ^Text_Field, f: ^NS_Font) {
	send(nil, tf, "setFont:", f)
}

text_field_set_text_color :: proc "c" (tf: ^Text_Field, c: ^NS.Color) {
	send(nil, tf, "setTextColor:", c)
}

text_field_set_tag :: proc "c" (tf: ^Text_Field, tag: NS.Integer) {
	send(nil, tf, "setTag:", tag)
}

// Autoreleased editable field: single line, non-wrapping, scrolls horizontally.
text_field_editable :: proc "c" (s: ^NS.String) -> ^Text_Field {
	return send(^Text_Field, Text_Field, "textFieldWithString:", s)
}

text_field_set_placeholder :: proc "c" (tf: ^Text_Field, s: ^NS.String) {
	send(nil, tf, "setPlaceholderString:", s)
}

text_field_set_delegate :: proc "c" (tf: ^Text_Field, d: NS.id) {
	send(nil, tf, "setDelegate:", d)
}

text_field_string :: proc "c" (tf: ^Text_Field) -> ^NS.String {
	return send(^NS.String, tf, "stringValue")
}

// Autoreleased bezel push button; `target` is weak.
button_push :: proc "c" (title: ^NS.String, target: NS.id, action: NS.SEL) -> ^Button_View {
	return send(^Button_View, Button_View, "buttonWithTitle:target:action:", title, target, action)
}

button_set_title_ns :: proc "c" (b: ^Button_View, title: ^NS.String) {
	send(nil, b, "setTitle:", title)
}

// Autoreleased image-only bezel button; `target` is weak.
button_with_image :: proc "c" (image: ^NS.Image, target: NS.id, action: NS.SEL) -> ^Button_View {
	return send(^Button_View, Button_View, "buttonWithImage:target:action:", image, target, action)
}

button_set_bezel_style :: proc "c" (b: ^Button_View, style: NS.Integer) {
	send(nil, b, "setBezelStyle:", style)
}

// Autoreleased SF Symbol (macOS 11+).
image_system_symbol :: proc "c" (name: ^NS.String, description: ^NS.String) -> ^NS.Image {
	return send(^NS.Image, NS.Image, "imageWithSystemSymbolName:accessibilityDescription:", name, description)
}

// Returns an owned (+1) controller.
titlebar_accessory_new :: proc "c" () -> ^Titlebar_Accessory_View_Controller {
	return send(^Titlebar_Accessory_View_Controller, Titlebar_Accessory_View_Controller, "new")
}

titlebar_accessory_set_view :: proc "c" (vc: ^Titlebar_Accessory_View_Controller, v: ^NS.View) {
	send(nil, vc, "setView:", v)
}

// NSLayoutAttribute: Leading / Trailing sit in the title bar, Bottom adds a strip below it.
titlebar_accessory_set_layout_attribute :: proc "c" (vc: ^Titlebar_Accessory_View_Controller, attr: NS.Integer) {
	send(nil, vc, "setLayoutAttribute:", attr)
}

titlebar_accessory_set_hidden :: proc "c" (vc: ^Titlebar_Accessory_View_Controller, hidden: NS.BOOL) {
	send(nil, vc, "setHidden:", hidden)
}

// The window retains the controller.
window_add_titlebar_accessory :: proc "c" (w: ^NS.Window, vc: ^Titlebar_Accessory_View_Controller) {
	send(nil, w, "addTitlebarAccessoryViewController:", vc)
}

// Removes `vc` from the window's titlebarAccessoryViewControllers, releasing it.
window_remove_titlebar_accessory :: proc "c" (w: ^NS.Window, vc: ^Titlebar_Accessory_View_Controller) {
	all := send(^NS.Array, w, "titlebarAccessoryViewControllers")
	index := send(NS.UInteger, all, "indexOfObject:", vc)
	if index == NS.UInteger(NS.NotFound) do return
	send(nil, w, "removeTitlebarAccessoryViewControllerAtIndex:", NS.Integer(index))
}

font_system :: proc "c" (size: NS.Float) -> ^NS_Font {
	return send(^NS_Font, NS_Font, "systemFontOfSize:", size)
}

font_bold_system :: proc "c" (size: NS.Float) -> ^NS_Font {
	return send(^NS_Font, NS_Font, "boldSystemFontOfSize:", size)
}

color_secondary_label :: proc "c" () -> ^NS.Color {
	return send(^NS.Color, NS.Color, "secondaryLabelColor")
}
