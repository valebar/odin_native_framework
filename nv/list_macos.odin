#+build darwin:default
package nv

// macOS list backend: NSTableView inside NSScrollView, with cell reuse.

import NS "core:sys/darwin/Foundation"

@(private) TAG_TITLE    :: 1
@(private) TAG_SUBTITLE :: 2

@(private) list_class: NS.Class

@(private)
_list_init :: proc(h: ^List_Handle) {
	frame := NS.Rect{{0, 0}, {400, 600}}
	scroll := objc_own(scroll_view_new(frame))
	scroll_view_set_has_vertical_scroller(scroll, true)
	view_set_autoresizing(scroll, RESIZE_WIDTH | RESIZE_HEIGHT)

	table := objc_own(table_view_new(frame)) // the scroll view retains it too (setDocumentView:)
	table_view_set_style(table, Table_View_Style_Plain)
	table_view_set_header_view(table, nil)
	table_view_set_row_height(table, NS.Float(h.list.item_height))

	col := table_column_new(NS.AT("main"))
	table_column_set_resizing_mask(col, 1) // NSTableColumnAutoresizingMask
	table_view_add_column(table, col)
	col->release()

	ds := objc_own(list_data_source_alloc(h))
	table_view_set_data_source(table, ds) // both weak
	table_view_set_delegate(table, ds)
	objc_clear_data_source_on_dispose(table)
	objc_clear_delegate_on_dispose(table)

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
	cls := objc_class(&list_class, "NVListDataSource", "NSObject", {
		{"numberOfRowsInTableView:", auto_cast number_of_rows, "q@:@"},
		{"tableView:viewForTableColumn:row:", auto_cast view_for_row, "@@:@@q"},
		{"tableView:heightOfRow:", auto_cast height_of_row, "d@:@q"},
		{"tableViewSelectionDidChange:", auto_cast selection_did_change, "v@:@"},
	})
	return objc_alloc_with_handle(cls, h)
}

@(private)
number_of_rows :: proc "c" (self: NS.id, _: NS.SEL, _: ^Table_View) -> NS.Integer {
	h := objc_handle(self, List_Handle)
	context = h.ctx
	return NS.Integer(h.list.count(h.list.user))
}

@(private)
height_of_row :: proc "c" (self: NS.id, _: NS.SEL, _: ^Table_View, _: NS.Integer) -> NS.Float {
	return NS.Float(objc_handle(self, List_Handle).list.item_height)
}

@(private)
selection_did_change :: proc "c" (self: NS.id, _: NS.SEL, _: ^NS.Notification) {
	h := objc_handle(self, List_Handle)
	context = h.ctx
	callback_enter()
	defer callback_exit()
	if h.list.on_select == nil do return
	row := table_view_selected_row((^Table_View)(h.table))
	if row >= 0 do h.list.on_select(h.list.user, int(row))
}

@(private)
view_for_row :: proc "c" (self: NS.id, _: NS.SEL, tv: ^Table_View, _: ^Table_Column, row: NS.Integer) -> ^NS.View {
	h := objc_handle(self, List_Handle)
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
	height := NS.Float(h.list.item_height)

	cell := NS.View.alloc()->initWithFrame({{0, 0}, {width, height}})
	view_set_identifier(cell, NS.AT(ROW_ID))

	// Bold 13pt over 11pt by default; the pair is centred (the cell is not flipped: y grows upwards).
	title_font := apple_font(h.list.title_style, 13, true)
	subtitle_font := apple_font(h.list.subtitle_style, 11, false)
	title_h, subtitle_h := font_line_height(title_font), font_line_height(subtitle_font)
	bottom := (height - title_h - subtitle_h) / 2

	title := text_field_label(NS.AT(""))
	text_field_set_font(title, (^NS_Font)(title_font))
	if c := h.list.title_style.color; c.a > 0 do text_field_set_text_color(title, (^NS.Color)(canvas_color(c)))
	text_field_set_tag(title, TAG_TITLE)
	view_set_frame(title, {{8, bottom + subtitle_h}, {width - 16, title_h}})
	view_set_autoresizing(title, RESIZE_WIDTH)
	cell->addSubview(title)

	subtitle := text_field_label(NS.AT(""))
	text_field_set_font(subtitle, (^NS_Font)(subtitle_font))
	c := h.list.subtitle_style.color
	text_field_set_text_color(subtitle, c.a > 0 ? (^NS.Color)(canvas_color(c)) : color_secondary_label())
	text_field_set_tag(subtitle, TAG_SUBTITLE)
	view_set_frame(subtitle, {{8, bottom}, {width - 16, subtitle_h}})
	view_set_autoresizing(subtitle, RESIZE_WIDTH)
	cell->addSubview(subtitle)

	cell->autorelease()
	return cell
}
