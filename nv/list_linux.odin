#+build linux:default
package nv

// Linux list backend: GtkListView inside a GtkScrolledWindow, rows recycled through a
// GtkSignalListItemFactory (setup creates a cell, bind fills it by position).
//
// GtkListView needs a GListModel, so "NVListModel" is a GObject type registered at runtime
// (like the ObjC delegate classes) that stores a ^List_Handle after the GObject fields. Its
// items are throwaway GObjects: the row content comes from `list.row` during bind. A fresh
// item per position matters, because GTK only rebinds a row whose item object changed.

import "core:strings"

@(private) model_type:   GType
@(private) model_offset: guint // ^Model_Data lives at this offset inside a model instance

@(private) Model_Data :: struct {
	h:     ^List_Handle,
	known: guint, // item count last reported to GTK, needed by items-changed on reload
}

@(private)
_list_init :: proc(h: ^List_Handle) {
	model := model_new(h)

	sel := gtk_single_selection_new(model) // takes over the model reference
	// Construction auto-selected row 0; start unselected like the other platforms.
	gtk_single_selection_set_autoselect(sel, false)
	gtk_single_selection_set_can_unselect(sel, true)
	gtk_single_selection_set_selected(sel, GTK_INVALID_LIST_POSITION)
	g_signal_connect(sel, "selection-changed", rawptr(on_selection_changed), h)

	factory := gtk_signal_list_item_factory_new()
	g_signal_connect(factory, "setup", rawptr(on_setup), h)
	g_signal_connect(factory, "bind", rawptr(on_bind), h)

	list := gtk_list_view_new(sel, factory) // takes over both references

	scroll := gtk_scrolled_window_new()
	gtk_scrolled_window_set_child(scroll, list)
	gtk_widget_set_hexpand(scroll, true)
	gtk_widget_set_vexpand(scroll, true)

	h.root = View(scroll)
	h.table = list
	h.data_source = model
}

@(private)
_list_reload :: proc(h: ^List_Handle) {
	d := model_data(h.data_source)
	n := guint(h.list.count(h.list.user))
	old := d.known
	d.known = n
	g_list_model_items_changed(h.data_source, 0, old, n)
}

@(private)
model_new :: proc(h: ^List_Handle) -> ^GObject {
	if model_type == 0 {
		q: GTypeQuery
		g_type_query(g_object_get_type(), &q)
		model_offset = q.instance_size
		model_type = g_type_register_static_simple(g_object_get_type(), "NVListModel",
			q.class_size, nil, q.instance_size + size_of(Model_Data), nil, 0)
		@(static) iface := GInterfaceInfo{interface_init = model_iface_init}
		g_type_add_interface_static(model_type, g_list_model_get_type(), &iface)
	}
	obj := g_object_new(model_type, nil)
	model_data(obj)^ = {h = h}
	return obj
}

@(private)
model_data :: #force_inline proc "contextless" (obj: rawptr) -> ^Model_Data {
	return (^Model_Data)(uintptr(obj) + uintptr(model_offset))
}

@(private)
model_iface_init :: proc "c" (iface: gpointer, _: gpointer) {
	i := (^GListModelInterface)(iface)
	i.get_item_type = proc "c" (_: gpointer) -> GType { return g_object_get_type() }
	i.get_n_items = proc "c" (list: gpointer) -> guint {
		d := model_data(list)
		context = d.h.ctx
		d.known = guint(d.h.list.count(d.h.list.user))
		return d.known
	}
	i.get_item = proc "c" (list: gpointer, position: guint) -> gpointer {
		d := model_data(list)
		context = d.h.ctx
		if int(position) >= d.h.list.count(d.h.list.user) do return nil
		return g_object_new(g_object_get_type(), nil) // caller owns the reference
	}
}

@(private)
on_selection_changed :: proc "c" (sel: ^GtkSingleSelection, _, _: guint, user: gpointer) {
	h := (^List_Handle)(user)
	context = h.ctx
	callback_enter()
	defer callback_exit()
	if h.list.on_select == nil do return
	row := gtk_single_selection_get_selected(sel)
	if row != GTK_INVALID_LIST_POSITION do h.list.on_select(h.list.user, int(row))
}

// Cell: vertical box with title above subtitle. Each label expands into half the row and
// hugs the middle, so the pair sits vertically centred at any row height.
@(private)
on_setup :: proc "c" (_: ^GtkListItemFactory, item: ^GtkListItem, user: gpointer) {
	h := (^List_Handle)(user)
	context = h.ctx
	h.cells_created += 1

	cell := gtk_box_new(.Vertical, 2)
	gtk_widget_set_margin_start(cell, 12)
	gtk_widget_set_margin_end(cell, 12)
	gtk_widget_set_size_request(cell, -1, i32(h.list.row_height))

	title := gtk_label_new("")
	gtk_label_set_xalign(title, 0)
	gtk_label_set_ellipsize(title, .End)
	gtk_widget_add_css_class(title, "heading")
	gtk_widget_set_vexpand(title, true)
	gtk_widget_set_valign(title, .End)
	gtk_box_append(cell, title)

	subtitle := gtk_label_new("")
	gtk_label_set_xalign(subtitle, 0)
	gtk_label_set_ellipsize(subtitle, .End)
	gtk_widget_add_css_class(subtitle, "caption")
	gtk_widget_add_css_class(subtitle, "dim-label")
	gtk_widget_set_vexpand(subtitle, true)
	gtk_widget_set_valign(subtitle, .Start)
	gtk_box_append(cell, subtitle)

	gtk_list_item_set_child(item, cell)
}

@(private)
on_bind :: proc "c" (_: ^GtkListItemFactory, item: ^GtkListItem, user: gpointer) {
	h := (^List_Handle)(user)
	context = h.ctx
	callback_enter()
	defer callback_exit()

	cell := gtk_list_item_get_child(item)
	title := gtk_widget_get_first_child(cell)
	subtitle := gtk_widget_get_next_sibling(title)

	r := h.list.item(h.list.user, int(gtk_list_item_get_position(item)))
	gtk_label_set_text(title, strings.clone_to_cstring(r.title, context.temp_allocator))
	gtk_label_set_text(subtitle, strings.clone_to_cstring(r.subtitle, context.temp_allocator))
}
