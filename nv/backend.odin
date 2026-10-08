package nv

// The backend contract: every operation the shared core (nv.odin) asks of a platform, one field
// each, with the backends' exact signatures. Each backend implements them as the `_`-prefixed
// procs of its files (picked by build tags) and g_backend binds them, so a backend that lacks one,
// or has it with another signature, fails to compile for its target (nvbuild check). The core
// calls g_backend.x(..); a backend calls its own _x directly; the tests install a mock
// (mock_test.odin). What each operation must do is documented where the core uses it: g_nav (run
// may return before the root page is shown, as on Android), Dialog, Image / Fetch, and the theme's
// backend comment above g_theme.
//
// The draw procs (_fill_rect, _stroke_rect, _draw_line, _fill_ellipse, _stroke_ellipse,
// _stroke_arc, _draw_text, _draw_image) belong to the contract too, but the core calls them directly: they are
// the canvas's hot path and only run inside on_draw with a Painter the backend made, so no test
// replaces them. A missing one fails at its call in nv.odin.
@(private) Backend :: struct {
	// The app and its pages (see g_nav)
	run:                 proc(),
	nav_push:            proc(e: ^Page_Handle),
	nav_pop:             proc(top, below: ^Page_Handle) -> bool,
	nav_release:         proc(e: ^Page_Handle),
	nav_title_changed:   proc(e: ^Page_Handle),
	nav_actions_changed: proc(e: ^Page_Handle),

	// Widgets: *_init makes h.root (and whatever else the handle holds) in the current scope
	list_init:           proc(h: ^List_Handle),
	list_reload:         proc(h: ^List_Handle),
	flex_create:         proc(f: Flex) -> View,
	container_init:      proc(h: ^Container_Handle),
	container_set_color: proc(h: ^Container_Handle),
	label_init:          proc(h: ^Label_Handle),
	label_set_text:      proc(h: ^Label_Handle, text: string),
	input_init:          proc(h: ^Input_Handle),
	input_text:          proc(h: ^Input_Handle, allocator := context.allocator) -> string,
	input_set_text:      proc(h: ^Input_Handle, text: string),
	button_init:         proc(h: ^Button_Handle),
	button_set_title:    proc(h: ^Button_Handle, title: string),
	canvas_init:         proc(h: ^Canvas_Handle),
	canvas_redraw:       proc(h: ^Canvas_Handle),
	image_init:          proc(h: ^Image_Handle),
	image_set_bitmap:    proc(h: ^Image_Handle),

	// Bitmaps, fonts, assets and downloads
	bitmap_decode:       proc(b: ^Bitmap, data: []u8) -> bool,
	bitmap_free:         proc(b: ^Bitmap),
	font_load:           proc(f: ^Font, data: []u8) -> bool,
	font_free:           proc(f: ^Font),
	asset_read:          proc(path: string, allocator := context.allocator) -> []u8,
	fetch_start:         proc(f: ^Fetch),

	// Dialogs (see Dialog)
	dialog_show:         proc(h: ^Dialog_Handle),
	dialog_close:        proc(h: ^Dialog_Handle),
	dialog_set_hidden:   proc(h: ^Dialog_Handle, hidden: bool),

	// The theme (see g_theme)
	theme_system_dark:   proc() -> bool,
	theme_system_accent: proc() -> Color,
	theme_apply_mode:    proc(),
	theme_recolor:       proc(),
}

@(private) g_backend := Backend{
	run                 = _run,
	nav_push            = _nav_push,
	nav_pop             = _nav_pop,
	nav_release         = _nav_release,
	nav_title_changed   = _nav_title_changed,
	nav_actions_changed = _nav_actions_changed,
	list_init           = _list_init,
	list_reload         = _list_reload,
	flex_create         = _flex_create,
	container_init      = _container_init,
	container_set_color = _container_set_color,
	label_init          = _label_init,
	label_set_text      = _label_set_text,
	input_init          = _input_init,
	input_text          = _input_text,
	input_set_text      = _input_set_text,
	button_init         = _button_init,
	button_set_title    = _button_set_title,
	canvas_init         = _canvas_init,
	canvas_redraw       = _canvas_redraw,
	image_init          = _image_init,
	image_set_bitmap    = _image_set_bitmap,
	bitmap_decode       = _bitmap_decode,
	bitmap_free         = _bitmap_free,
	font_load           = _font_load,
	font_free           = _font_free,
	asset_read          = _asset_read,
	fetch_start         = _fetch_start,
	dialog_show         = _dialog_show,
	dialog_close        = _dialog_close,
	dialog_set_hidden   = _dialog_set_hidden,
	theme_system_dark   = _theme_system_dark,
	theme_system_accent = _theme_system_accent,
	theme_apply_mode    = _theme_apply_mode,
	theme_recolor       = _theme_recolor,
}
