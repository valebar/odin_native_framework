#+build darwin
package nv

// macOS list backend: NSTableView inside NSScrollView, with cell reuse.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private) TAG_TITLE    :: 1
@(private) TAG_SUBTITLE :: 2

@(private) list_class: NS.Class

@(private)
_list_init :: proc(h: ^List_Handle) {
	frame := NS.Rect{{0, 0}, {400, 600}}
	scroll := scroll_view_new(frame)
	scroll_view_set_has_vertical_scroller(scroll, true)
	view_set_autoresizing(scroll, RESIZE_WIDTH | RESIZE_HEIGHT)

	table := table_view_new(frame)
	table_view_set_style(table, Table_View_Style_Plain)
	table_view_set_header_view(table, nil)
	table_view_set_row_height(table, NS.Float(h.list.row_height))

	col := table_column_new(NS.AT("main"))
	table_column_set_resizing_mask(col, 1) // NSTableColumnAutoresizingMask
	table_view_add_column(table, col)
	col->release()

	ds := list_data_source_alloc(h)
	table_view_set_data_source(table, ds)
	table_view_set_delegate(table, ds)

	scroll_view_set_document_view(scroll, table)
	table_view_size_last_column_to_fit(table)

	h.root = View(scroll)
	h.table = table
	h.data_source = ds
}

@(private)
_list_reload :: proc(h: ^List_Handle) {
	table_view_reload_data((^Table_View)(h.table))
}

@(private)
list_data_source_alloc :: proc(h: ^List_Handle) -> NS.id {
	if list_class == nil {
		list_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "NVListDataSource", 0)
		NS.class_addMethod(list_class, intrinsics.objc_find_selector("numberOfRowsInTableView:"), auto_cast number_of_rows, "q@:@")
		NS.class_addMethod(list_class, intrinsics.objc_find_selector("tableView:viewForTableColumn:row:"), auto_cast view_for_row, "@@:@@q")
		NS.class_addMethod(list_class, intrinsics.objc_find_selector("tableView:heightOfRow:"), auto_cast height_of_row, "d@:@q")
		NS.class_addMethod(list_class, intrinsics.objc_find_selector("tableViewSelectionDidChange:"), auto_cast selection_did_change, "v@:@")
		NS.objc_registerClassPair(list_class)
	}
	obj := NS.class_createInstance(list_class, size_of(^List_Handle))
	(^^List_Handle)(NS.object_getIndexedIvars(obj))^ = h
	return obj
}

@(private)
handle_of :: #force_inline proc "c" (self: NS.id) -> ^List_Handle {
	return (^^List_Handle)(NS.object_getIndexedIvars(self))^
}

@(private)
number_of_rows :: proc "c" (self: NS.id, _: NS.SEL, _: ^Table_View) -> NS.Integer {
	h := handle_of(self)
	context = h.ctx
	return NS.Integer(h.list.count(h.list.user))
}

@(private)
height_of_row :: proc "c" (self: NS.id, _: NS.SEL, _: ^Table_View, _: NS.Integer) -> NS.Float {
	return NS.Float(handle_of(self).list.row_height)
}

@(private)
selection_did_change :: proc "c" (self: NS.id, _: NS.SEL, _: ^NS.Notification) {
	h := handle_of(self)
	context = h.ctx
	callback_enter()
	defer callback_exit()
	if h.list.on_select == nil do return
	row := table_view_selected_row((^Table_View)(h.table))
	if row >= 0 do h.list.on_select(h.list.user, int(row))
}

@(private)
view_for_row :: proc "c" (self: NS.id, _: NS.SEL, tv: ^Table_View, _: ^Table_Column, row: NS.Integer) -> ^NS.View {
	h := handle_of(self)
	context = h.ctx
	callback_enter()
	defer callback_exit()

	cell := table_view_make_view(tv, NS.AT(ROW_ID))
	if cell == nil {
		cell = make_row_cell(h)
	}

	r := h.list.item(h.list.user, int(row))
	text_field_set_string(cast(^Text_Field)view_with_tag(cell, TAG_TITLE), ns_string(r.title))
	text_field_set_string(cast(^Text_Field)view_with_tag(cell, TAG_SUBTITLE), ns_string(r.subtitle))
	return cell
}

// Autoreleased cell: title on top, subtitle below.
@(private)
make_row_cell :: proc(h: ^List_Handle) -> ^NS.View {
	h.cells_created += 1
	width := NS.Float(400)
	height := NS.Float(h.list.row_height)

	cell := NS.View.alloc()->initWithFrame({{0, 0}, {width, height}})
	view_set_identifier(cell, NS.AT(ROW_ID))

	title := text_field_label(NS.AT(""))
	text_field_set_font(title, font_bold_system(13))
	text_field_set_tag(title, TAG_TITLE)
	view_set_frame(title, {{8, height / 2}, {width - 16, 18}})
	view_set_autoresizing(title, RESIZE_WIDTH)
	cell->addSubview(title)

	subtitle := text_field_label(NS.AT(""))
	text_field_set_font(subtitle, font_system(11))
	text_field_set_text_color(subtitle, color_secondary_label())
	text_field_set_tag(subtitle, TAG_SUBTITLE)
	view_set_frame(subtitle, {{8, height / 2 - 18}, {width - 16, 16}})
	view_set_autoresizing(subtitle, RESIZE_WIDTH)
	cell->addSubview(subtitle)

	cell->autorelease()
	return cell
}

}
