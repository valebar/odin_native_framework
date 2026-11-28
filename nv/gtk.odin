#+build linux:default
#+private
package nv

// Minimal hand-written GTK4 / GObject / GIO bindings used by the Linux backend.
// Names match the C API so the GTK docs apply directly.

foreign import gtk  "system:gtk-4"
foreign import gobj "system:gobject-2.0"
foreign import gio  "system:gio-2.0"
foreign import cairo "system:cairo"
foreign import glib "system:glib-2.0"
foreign import pango "system:pango-1.0"
foreign import pangocairo "system:pangocairo-1.0"
foreign import pangoft2 "system:pangoft2-1.0"
foreign import fontconfig "system:fontconfig"

GType    :: distinct uint
gboolean :: b32
guint    :: u32
gulong   :: uint
gpointer :: rawptr
GSourceFunc :: proc "c" (data: gpointer) -> gboolean

// Opaque instance types; only ever used behind a pointer.
GObject          :: struct {}
GtkWidget        :: struct {}
GtkApplication   :: struct {}
GtkListItem      :: struct {}
GtkSingleSelection :: struct {}
GtkListItemFactory :: struct {}
GtkEventController :: struct {}
GtkCssProvider     :: struct {}
GdkDisplay         :: struct {}
cairo_t            :: struct {}
cairo_surface_t    :: struct {}
GBytes             :: struct {}
GError             :: struct {}
GdkTexture         :: struct {}
PangoAttrList      :: struct {}
PangoAttribute     :: struct {}
PangoFontMap       :: struct {}
FcConfig           :: struct {}

PANGO_SCALE :: 1024
PANGO_STYLE_ITALIC :: i32(2)
CAIRO_FONT_SLANT_ITALIC :: i32(1)
CAIRO_FONT_WEIGHT_BOLD  :: i32(1)

GdkRectangle :: struct {
	x, y, width, height: i32,
}

cairo_font_extents_t :: struct {
	ascent, descent, height, max_x_advance, max_y_advance: f64,
}

cairo_text_extents_t :: struct {
	x_bearing, y_bearing, width, height, x_advance, y_advance: f64,
}

GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES :: u32(3) // VERTICAL | HORIZONTAL
GDK_SCROLL_UNIT_WHEEL                 :: i32(0) // notches; GDK_SCROLL_UNIT_SURFACE (1) is pixels

CAIRO_LINE_CAP_BUTT  :: i32(0)
CAIRO_LINE_CAP_ROUND :: i32(1)
CAIRO_LINE_JOIN_MITER :: i32(0)
CAIRO_LINE_JOIN_ROUND :: i32(1)
CAIRO_FORMAT_ARGB32  :: i32(0)

// GtkInputPurpose / GtkInputHints, for on-screen keyboards
GTK_INPUT_PURPOSE_DIGITS   :: i32(2)
GTK_INPUT_PURPOSE_NUMBER   :: i32(3)
GTK_INPUT_PURPOSE_PASSWORD :: i32(8)
GTK_INPUT_PURPOSE_PIN      :: i32(9)
GTK_INPUT_HINT_UPPERCASE_SENTENCES :: u32(1 << 6)

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
GtkCustomMeasureFunc  :: proc "c" (widget: ^GtkWidget, orientation: GtkOrientation, for_size: i32, minimum, natural, minimum_baseline, natural_baseline: ^i32)
GtkCustomAllocateFunc :: proc "c" (widget: ^GtkWidget, width, height, baseline: i32)
GtkStackTransitionType :: enum i32 {
	None = 0, Crossfade = 1, Slide_Right = 2, Slide_Left = 3, Slide_Up = 4, Slide_Down = 5,
	Slide_Left_Right = 6, Slide_Up_Down = 7,
}
GtkAlign       :: enum i32 { Fill = 0, Start = 1, End = 2, Center = 3 }
GtkOverflow    :: enum i32 { Visible = 0, Hidden = 1 }
PangoEllipsizeMode :: enum i32 { None = 0, Start = 1, Middle = 2, End = 3 }

G_APPLICATION_DEFAULT_FLAGS :: i32(0)
G_SOURCE_REMOVE             :: gboolean(false)
GTK_INVALID_LIST_POSITION   :: guint(0xffffffff)
GTK_STYLE_PROVIDER_PRIORITY_APPLICATION :: guint(600)

@(default_calling_convention="c")
foreign gobj {
	g_object_get_type            :: proc() -> GType ---
	g_object_new                 :: proc(type: GType, first_property_name: cstring, #c_vararg args: ..any) -> ^GObject ---
	g_object_unref               :: proc(object: gpointer) ---
	g_type_query                 :: proc(type: GType, query: ^GTypeQuery) ---
	g_type_register_static_simple :: proc(parent: GType, name: cstring, class_size: guint, class_init: rawptr, instance_size: guint, instance_init: rawptr, flags: i32) -> GType ---
	g_type_add_interface_static  :: proc(instance_type, interface_type: GType, info: ^GInterfaceInfo) ---
	g_signal_connect_data        :: proc(instance: gpointer, detailed_signal: cstring, c_handler: rawptr, data: gpointer, destroy_data: rawptr, connect_flags: i32) -> gulong ---
	g_object_ref_sink            :: proc(object: gpointer) -> gpointer ---
	g_object_ref                 :: proc(object: gpointer) -> gpointer ---
	g_object_set                 :: proc(object: gpointer, first_property_name: cstring, #c_vararg args: ..any) ---
	g_object_set_data            :: proc(object: gpointer, key: cstring, data: gpointer) ---
	g_object_get_data            :: proc(object: gpointer, key: cstring) -> gpointer ---
}

@(default_calling_convention="c")
foreign glib {
	g_idle_add :: proc(function: GSourceFunc, data: gpointer) -> guint ---
	g_timeout_add :: proc(interval: guint, function: GSourceFunc, data: gpointer) -> guint ---
	g_bytes_new    :: proc(data: rawptr, size: uint) -> ^GBytes ---
	g_bytes_unref  :: proc(bytes: ^GBytes) ---
	g_error_free   :: proc(error: ^GError) ---
	g_free         :: proc(mem: rawptr) ---
}

@(default_calling_convention="c")
foreign gio {
	g_list_model_get_type      :: proc() -> GType ---
	g_list_model_items_changed :: proc(list: gpointer, position, removed, added: guint) ---
	g_application_run          :: proc(application: gpointer, argc: i32, argv: [^]cstring) -> i32 ---
	g_settings_schema_source_get_default :: proc() -> gpointer ---
	g_settings_schema_source_lookup      :: proc(source: gpointer, schema_id: cstring, recursive: gboolean) -> gpointer ---
	g_settings_schema_has_key            :: proc(schema: gpointer, name: cstring) -> gboolean ---
	g_settings_schema_unref              :: proc(schema: gpointer) ---
	g_settings_new                       :: proc(schema_id: cstring) -> gpointer ---
	g_settings_get_enum                  :: proc(settings: gpointer, key: cstring) -> i32 ---
	g_file_get_path :: proc(file: rawptr) -> cstring --- // g_free it
}

@(default_calling_convention="c")
foreign gtk {
	gtk_application_new        :: proc(application_id: cstring, flags: i32) -> ^GtkApplication ---
	gtk_application_window_new :: proc(application: ^GtkApplication) -> ^GtkWidget ---
	gtk_window_set_title        :: proc(window: ^GtkWidget, title: cstring) ---
	gtk_window_set_default_size :: proc(window: ^GtkWidget, width, height: i32) ---
	gtk_window_set_child        :: proc(window: ^GtkWidget, child: ^GtkWidget) ---
	gtk_window_set_titlebar     :: proc(window: ^GtkWidget, titlebar: ^GtkWidget) ---
	gtk_window_present          :: proc(window: ^GtkWidget) ---

	gtk_header_bar_new        :: proc() -> ^GtkWidget ---
	gtk_header_bar_pack_start :: proc(bar: ^GtkWidget, child: ^GtkWidget) ---
	gtk_header_bar_pack_end   :: proc(bar: ^GtkWidget, child: ^GtkWidget) ---
	gtk_header_bar_remove     :: proc(bar: ^GtkWidget, child: ^GtkWidget) ---

	gtk_stack_new                    :: proc() -> ^GtkWidget ---
	gtk_stack_add_child              :: proc(stack: ^GtkWidget, child: ^GtkWidget) -> rawptr --- // GtkStackPage*, not owned
	gtk_stack_remove                 :: proc(stack: ^GtkWidget, child: ^GtkWidget) ---
	gtk_stack_set_visible_child      :: proc(stack: ^GtkWidget, child: ^GtkWidget) ---
	gtk_stack_set_transition_type    :: proc(stack: ^GtkWidget, transition: GtkStackTransitionType) ---
	gtk_stack_get_transition_running :: proc(stack: ^GtkWidget) -> gboolean ---

	gtk_widget_set_margin_start  :: proc(widget: ^GtkWidget, margin: i32) ---
	gtk_widget_set_margin_end    :: proc(widget: ^GtkWidget, margin: i32) ---
	gtk_widget_set_margin_top    :: proc(widget: ^GtkWidget, margin: i32) ---
	gtk_widget_set_margin_bottom :: proc(widget: ^GtkWidget, margin: i32) ---
	gtk_widget_set_overflow      :: proc(widget: ^GtkWidget, overflow: GtkOverflow) ---
	gtk_widget_set_size_request  :: proc(widget: ^GtkWidget, width, height: i32) ---
	gtk_widget_get_size_request  :: proc(widget: ^GtkWidget, width, height: ^i32) ---
	gtk_widget_set_vexpand       :: proc(widget: ^GtkWidget, expand: gboolean) ---
	gtk_widget_set_hexpand       :: proc(widget: ^GtkWidget, expand: gboolean) ---
	gtk_widget_set_valign        :: proc(widget: ^GtkWidget, align: GtkAlign) ---
	gtk_widget_set_halign        :: proc(widget: ^GtkWidget, align: GtkAlign) ---
	gtk_widget_add_css_class     :: proc(widget: ^GtkWidget, css_class: cstring) ---
	gtk_widget_set_visible       :: proc(widget: ^GtkWidget, visible: gboolean) ---
	gtk_widget_set_sensitive     :: proc(widget: ^GtkWidget, sensitive: gboolean) ---
	gtk_widget_grab_focus        :: proc(widget: ^GtkWidget) -> gboolean ---
	gtk_widget_set_tooltip_text  :: proc(widget: ^GtkWidget, text: cstring) ---
	gtk_widget_get_first_child   :: proc(widget: ^GtkWidget) -> ^GtkWidget ---
	gtk_widget_get_next_sibling  :: proc(widget: ^GtkWidget) -> ^GtkWidget ---

	gtk_overlay_new            :: proc() -> ^GtkWidget ---
	gtk_overlay_set_child      :: proc(overlay: ^GtkWidget, child: ^GtkWidget) ---
	gtk_overlay_add_overlay    :: proc(overlay: ^GtkWidget, widget: ^GtkWidget) ---
	gtk_overlay_remove_overlay :: proc(overlay: ^GtkWidget, widget: ^GtkWidget) ---
	gtk_overlay_set_measure_overlay :: proc(overlay: ^GtkWidget, widget: ^GtkWidget, measure: gboolean) ---

	gtk_css_provider_new              :: proc() -> ^GtkCssProvider ---
	gtk_css_provider_load_from_data   :: proc(provider: ^GtkCssProvider, data: cstring, length: int) --- // every 4.x (4.12+ prefers load_from_string)
	gtk_style_context_add_provider_for_display :: proc(display: ^GdkDisplay, provider: gpointer, priority: guint) ---
	gtk_style_context_remove_provider_for_display :: proc(display: ^GdkDisplay, provider: gpointer) ---
	gdk_display_get_default           :: proc() -> ^GdkDisplay ---
	gtk_icon_theme_get_for_display    :: proc(display: ^GdkDisplay) -> rawptr ---
	gtk_icon_theme_add_search_path    :: proc(theme: rawptr, path: cstring) ---
	gtk_settings_get_default          :: proc() -> gpointer ---

	gtk_scrolled_window_new       :: proc() -> ^GtkWidget ---
	gtk_scrolled_window_set_child :: proc(scrolled_window: ^GtkWidget, child: ^GtkWidget) ---

	gtk_box_new    :: proc(orientation: GtkOrientation, spacing: i32) -> ^GtkWidget ---
	gtk_box_append :: proc(box: ^GtkWidget, child: ^GtkWidget) ---
	gtk_box_remove :: proc(box: ^GtkWidget, child: ^GtkWidget) ---

	gtk_file_chooser_native_new       :: proc(title: cstring, parent: ^GtkWidget, action: i32, accept_label, cancel_label: cstring) -> rawptr ---
	gtk_native_dialog_set_modal       :: proc(dialog: rawptr, modal: gboolean) ---
	gtk_native_dialog_show            :: proc(dialog: rawptr) ---
	gtk_file_chooser_get_file         :: proc(chooser: rawptr) -> rawptr --- // GFile*, owned
	gtk_file_chooser_set_current_name :: proc(chooser: rawptr, name: cstring) ---
	gtk_file_chooser_add_filter       :: proc(chooser: rawptr, filter: rawptr) ---
	gtk_file_filter_new               :: proc() -> rawptr ---
	gtk_file_filter_add_suffix        :: proc(filter: rawptr, suffix: cstring) --- // 4.4
	gtk_file_filter_set_name          :: proc(filter: rawptr, name: cstring) ---

	gtk_custom_layout_new         :: proc(request_mode: rawptr, measure: GtkCustomMeasureFunc, allocate: GtkCustomAllocateFunc) -> rawptr --- // GtkLayoutManager*
	gtk_widget_set_layout_manager :: proc(widget: ^GtkWidget, layout_manager: rawptr) --- // takes it
	gtk_widget_get_width          :: proc(widget: ^GtkWidget) -> i32 ---
	gtk_widget_get_height         :: proc(widget: ^GtkWidget) -> i32 ---
	gtk_widget_measure            :: proc(widget: ^GtkWidget, orientation: GtkOrientation, for_size: i32, minimum, natural, minimum_baseline, natural_baseline: ^i32) ---
	gtk_widget_allocate           :: proc(widget: ^GtkWidget, width, height, baseline: i32, transform: rawptr) ---

	gtk_label_new           :: proc(str: cstring) -> ^GtkWidget ---
	gtk_label_set_text      :: proc(label: ^GtkWidget, str: cstring) ---
	gtk_label_set_xalign    :: proc(label: ^GtkWidget, xalign: f32) ---
	gtk_label_set_ellipsize :: proc(label: ^GtkWidget, mode: PangoEllipsizeMode) ---
	gtk_label_set_attributes :: proc(label: ^GtkWidget, attrs: ^PangoAttrList) ---
	gtk_entry_set_attributes :: proc(entry: ^GtkWidget, attrs: ^PangoAttrList) ---

	gtk_button_new            :: proc() -> ^GtkWidget ---
	gtk_button_new_with_label :: proc(label: cstring) -> ^GtkWidget ---
	gtk_button_set_label      :: proc(button: ^GtkWidget, label: cstring) ---
	gtk_button_new_from_icon_name :: proc(icon_name: cstring) -> ^GtkWidget ---
	gtk_button_get_child      :: proc(button: ^GtkWidget) -> ^GtkWidget ---

	gtk_entry_new                  :: proc() -> ^GtkWidget ---
	gtk_entry_set_placeholder_text :: proc(entry: ^GtkWidget, text: cstring) ---
	gtk_editable_get_text          :: proc(editable: ^GtkWidget) -> cstring ---
	gtk_editable_set_text          :: proc(editable: ^GtkWidget, text: cstring) ---
	gtk_editable_select_region     :: proc(editable: ^GtkWidget, start_pos, end_pos: i32) ---
	gtk_editable_set_position      :: proc(editable: ^GtkWidget, position: i32) ---
	gtk_entry_grab_focus_without_selecting :: proc(entry: ^GtkWidget) -> gboolean ---
	gtk_entry_set_visibility       :: proc(entry: ^GtkWidget, visible: gboolean) ---
	gtk_entry_set_input_purpose    :: proc(entry: ^GtkWidget, purpose: i32) ---
	gtk_entry_set_input_hints      :: proc(entry: ^GtkWidget, hints: u32) ---

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

	gtk_drawing_area_new           :: proc() -> ^GtkWidget ---
	gtk_drawing_area_set_draw_func :: proc(area: ^GtkWidget, draw_func: rawptr, user_data: gpointer, destroy: rawptr) ---
	gtk_drawing_area_set_content_width  :: proc(area: ^GtkWidget, width: i32) ---
	gtk_drawing_area_set_content_height :: proc(area: ^GtkWidget, height: i32) ---
	gdk_texture_new_from_bytes :: proc(bytes: ^GBytes, error: ^^GError) -> ^GdkTexture ---
	gdk_texture_get_width      :: proc(texture: ^GdkTexture) -> i32 ---
	gdk_texture_get_height     :: proc(texture: ^GdkTexture) -> i32 ---
	gdk_texture_download       :: proc(texture: ^GdkTexture, data: [^]u8, stride: uint) ---
	gtk_widget_queue_draw          :: proc(widget: ^GtkWidget) ---
	gtk_widget_add_tick_callback   :: proc(widget: ^GtkWidget, callback: rawptr, user: gpointer, notify: rawptr) -> guint ---
	gtk_widget_remove_tick_callback :: proc(widget: ^GtkWidget, id: guint) ---
	gtk_widget_add_controller      :: proc(widget: ^GtkWidget, controller: ^GtkEventController) ---
	gtk_gesture_drag_new           :: proc() -> ^GtkEventController ---
	gtk_event_controller_scroll_new      :: proc(flags: u32) -> ^GtkEventController ---
	gtk_event_controller_scroll_get_unit :: proc(controller: ^GtkEventController) -> i32 --- // GTK 4.8
	gtk_gesture_drag_get_start_point :: proc(gesture: ^GtkEventController, x, y: ^f64) -> gboolean ---
	gtk_gesture_zoom_new           :: proc() -> ^GtkEventController ---
	gtk_gesture_get_bounding_box_center :: proc(gesture: ^GtkEventController, x, y: ^f64) -> gboolean ---
	gtk_event_controller_motion_new :: proc() -> ^GtkEventController ---
	gtk_event_controller_get_current_event_state :: proc(controller: ^GtkEventController) -> u32 --- // GdkModifierType
	gtk_gesture_click_new          :: proc() -> ^GtkEventController ---

	gtk_box_set_homogeneous         :: proc(box: ^GtkWidget, homogeneous: gboolean) ---
	gtk_toggle_button_new           :: proc() -> ^GtkWidget ---
	gtk_toggle_button_set_group     :: proc(button: ^GtkWidget, group: ^GtkWidget) ---
	gtk_toggle_button_set_active    :: proc(button: ^GtkWidget, is_active: gboolean) ---
	gtk_toggle_button_get_active    :: proc(button: ^GtkWidget) -> gboolean ---
	gtk_button_set_child            :: proc(button: ^GtkWidget, child: ^GtkWidget) ---
	gtk_image_new_from_icon_name    :: proc(icon_name: cstring) -> ^GtkWidget ---
	gtk_image_set_pixel_size        :: proc(image: ^GtkWidget, pixel_size: i32) ---
}

@(default_calling_convention="c")
foreign cairo {
	cairo_save             :: proc(cr: ^cairo_t) ---
	cairo_restore          :: proc(cr: ^cairo_t) ---
	cairo_translate        :: proc(cr: ^cairo_t, tx, ty: f64) ---
	cairo_scale            :: proc(cr: ^cairo_t, sx, sy: f64) ---
	cairo_set_source_rgba  :: proc(cr: ^cairo_t, r, g, b, a: f64) ---
	cairo_set_line_width   :: proc(cr: ^cairo_t, width: f64) ---
	cairo_set_line_cap     :: proc(cr: ^cairo_t, cap: i32) ---
	cairo_set_line_join    :: proc(cr: ^cairo_t, join: i32) ---
	cairo_clip             :: proc(cr: ^cairo_t) ---
	cairo_new_path         :: proc(cr: ^cairo_t) ---
	cairo_move_to          :: proc(cr: ^cairo_t, x, y: f64) ---
	cairo_line_to          :: proc(cr: ^cairo_t, x, y: f64) ---
	cairo_close_path       :: proc(cr: ^cairo_t) ---
	cairo_rectangle        :: proc(cr: ^cairo_t, x, y, w, h: f64) ---
	cairo_arc              :: proc(cr: ^cairo_t, xc, yc, radius, angle1, angle2: f64) ---
	cairo_fill             :: proc(cr: ^cairo_t) ---
	cairo_stroke           :: proc(cr: ^cairo_t) ---
	cairo_select_font_face :: proc(cr: ^cairo_t, family: cstring, slant, weight: i32) ---
	cairo_set_font_size    :: proc(cr: ^cairo_t, size: f64) ---
	cairo_font_extents     :: proc(cr: ^cairo_t, extents: ^cairo_font_extents_t) ---
	cairo_text_extents     :: proc(cr: ^cairo_t, utf8: cstring, extents: ^cairo_text_extents_t) ---
	cairo_show_text        :: proc(cr: ^cairo_t, utf8: cstring) ---
	cairo_set_source_surface     :: proc(cr: ^cairo_t, surface: ^cairo_surface_t, x, y: f64) ---
	cairo_image_surface_create   :: proc(format: i32, width, height: i32) -> ^cairo_surface_t ---
	cairo_image_surface_get_data :: proc(surface: ^cairo_surface_t) -> [^]u8 ---
	cairo_image_surface_get_stride :: proc(surface: ^cairo_surface_t) -> i32 ---
	cairo_surface_mark_dirty     :: proc(surface: ^cairo_surface_t) ---
	cairo_surface_flush          :: proc(surface: ^cairo_surface_t) ---
	cairo_surface_destroy        :: proc(surface: ^cairo_surface_t) ---
}

// Pango text attributes (font_linux.odin) and the fontconfig registration of loaded fonts.
@(default_calling_convention="c")
foreign pango {
	pango_attr_list_new          :: proc() -> ^PangoAttrList ---
	pango_attr_list_insert       :: proc(list: ^PangoAttrList, attr: ^PangoAttribute) --- // takes the attribute
	pango_attr_list_unref        :: proc(list: ^PangoAttrList) ---
	pango_attr_family_new        :: proc(family: cstring) -> ^PangoAttribute ---
	pango_attr_size_new_absolute :: proc(size: i32) -> ^PangoAttribute --- // device units × PANGO_SCALE
	pango_attr_weight_new        :: proc(weight: i32) -> ^PangoAttribute ---
	pango_attr_style_new         :: proc(style: i32) -> ^PangoAttribute ---
}

@(default_calling_convention="c")
foreign pangocairo {
	pango_cairo_font_map_get_default :: proc() -> ^PangoFontMap ---
}

@(default_calling_convention="c")
foreign pangoft2 {
	pango_fc_font_map_config_changed :: proc(fcfontmap: ^PangoFontMap) ---
}

@(default_calling_convention="c")
foreign fontconfig {
	FcConfigGetCurrent     :: proc() -> ^FcConfig ---
	FcConfigAppFontAddFile :: proc(config: ^FcConfig, file: cstring) -> i32 ---
}

g_signal_connect :: proc "c" (instance: gpointer, signal: cstring, handler: rawptr, data: gpointer) -> gulong {
	return g_signal_connect_data(instance, signal, handler, data, nil, 0)
}
