#+build darwin
package nv

// iOS list backend: UITableView with cell reuse.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private) list_class: NS.Class

@(private)
_list_init :: proc(h: ^List_Handle) {
	table := ui_table_view_new(UI_TABLE_VIEW_STYLE_PLAIN)
	// Self-sizing rows; row_height is only an estimate since UIKit's subtitle cell needs ~60pt.
	ui_table_view_set_row_height(table, UI_TABLE_VIEW_AUTOMATIC_DIMENSION)
	ui_table_view_set_estimated_row_height(table, NS.Float(h.list.row_height))

	ds := list_data_source_alloc(h)
	ui_table_view_set_data_source(table, ds)
	ui_table_view_set_delegate(table, ds)

	h.root = View(table)
	h.table = table
	h.data_source = ds
}

@(private)
_list_reload :: proc(h: ^List_Handle) {
	ui_table_view_reload_data((^UI_Table_View)(h.table))
}

@(private)
list_data_source_alloc :: proc(h: ^List_Handle) -> NS.id {
	if list_class == nil {
		list_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "NVListDataSource", 0)
		NS.class_addMethod(list_class, intrinsics.objc_find_selector("tableView:numberOfRowsInSection:"), auto_cast number_of_rows, "q@:@q")
		NS.class_addMethod(list_class, intrinsics.objc_find_selector("tableView:cellForRowAtIndexPath:"), auto_cast cell_for_row, "@@:@@")
		NS.class_addMethod(list_class, intrinsics.objc_find_selector("tableView:didSelectRowAtIndexPath:"), auto_cast did_select_row, "v@:@@")
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
number_of_rows :: proc "c" (self: NS.id, _: NS.SEL, _: ^UI_Table_View, _: NS.Integer) -> NS.Integer {
	h := handle_of(self)
	context = h.ctx
	return NS.Integer(h.list.count(h.list.user))
}

@(private)
cell_for_row :: proc "c" (self: NS.id, _: NS.SEL, tv: ^UI_Table_View, ip: ^Index_Path) -> ^UI_Table_View_Cell {
	h := handle_of(self)
	context = h.ctx

	cell := ui_table_view_dequeue_cell(tv, NS.AT(ROW_ID))
	if cell == nil {
		h.cells_created += 1
		cell = ui_table_view_cell_new(UI_TABLE_VIEW_CELL_STYLE_DEFAULT, NS.AT(ROW_ID))
	}

	r := h.list.row(h.list.user, int(index_path_row(ip)))
	cfg := ui_list_content_subtitle()
	ui_list_content_set_text(cfg, ns_string(r.title))
	ui_list_content_set_secondary_text(cfg, ns_string(r.subtitle))
	ui_table_view_cell_set_content_configuration(cell, cfg)
	free_all(context.temp_allocator)
	return cell
}

@(private)
did_select_row :: proc "c" (self: NS.id, _: NS.SEL, tv: ^UI_Table_View, ip: ^Index_Path) {
	h := handle_of(self)
	context = h.ctx
	ui_table_view_deselect_row(tv, ip, true)
	if h.list.on_select != nil {
		h.list.on_select(h.list.user, int(index_path_row(ip)))
	}
}

}
