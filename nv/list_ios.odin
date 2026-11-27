#+build darwin:ios
#+private
package nv

// iOS list backend: UITableView with cell reuse.

import NS "core:sys/darwin/Foundation"

@(private) list_class: NS.Class

@(private)
_list_init :: proc(h: ^List_Handle) {
	table := objc_own(ui_table_view_new(UI_TABLE_VIEW_STYLE_PLAIN))
	// Self-sizing rows; item_height is only an estimate since UIKit's subtitle cell needs ~60pt.
	ui_table_view_set_row_height(table, UI_TABLE_VIEW_AUTOMATIC_DIMENSION)
	ui_table_view_set_estimated_row_height(table, NS.Float(h.list.item_height))

	ds := objc_own(list_data_source_alloc(h))
	ui_table_view_set_data_source(table, ds) // both weak
	ui_table_view_set_delegate(table, ds)
	objc_clear_data_source_on_dispose(table)
	objc_clear_delegate_on_dispose(table)

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
	cls := objc_class(&list_class, "NVListDataSource", "NSObject", {
		{"tableView:numberOfRowsInSection:", auto_cast number_of_rows, "q@:@q"},
		{"tableView:cellForRowAtIndexPath:", auto_cast cell_for_row, "@@:@@"},
		{"tableView:didSelectRowAtIndexPath:", auto_cast did_select_row, "v@:@@"},
	})
	return objc_alloc_with_handle(cls, h)
}

@(private)
number_of_rows :: proc "c" (self: NS.id, _: NS.SEL, _: ^UI_Table_View, _: NS.Integer) -> NS.Integer {
	h := objc_handle(self, List_Handle)
	context = h.ctx
	return NS.Integer(list_count(h))
}

@(private)
cell_for_row :: proc "c" (self: NS.id, _: NS.SEL, tv: ^UI_Table_View, ip: ^Index_Path) -> ^UI_Table_View_Cell {
	h := objc_handle(self, List_Handle)
	context = h.ctx
	callback_enter()
	defer callback_exit()

	cell := ui_table_view_dequeue_cell(tv, NS.AT(ROW_ID))
	if cell == nil {
		h.cells_created += 1
		cell = ui_table_view_cell_new(UI_TABLE_VIEW_CELL_STYLE_DEFAULT, NS.AT(ROW_ID))
	}

	r := list_item(h, int(index_path_row(ip)))
	cfg := ui_list_content_subtitle()
	ui_list_content_set_text(cfg, ns_string(r.title))
	ui_list_content_set_secondary_text(cfg, ns_string(r.subtitle))
	list_ios_style(send(^NS.Object, cfg, "textProperties"), h.list.title_style)
	list_ios_style(send(^NS.Object, cfg, "secondaryTextProperties"), h.list.subtitle_style)
	ui_table_view_cell_set_content_configuration(cell, cfg)
	return cell
}

// Styles a UIListContentTextProperties (the configuration's own, mutable in place).
@(private)
list_ios_style :: proc "contextless" (props: ^NS.Object, s: Text_Style) {
	if style_sets_font(s) do send(nil, props, "setFont:", apple_font(s, font_point_size(send(^NS.Object, props, "font")), false))
	if s.color.a > 0 do send(nil, props, "setColor:", canvas_color(s.color))
}

@(private)
did_select_row :: proc "c" (self: NS.id, _: NS.SEL, tv: ^UI_Table_View, ip: ^Index_Path) {
	h := objc_handle(self, List_Handle)
	context = h.ctx
	callback_enter()
	defer callback_exit()
	ui_table_view_deselect_row(tv, ip, true)
	if h.list.on_select != nil {
		list_select(h, int(index_path_row(ip)))
	}
}
