#+build linux:default
package nv

// Minimal hand-written GTK4 / GObject / GIO bindings used by the Linux backend.
// Names match the C API so the GTK docs apply directly.

foreign import gtk  "system:gtk-4"
foreign import gobj "system:gobject-2.0"
foreign import gio  "system:gio-2.0"

GType    :: distinct uint
gboolean :: b32
guint    :: u32
gulong   :: uint
gpointer :: rawptr

// Opaque instance types; only ever used behind a pointer.
GObject          :: struct {}
GtkWidget        :: struct {}
GtkApplication   :: struct {}
GtkListItem      :: struct {}
GtkSingleSelection :: struct {}
GtkListItemFactory :: struct {}

GTypeQuery :: struct {
	type:          GType,
	type_name:     cstring,
	class_size:    guint,
	instance_size: guint,
}

GInterfaceInfo :: struct {
	interface_init:     proc "c" (iface: gpointer, data: gpointer),
	interface_finalize: proc "c" (iface: gpointer, data: gpointer),
	interface_data:     gpointer,
}

GListModelInterface :: struct {
	g_iface:       [2]GType, // GTypeInterface: g_type, g_instance_type
	get_item_type: proc "c" (list: gpointer) -> GType,
	get_n_items:   proc "c" (list: gpointer) -> guint,
	get_item:      proc "c" (list: gpointer, position: guint) -> gpointer,
}

GtkOrientation :: enum i32 { Horizontal = 0, Vertical = 1 }
GtkAlign       :: enum i32 { Fill = 0, Start = 1, End = 2, Center = 3 }
PangoEllipsizeMode :: enum i32 { None = 0, Start = 1, Middle = 2, End = 3 }

G_APPLICATION_DEFAULT_FLAGS :: i32(0)
GTK_INVALID_LIST_POSITION   :: guint(0xffffffff)

@(default_calling_convention="c")
foreign gobj {
	g_object_get_type            :: proc() -> GType ---
	g_object_new                 :: proc(type: GType, first_property_name: cstring, #c_vararg args: ..any) -> ^GObject ---
	g_object_unref               :: proc(object: gpointer) ---
	g_type_query                 :: proc(type: GType, query: ^GTypeQuery) ---
	g_type_register_static_simple :: proc(parent: GType, name: cstring, class_size: guint, class_init: rawptr, instance_size: guint, instance_init: rawptr, flags: i32) -> GType ---
	g_type_add_interface_static  :: proc(instance_type, interface_type: GType, info: ^GInterfaceInfo) ---
	g_signal_connect_data        :: proc(instance: gpointer, detailed_signal: cstring, c_handler: rawptr, data: gpointer, destroy_data: rawptr, connect_flags: i32) -> gulong ---
}

@(default_calling_convention="c")
foreign gio {
	g_list_model_get_type      :: proc() -> GType ---
	g_list_model_items_changed :: proc(list: gpointer, position, removed, added: guint) ---
	g_application_run          :: proc(application: gpointer, argc: i32, argv: [^]cstring) -> i32 ---
}

@(default_calling_convention="c")
foreign gtk {
	gtk_application_new        :: proc(application_id: cstring, flags: i32) -> ^GtkApplication ---
	gtk_application_window_new :: proc(application: ^GtkApplication) -> ^GtkWidget ---
	gtk_window_set_title        :: proc(window: ^GtkWidget, title: cstring) ---
	gtk_window_set_default_size :: proc(window: ^GtkWidget, width, height: i32) ---
	gtk_window_set_child        :: proc(window: ^GtkWidget, child: ^GtkWidget) ---
	gtk_window_present          :: proc(window: ^GtkWidget) ---

	gtk_widget_set_margin_start  :: proc(widget: ^GtkWidget, margin: i32) ---
	gtk_widget_set_margin_end    :: proc(widget: ^GtkWidget, margin: i32) ---
	gtk_widget_set_size_request  :: proc(widget: ^GtkWidget, width, height: i32) ---
	gtk_widget_set_vexpand       :: proc(widget: ^GtkWidget, expand: gboolean) ---
	gtk_widget_set_hexpand       :: proc(widget: ^GtkWidget, expand: gboolean) ---
	gtk_widget_set_valign        :: proc(widget: ^GtkWidget, align: GtkAlign) ---
	gtk_widget_add_css_class     :: proc(widget: ^GtkWidget, css_class: cstring) ---
	gtk_widget_get_first_child   :: proc(widget: ^GtkWidget) -> ^GtkWidget ---
	gtk_widget_get_next_sibling  :: proc(widget: ^GtkWidget) -> ^GtkWidget ---

	gtk_scrolled_window_new       :: proc() -> ^GtkWidget ---
	gtk_scrolled_window_set_child :: proc(scrolled_window: ^GtkWidget, child: ^GtkWidget) ---

	gtk_box_new    :: proc(orientation: GtkOrientation, spacing: i32) -> ^GtkWidget ---
	gtk_box_append :: proc(box: ^GtkWidget, child: ^GtkWidget) ---

	gtk_label_new           :: proc(str: cstring) -> ^GtkWidget ---
	gtk_label_set_text      :: proc(label: ^GtkWidget, str: cstring) ---
	gtk_label_set_xalign    :: proc(label: ^GtkWidget, xalign: f32) ---
	gtk_label_set_ellipsize :: proc(label: ^GtkWidget, mode: PangoEllipsizeMode) ---

	gtk_list_view_new                :: proc(model: ^GtkSingleSelection, factory: ^GtkListItemFactory) -> ^GtkWidget ---
	gtk_signal_list_item_factory_new :: proc() -> ^GtkListItemFactory ---
	gtk_list_item_get_position       :: proc(self: ^GtkListItem) -> guint ---
	gtk_list_item_set_child          :: proc(self: ^GtkListItem, child: ^GtkWidget) ---
	gtk_list_item_get_child          :: proc(self: ^GtkListItem) -> ^GtkWidget ---

	gtk_single_selection_new            :: proc(model: ^GObject) -> ^GtkSingleSelection ---
	gtk_single_selection_get_selected   :: proc(self: ^GtkSingleSelection) -> guint ---
	gtk_single_selection_set_autoselect :: proc(self: ^GtkSingleSelection, autoselect: gboolean) ---
	gtk_single_selection_set_selected   :: proc(self: ^GtkSingleSelection, position: guint) ---
	gtk_single_selection_set_can_unselect :: proc(self: ^GtkSingleSelection, can_unselect: gboolean) ---
}

g_signal_connect :: proc "c" (instance: gpointer, signal: cstring, handler: rawptr, data: gpointer) -> gulong {
	return g_signal_connect_data(instance, signal, handler, data, nil, 0)
}
