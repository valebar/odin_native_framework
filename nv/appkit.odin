#+build darwin
package nv

// Minimal hand-written AppKit bindings not covered by core:sys/darwin/Foundation.
// `send`, `ns_string` and the Auto Layout helpers are shared with the iOS backend.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(private) send :: intrinsics.objc_send

// Copies bytes, so the Odin string may be freed afterwards. Autoreleased.
ns_string :: proc "c" (s: string) -> ^NS.String {
	str := send(^NS.String, NS.String, "alloc")
	str = send(^NS.String, str, "initWithBytes:length:encoding:", raw_data(s), NS.UInteger(len(s)), NS.StringEncoding.UTF8)
	send(nil, str, "autorelease")
	return str
}

// NSLayoutConstraint exists in both AppKit and UIKit.
@(objc_class="NSLayoutConstraint")
Layout_Constraint :: struct { using _: NS.Object }

// NSLayoutAttribute / NSLayoutRelation
LAYOUT_ATTRIBUTE_WIDTH  :: NS.Integer(7)
LAYOUT_ATTRIBUTE_HEIGHT :: NS.Integer(8)
LAYOUT_RELATION_EQUAL   :: NS.Integer(0)

// NSLayoutPriority / UILayoutPriority
LAYOUT_PRIORITY_REQUIRED :: f32(1000)
LAYOUT_PRIORITY_FLEX     :: f32(1)

// Activates `a.attr == b.attr * multiplier`.
layout_constraint_equal :: proc "c" (a: NS.id, b: NS.id, attr: NS.Integer, multiplier: NS.Float) {
	c := send(^Layout_Constraint, Layout_Constraint, "constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:constant:",
		a, attr, LAYOUT_RELATION_EQUAL, b, attr, multiplier, NS.Float(0))
	send(nil, c, "setActive:", NS.BOOL(true))
}

// Ties the main-axis size of every flex child to the first flex child, in the ratio of their
// weights. Together with a low hugging priority this gives exact Flutter weights in a stack view.
flex_link_sizes :: proc(children: []Flex_Child, axis: Axis) {
	attr := axis == .Vertical ? LAYOUT_ATTRIBUTE_HEIGHT : LAYOUT_ATTRIBUTE_WIDTH
	first: Flex_Child
	for c in children {
		if c.flex <= 0 do continue
		if first.view == nil {
			first = c
			continue
		}
		layout_constraint_equal(NS.id(c.view), NS.id(first.view), attr, NS.Float(c.flex) / NS.Float(first.flex))
	}
}

when !IS_IOS {

// NSAutoresizingMaskOptions
RESIZE_WIDTH        :: NS.UInteger(2)
RESIZE_MIN_Y_MARGIN :: NS.UInteger(8)
RESIZE_HEIGHT       :: NS.UInteger(16)

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

@(objc_class="NSFont")
Font :: struct { using _: NS.Object }

view_set_frame :: proc "c" (v: ^NS.View, frame: NS.Rect) {
	send(nil, v, "setFrame:", frame)
}

view_set_autoresizing :: proc "c" (v: ^NS.View, mask: NS.UInteger) {
	send(nil, v, "setAutoresizingMask:", mask)
}

view_with_tag :: proc "c" (v: ^NS.View, tag: NS.Integer) -> ^NS.View {
	return send(^NS.View, v, "viewWithTag:", tag)
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

text_field_set_font :: proc "c" (tf: ^Text_Field, f: ^Font) {
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

font_system :: proc "c" (size: NS.Float) -> ^Font {
	return send(^Font, Font, "systemFontOfSize:", size)
}

font_bold_system :: proc "c" (size: NS.Float) -> ^Font {
	return send(^Font, Font, "boldSystemFontOfSize:", size)
}

color_secondary_label :: proc "c" () -> ^NS.Color {
	return send(^NS.Color, NS.Color, "secondaryLabelColor")
}

}
