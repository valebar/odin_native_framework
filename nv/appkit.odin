#+build darwin
package nv

// Minimal hand-written AppKit bindings not covered by core:sys/darwin/Foundation.
// `send` and `ns_string` are shared with the iOS backend.

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

when !IS_IOS {

// NSAutoresizingMaskOptions
RESIZE_WIDTH        :: NS.UInteger(2)
RESIZE_MIN_Y_MARGIN :: NS.UInteger(8)
RESIZE_HEIGHT       :: NS.UInteger(16)

Table_View_Style_Plain :: 4

@(objc_class="NSScrollView")
Scroll_View :: struct { using _: NS.View }

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
