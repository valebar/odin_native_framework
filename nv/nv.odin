package nv

// Shared public API. Platform backends: *_macos.odin / *_ios.odin (`#+build darwin`,
// split by `when IS_IOS` since build tags can't select the iOS subtarget),
// *_android.odin (`#+build linux:android`), *_linux.odin (`#+build linux:default`, GTK4) and
// *_windows.odin (`#+build windows`, Win32).
//
// Widgets: a scrolling list (`list_create`), a text label (`label_create`), a text input
// (`input_create`), a push button (`button_create`), a custom-drawn canvas (`canvas_create`), an
// image (`image_create`), Flutter-style Row / Column stacks (`row_create`, `column_create`,
// `flex_create`) and a Container (`container_create`): a box with margin, border, background,
// rounded corners and padding around one child. Images are decoded into a Bitmap from bytes, a file or a URL (`bitmap_from_bytes`,
// `bitmap_from_file`, `bitmap_fetch`), which the canvas can draw too (`draw_image`). Pages stack
// with `push` / `pop`; `run` shows the root page. A page's bar carries its title, a back button
// and its `actions` (`page_set_title`, `page_set_actions`). A dialog (`dialog_show`,
// `dialog_close`) is a card drawn over the page inside the window, modal or not. A Font loaded
// from bytes or an asset file (`font_from_bytes`, `font_from_file`) can replace the system font in
// labels, inputs, buttons and canvas text.
//
// Every widget follows one shape: `X :: struct` describes it, `x_create(X) -> ^X_Handle` makes it,
// `x_view(h)` is the view to embed, `x_set_y(h, ..)` changes it. Row / Column return a plain View:
// their children are fixed at creation, like Flutter.

import "base:builtin"
import "base:runtime"
import "core:os"
import "core:slice"
import "core:strings"

IS_IOS     :: ODIN_PLATFORM_SUBTARGET_IOS
IS_ANDROID :: ODIN_PLATFORM_SUBTARGET == .Android

// Opaque native view: NSView* on macOS, UIView* on iOS, global jobject on Android, GtkWidget* on Linux,
// HWND on Windows.
View :: distinct rawptr

Item :: struct {
	title:    string,
	subtitle: string,
}

List :: struct {
	count:      proc(user: rawptr) -> int,
	item:       proc(user: rawptr, index: int) -> Item,
	on_select:   proc(user: rawptr, index: int), // optional
	item_height: f64, // points / dp; 44 when 0
	user:        rawptr,
}

List_Handle :: struct {
	list:          List,
	ctx:           runtime.Context,
	root:          View,   // view embedded by the app
	table:         rawptr, // NSTableView* / UITableView* / ListView / GtkListView* / SysListView32 HWND
	data_source:   rawptr,
	cells_created: int,    // debug: proves reuse (always 0 on Windows: the virtual ListView has no row objects)
}

// Temp memory belongs to the callback in progress and is freed when the outermost one returns.
// Callbacks nest: an on_click that calls input_set_text, list_reload or push can trigger a change
// notification, a row callback or a page build, and a Win32 layout re-enters the procs of nested
// views. An inner callback that freed would wipe strings the outer one (and the app) still holds.
// So every entry from the platform into Odin code that allocates or calls the app (`build`,
// `on_pop`, the system back handlers) is bracketed by these, and procs the app calls never free.
@(private) g_callback_depth: int

@(private)
callback_enter :: proc "contextless" () {
	g_callback_depth += 1
}

@(private)
callback_exit :: proc() {
	g_callback_depth -= 1
	if g_callback_depth == 0 do free_all(context.temp_allocator)
}

// One screen of the navigation stack. `build` runs when the page is pushed and gets the page's
// handle; `on_pop` runs after the page left the stack and its view was released, so the app can
// free what `build` created (it is the last call the page's handle is valid for). `actions` are
// the trailing buttons of the page's bar (Flutter's AppBar.actions). Dialogs shown while the page
// is on top belong to it: they hide under a pushed page and close when the page pops.
Page :: struct {
	title:   string, // copied
	build:   Build_Proc,
	user_data:    rawptr,
	on_pop:  proc(user: rawptr), // optional
	actions: []Action,           // copied
}

Build_Proc :: proc(page: ^Page_Handle, user: rawptr) -> View

// System icons every platform has (SF Symbols / android.R.drawable / GTK icon names / Segoe MDL2
// Assets). A platform without a given icon shows the action's title as text instead.
Icon :: enum { None, Add, Edit, Delete, Search, Share, Settings, Refresh, Done, Info, More, Close }

// One button in the page's bar, shown trailing in declared order. `title` is the button text when
// `icon` is None, and the tooltip / accessibility label otherwise.
Action :: struct {
	title:    string, // copied
	icon:     Icon,
	on_click: proc(user: rawptr), // optional
	user:     rawptr,
}

// The owned copy of an Action. Backends find it again from the native control (the `tag` on
// Apple, the signal data on GTK, GWLP_USERDATA on Windows, the menu item id on Android).
@(private) Action_Handle :: struct {
	action: Action, // action.title is an owned copy
	ctx:    runtime.Context,
}

// A page on the stack, from `run` / `push` until its `on_pop` returned. Heap-allocated, so the
// pointer is stable while the stack grows.
Page_Handle :: struct {
	page:    Page,                    // page.title is an owned copy; page.actions is not used past push
	root:    View,                    // owned; nil while `build` runs and once released
	actions: [dynamic]^Action_Handle, // owned; freed by nav_actions_free
	native:  rawptr,                  // backend per-page object: the UIViewController on iOS
}

// The page stack: g_nav[0] is the root page from `run`, the depth is len(g_nav) - 1. Backends
// implement _run (the platform loop; once views can exist it calls nav_show_root), _nav_push
// (show the new top page, already in g_nav, with its title and chrome), _nav_pop (the native
// transition back to `below`, already the top of g_nav; false if the platform refused),
// _nav_release (drop the ownership of a page's root view), _nav_title_changed and
// _nav_actions_changed (a shown page's title / actions were replaced; it may or may not be the
// top page, and push / pop read them on their own). They never modify g_nav; a system back (iOS swipe, Android relaunch) that
// already removed the native page calls nav_system_pop for the bookkeeping. Inside this package
// `pop` shadows the builtin, hence builtin.pop. Dialogs add _dialog_show, _dialog_close and
// _dialog_set_hidden (see Dialog).
@(private) g_nav: [dynamic]^Page_Handle

// A push from inside a page's `build` (a deep link from the root page, say) waits until that page
// is shown, so the pages stack in call order.
@(private) g_nav_building: int
@(private) g_nav_pending:  [dynamic]^Page_Handle

// Opens a window showing the root page and blocks in the platform event loop. `build` runs once
// the platform is ready to create views.
run :: proc(p: Page) {
	assert(len(g_nav) == 0, "nv.run twice")
	append(&g_nav, nav_page_new(p))
	_run()
}

// Builds and shows a page on top of the stack; the title is shown in the navigation bar / window
// title, and a back button (or the platform's back gesture / key) pops it. Called from `build`,
// the page is pushed once the page being built is shown. The handle stays valid until the page's
// `on_pop` returned.
push :: proc(p: Page) -> ^Page_Handle {
	assert(len(g_nav) > 0, "nv.push before nv.run")
	h := nav_page_new(p)
	if g_nav_building > 0 {
		append(&g_nav_pending, h)
		return h
	}
	append(&g_nav, h) // on the stack before the build, so a nested push queues behind it
	nav_build(h)
	nav_present(h)
	nav_flush_pending()
	return h
}

// Removes the top page and returns to the one below. Does nothing on the root page, or inside a
// `build` (the top page is the one being built then; a page decides against itself by pushing
// nothing and popping from a later callback).
pop :: proc() {
	if len(g_nav) <= 1 || g_nav_building > 0 do return
	top := builtin.pop(&g_nav)
	if !_nav_pop(top, g_nav[len(g_nav) - 1]) {
		append(&g_nav, top) // the platform is mid-transition; the page stays
		return
	}
	nav_finish_pop(top)
}

// Replaces the title shown in the page's bar; `title` is copied.
page_set_title :: proc(h: ^Page_Handle, title: string) {
	old := h.page.title
	h.page.title = strings.clone(title)
	delete(old)
	if h.root != nil do _nav_title_changed(h) // nil while `build` runs: the _nav_push that follows shows it
}

// Replaces the page's actions. Frees the old ones, including the one whose `on_click` may be
// making this call.
page_set_actions :: proc(h: ^Page_Handle, actions: []Action) {
	nav_actions_assign(h, actions)
	if h.root != nil do _nav_actions_changed(h)
}

@(private)
nav_page_new :: proc(p: Page) -> ^Page_Handle {
	h := new(Page_Handle)
	h.page = p
	h.page.title = strings.clone(p.title)
	h.page.actions = nil // the app's slice; not kept
	nav_actions_assign(h, p.actions)
	return h
}

@(private)
nav_build :: proc(h: ^Page_Handle) {
	callback_enter()
	defer callback_exit()
	g_nav_building += 1
	h.root = h.page.build(h, h.page.user_data)
	g_nav_building -= 1
}

// Builds and shows the root page; every backend calls this once views can exist, bracketed.
@(private)
nav_show_root :: proc() {
	nav_build(g_nav[0])
	nav_present(g_nav[0])
	nav_flush_pending()
}

// Shows a built page that is already the top of g_nav: the dialogs of the page below hide under
// it, and the dialogs its own `build` showed appear over it.
@(private)
nav_present :: proc(h: ^Page_Handle) {
	if len(g_nav) > 1 do dialog_set_page_hidden(g_nav[len(g_nav) - 2], true)
	_nav_push(h)
	dialog_flush_pending()
}

// Also flushes the dialogs of a root page shown without nav_present (iOS builds the root page
// itself, since the navigation controller wants its root controller up front).
@(private)
nav_flush_pending :: proc() {
	dialog_flush_pending()
	for len(g_nav_pending) > 0 {
		h := g_nav_pending[0]
		ordered_remove(&g_nav_pending, 0)
		append(&g_nav, h)
		nav_build(h)
		nav_present(h)
	}
}

// Bookkeeping for a pop the platform already performed.
@(private)
nav_system_pop :: proc() {
	if len(g_nav) <= 1 do return
	top := builtin.pop(&g_nav)
	nav_finish_pop(top)
}

// The page's dialogs close first (their on_close still sees a live page), and the dialogs of the
// page below come back.
@(private)
nav_finish_pop :: proc(top: ^Page_Handle) {
	dialog_close_page(top)
	_nav_release(top)
	top.root, top.native = nil, nil // a page_set_* from on_pop has nothing to show
	if top.page.on_pop != nil {
		callback_enter()
		defer callback_exit()
		top.page.on_pop(top.page.user_data)
	}
	nav_actions_free(top)
	delete(top.page.title)
	free(top)
	dialog_set_page_hidden(g_nav[len(g_nav) - 1], false)
}

@(private)
nav_actions_assign :: proc(h: ^Page_Handle, actions: []Action) {
	nav_actions_free(h)
	for a in actions {
		ah := new(Action_Handle)
		ah.action = a
		ah.action.title = strings.clone(a.title)
		ah.ctx = context
		append(&h.actions, ah)
	}
}

@(private)
nav_actions_free :: proc(h: ^Page_Handle) {
	for ah in h.actions {
		delete(ah.action.title)
		free(ah)
	}
	delete(h.actions)
	h.actions = nil
}

// Called by the backends when the bar's back button was clicked (macOS, GTK, Windows; Android's
// Back key closes a modal dialog instead, iOS's bar is under the scrim). Ignored while a modal
// dialog is up, since the bar sits outside the scrim on macOS and GTK.
@(private)
nav_back_notify :: proc() {
	if dialog_top_modal() != nil do return
	callback_enter()
	defer callback_exit()
	pop()
}

// Called by the backends when an action was clicked. The callback may replace the page's actions
// or pop the page, which frees `h`, so nothing is read from it afterwards. Ignored while a modal
// dialog is up, like nav_back_notify.
@(private)
action_notify :: proc(h: ^Action_Handle) {
	cb, user := h.action.on_click, h.action.user
	if cb == nil || dialog_top_modal() != nil do return
	callback_enter()
	defer callback_exit()
	cb(user)
}

list_create :: proc(l: List) -> ^List_Handle {
	h := new(List_Handle)
	h.list = l
	if h.list.item_height <= 0 do h.list.item_height = 44
	h.ctx = context
	_list_init(h)
	return h
}

list_view :: proc(h: ^List_Handle) -> View {
	return h.root
}

list_reload :: proc(h: ^List_Handle) {
	_list_reload(h)
}

ROW_ID :: "nv_row"

// Main axis of a Row / Column. The values match GtkOrientation, NSUserInterfaceLayoutOrientation,
// UILayoutConstraintAxis and LinearLayout.HORIZONTAL / VERTICAL, so backends cast directly. Windows
// lays out by hand and uses the value as the main-axis index (x = 0, y = 1).
Axis :: enum { Horizontal, Vertical }

// One child of a Row / Column. `flex` 0 keeps the natural size; `flex` > 0 shares the space left
// on the main axis in proportion to the other flex children (Flutter's Expanded). The cross axis
// always stretches. Weights other than 1 are exact on Apple, Android and Windows; GTK shares equally.
Flex_Child :: struct {
	view: View,
	flex: int,
}

Flex :: struct {
	axis:     Axis,
	spacing:  f64, // points / dp between children
	children: []Flex_Child,
}

// Children are fixed at creation, like Flutter. The returned view owns its children.
flex_create :: proc(f: Flex) -> View {
	return _flex_create(f)
}

row_create :: proc(children: []Flex_Child, spacing: f64 = 0) -> View {
	return _flex_create({axis = .Horizontal, spacing = spacing, children = children})
}

column_create :: proc(children: []Flex_Child, spacing: f64 = 0) -> View {
	return _flex_create({axis = .Vertical, spacing = spacing, children = children})
}

// Per-side distances in points / dp (Flutter's EdgeInsets).
Insets :: struct {
	left, top, right, bottom: f64,
}

insets_all :: proc(v: f64) -> Insets {
	return {v, v, v, v}
}

insets_symmetric :: proc(horizontal, vertical: f64) -> Insets {
	return {horizontal, vertical, horizontal, vertical}
}

// Flutter's Container: `margin` outside, then a `border_width` border in `border_color` and the
// `color` background, both rounded by `radius`, then `padding`, then `child` filling what is left.
// `width` / `height` are the natural size including the padding and the border but not the margin;
// 0 takes it from the child. Like Image, the cross axis of a Row / Column still stretches and a
// flex > 0 child ignores them on the main axis. GTK treats them as a minimum.
Container :: struct {
	child:        View,  // optional; the container owns it
	padding:      Insets,
	margin:       Insets,
	color:        Color, // background; alpha 0 = none
	border_color: Color, // drawn when border_width > 0
	border_width: f64,
	radius:       f64,
	width:        f64,
	height:       f64,
}

Container_Handle :: struct {
	container: Container,
	ctx:       runtime.Context,
	root:      View,   // the outer view, which includes the margin; embedded by the app
	box:       rawptr, // backend: NSBox* / UIView* / GradientDrawable global ref / ^Linux_Container / HBRUSH
}

container_create :: proc(c: Container) -> ^Container_Handle {
	h := new(Container_Handle)
	h.container = c
	h.ctx = context
	_container_init(h)
	return h
}

container_view :: proc(h: ^Container_Handle) -> View {
	return h.root
}

// Replaces the background color (alpha 0 removes it).
container_set_color :: proc(h: ^Container_Handle, color: Color) {
	h.container.color = color
	_container_set_color(h)
}

// The child's distance from the container's outer edge, per side.
@(private)
container_frame :: proc "contextless" (h: ^Container_Handle) -> Insets {
	c := &h.container
	b := c.border_width
	return {c.margin.left + b + c.padding.left, c.margin.top + b + c.padding.top,
		c.margin.right + b + c.padding.right, c.margin.bottom + b + c.padding.bottom}
}

// Single-line text; `bold` makes it a heading (bold and a little larger). `font` replaces the
// system font (then `bold` only picks the heading size: load a bold face for bold text) and
// `size` the default size, in points / dp like `draw_text`.
Label :: struct {
	text: string, // copied
	bold: bool,
	font: ^Font,  // optional; the label keeps its own reference
	size: f64,    // 0 = the platform default
}

Label_Handle :: struct {
	label: Label, // label.text is an owned copy, kept current by label_set_text
	root:  View,  // the NSTextField* / UILabel* / TextView / GtkLabel* / Static HWND, embedded by the app
}

label_create :: proc(l: Label) -> ^Label_Handle {
	h := new(Label_Handle)
	h.label = l
	h.label.text = strings.clone(l.text)
	font_retain(l.font)
	_label_init(h)
	return h
}

label_view :: proc(h: ^Label_Handle) -> View {
	return h.root
}

// Replaces the text; `text` is copied. The size of a flex-0 label follows on the next layout.
label_set_text :: proc(h: ^Label_Handle, text: string) {
	old := h.label.text
	h.label.text = strings.clone(text)
	delete(old)
	_label_set_text(h, text)
}

// Single-line text input. Callbacks get the current text, valid only during the call. `font` and
// `size` are as on Label.
Input :: struct {
	text:        string, // initial text
	placeholder: string,
	on_change:   proc(user: rawptr, text: string), // optional; on every edit by the user
	on_submit:   proc(user: rawptr, text: string), // optional; Return / Enter / the keyboard's Done key
	user:        rawptr,
	font:        ^Font, // optional; the input keeps its own reference
	size:        f64,   // 0 = the platform default
}

Input_Handle :: struct {
	input:    Input,
	ctx:      runtime.Context,
	root:     View,   // view embedded by the app
	field:    rawptr, // NSTextField* / UITextField* / EditText / GtkEntry* / Edit HWND
	delegate: rawptr, // delegate / target / listener object, where the platform needs one
	silent:   bool,   // set during input_set_text, which never reports a change
}

input_create :: proc(i: Input) -> ^Input_Handle {
	h := new(Input_Handle)
	h.input = i
	h.ctx = context
	font_retain(i.font)
	_input_init(h)
	return h
}

input_view :: proc(h: ^Input_Handle) -> View {
	return h.root
}

// Returns a copy of the current text.
input_text :: proc(h: ^Input_Handle, allocator := context.allocator) -> string {
	return _input_text(h, allocator)
}

// Replaces the text without calling `on_change`.
input_set_text :: proc(h: ^Input_Handle, text: string) {
	h.silent = true
	_input_set_text(h, text)
	h.silent = false
}

// Called by the backends when the text changed or was submitted; `cb` is on_change or on_submit.
@(private)
input_notify :: proc(h: ^Input_Handle, cb: proc(user: rawptr, text: string)) {
	if h.silent || cb == nil do return
	callback_enter()
	defer callback_exit()
	cb(h.input.user, _input_text(h, context.temp_allocator))
}

// Push button with a text title. `font` and `size` are as on Label.
Button :: struct {
	title:    string, // copied
	on_click: proc(user: rawptr), // optional
	user:     rawptr,
	font:     ^Font, // optional; the button keeps its own reference
	size:     f64,   // 0 = the platform default
}

Button_Handle :: struct {
	button:  Button, // button.title is an owned copy, kept current by button_set_title
	ctx:     runtime.Context,
	root:    View,   // view embedded by the app
	control: rawptr, // NSButton* / UIButton* / Button / GtkButton* / Button HWND
	target:  rawptr, // target / listener object, where the platform needs one
}

button_create :: proc(b: Button) -> ^Button_Handle {
	h := new(Button_Handle)
	h.button = b
	h.button.title = strings.clone(b.title)
	h.ctx = context
	font_retain(b.font)
	_button_init(h)
	return h
}

button_view :: proc(h: ^Button_Handle) -> View {
	return h.root
}

// Replaces the title; `title` is copied. The size of a flex-0 button follows on the next layout.
button_set_title :: proc(h: ^Button_Handle, title: string) {
	old := h.button.title
	h.button.title = strings.clone(title)
	delete(old)
	_button_set_title(h, title)
}

// Called by the backends when the button was clicked.
@(private)
button_notify :: proc(h: ^Button_Handle) {
	if h.button.on_click == nil do return
	callback_enter()
	defer callback_exit()
	h.button.on_click(h.button.user)
}

// RGBA, each 0..1.
Color :: [4]f32

// Packed 0xAARRGGBB (android.graphics.Color, GDI+).
@(private)
color_argb :: proc "contextless" (c: Color) -> u32 {
	b :: proc "contextless" (f: f32) -> u32 { return u32(clamp(f, 0, 1) * 255 + 0.5) }
	return b(c.a) << 24 | b(c.r) << 16 | b(c.g) << 8 | b(c.b)
}

Pointer :: enum { Down, Move, Up }

// Custom-drawn view. `on_draw` runs whenever the platform repaints; call `canvas_redraw` after
// the state it draws changed. Units are points / dp with the origin top-left. The canvas has no
// natural size, so give it `flex` > 0 in a Row / Column.
Canvas :: struct {
	on_draw:    proc(user: rawptr, p: ^Painter, width, height: f64),
	on_pointer: proc(user: rawptr, kind: Pointer, x, y: f64), // optional; Move only while pressed
	user:       rawptr,
}

Canvas_Handle :: struct {
	canvas: Canvas,
	ctx:    runtime.Context,
	root:   View,   // view embedded by the app
	view:   rawptr, // NVCanvasView* / NvCanvasView / GtkDrawingArea* / NVCanvas HWND
	fill:   rawptr, // Android: fill and stroke Paint global refs
	stroke: rawptr,
}

// Drawing target, valid only during `on_draw`.
Painter :: struct {
	h:      ^Canvas_Handle,
	native: rawptr, // CGContextRef / android.graphics.Canvas / cairo_t* / GpGraphics*
	dc:     rawptr, // Windows: the HDC behind `native`
}

canvas_create :: proc(c: Canvas) -> ^Canvas_Handle {
	h := new(Canvas_Handle)
	h.canvas = c
	h.ctx = context
	_canvas_init(h)
	return h
}

canvas_view :: proc(h: ^Canvas_Handle) -> View {
	return h.root
}

// Schedules a repaint; `on_draw` runs later from the event loop.
canvas_redraw :: proc(h: ^Canvas_Handle) {
	_canvas_redraw(h)
}

fill_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	_fill_rect(p, x, y, w, h, color)
}

stroke_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64 = 1) {
	_stroke_rect(p, x, y, w, h, color, width)
}

draw_line :: proc(p: ^Painter, x0, y0, x1, y1: f64, color: Color, width: f64 = 1) {
	_draw_line(p, x0, y0, x1, y1, color, width)
}

// The ellipse inscribed in the rect.
fill_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	_fill_ellipse(p, x, y, w, h, color)
}

stroke_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64 = 1) {
	_stroke_ellipse(p, x, y, w, h, color, width)
}

// One line of text in the system font, or in `font`; (x, y) is the top-left of its line box.
draw_text :: proc(p: ^Painter, text: string, x, y: f64, size: f64, color: Color, font: ^Font = nil) {
	_draw_text(p, text, x, y, size, color, font)
}

// Called by the backends on repaint; `native` / `dc` as in Painter.
@(private)
canvas_draw_notify :: proc(h: ^Canvas_Handle, native: rawptr, width, height: f64, dc: rawptr = nil) {
	if h.canvas.on_draw == nil do return
	callback_enter()
	defer callback_exit()
	p := Painter{h, native, dc}
	h.canvas.on_draw(h.canvas.user, &p, width, height)
}

@(private)
canvas_pointer_notify :: proc(h: ^Canvas_Handle, kind: Pointer, x, y: f64) {
	if h.canvas.on_pointer == nil do return
	callback_enter()
	defer callback_exit()
	h.canvas.on_pointer(h.canvas.user, kind, x, y)
}

// Draws `b` stretched over the rect.
draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	if b == nil do return
	_draw_image(p, b, x, y, w, h)
}

// A decoded image in memory, drawn by Image widgets and `draw_image`. Reference counted:
// `bitmap_free` drops the caller's reference, and a widget showing the bitmap holds its own, so
// the app can free a bitmap right after handing it to a widget.
Bitmap :: struct {
	native: rawptr, // CGImageRef / android.graphics.Bitmap global ref / cairo_surface_t* / GpBitmap*
	extra:  rawptr, // Windows: the IStream GDI+ decodes from lazily
	width:  int,    // px
	height: int,
	refs:   int,
}

// Decodes PNG or JPEG bytes with the platform's decoder; nil if they are not an image. `data` is
// not kept.
bitmap_from_bytes :: proc(data: []u8) -> ^Bitmap {
	if len(data) == 0 do return nil
	b := new(Bitmap)
	b.refs = 1
	if !_bitmap_decode(b, data) {
		free(b)
		return nil
	}
	return b
}

// Loads an image file. A relative path names one of the app's assets: `app/assets/`, which the
// build scripts copy next to the executable (desktop), into the app bundle (iOS) or into the APK.
bitmap_from_file :: proc(path: string) -> ^Bitmap {
	return bitmap_from_bytes(_asset_read(path, context.temp_allocator))
}

// Downloads and decodes an image in the background. `on_load` runs later on the UI thread with
// the bitmap, which the caller then owns, or nil if the download or the decode failed.
bitmap_fetch :: proc(url: string, on_load: proc(user: rawptr, b: ^Bitmap), user: rawptr) {
	f := new(Fetch, runtime.heap_allocator())
	f^ = {url = strings.clone(url, runtime.heap_allocator()), on_load = on_load, user = user, ctx = context}
	_fetch_start(f)
}

bitmap_free :: proc(b: ^Bitmap) {
	if b == nil do return
	b.refs -= 1
	if b.refs > 0 do return
	_bitmap_free(b)
	free(b)
}

@(private)
bitmap_retain :: proc(b: ^Bitmap) -> ^Bitmap {
	if b != nil do b.refs += 1
	return b
}

// A loaded font face, for Label / Input / Button `font` and `draw_text`. Reference counted like
// Bitmap: `font_free` drops the caller's reference and every widget using the font holds its own,
// so the app can free a font right after handing it over. Each Font is one face: load a bold file
// for bold text.
Font :: struct {
	native: rawptr, // CGFontRef / android.graphics.Typeface global ref / unused (fontconfig) / AddFontMemResourceEx handle
	extra:  rawptr, // Windows: the sized HFONT cache
	family: string, // the face's family name, from its `name` table; Linux and Windows select it by this
	weight: int,    // the face's weight, 100..900 (400 regular, 700 bold), from its OS/2 table
	italic: bool,
	refs:   int,
}

// Loads a TrueType / OpenType font from its bytes; nil if they are not one. `data` is not kept.
font_from_bytes :: proc(data: []u8) -> ^Font {
	family, weight, italic, ok := opentype_info(data)
	if !ok do return nil
	f := new(Font)
	f.family = family
	f.weight = weight
	f.italic = italic
	f.refs = 1
	if !_font_load(f, data) {
		delete(f.family)
		free(f)
		return nil
	}
	return f
}

// Loads a font file; a relative path names an asset, as for bitmap_from_file.
font_from_file :: proc(path: string) -> ^Font {
	return font_from_bytes(_asset_read(path, context.temp_allocator))
}

font_free :: proc(f: ^Font) {
	if f == nil do return
	f.refs -= 1
	if f.refs > 0 do return
	_font_free(f)
	delete(f.family)
	free(f)
}

@(private)
font_retain :: proc(f: ^Font) -> ^Font {
	if f != nil do f.refs += 1
	return f
}

// Reads a file for bitmap_from_file / font_from_file; a relative path resolves against the
// `assets` directory next to the executable (inside the .app on iOS). Android overrides this with
// the APK's assets.
@(private)
asset_read_file :: proc(path: string, allocator := context.allocator) -> []u8 {
	full := path
	if !os.is_absolute_path(path) {
		dir, err := os.get_executable_directory(context.temp_allocator)
		if err != nil do return nil
		full, _ = os.join_path({dir, "assets", path}, context.temp_allocator)
	}
	data, err := os.read_entire_file(full, allocator)
	if err != nil do return nil
	return data
}

// An image download in flight. Heap-allocated, since the worker thread has its own context:
// only `url` and `data` are touched off the UI thread.
@(private) Fetch :: struct {
	url:     string,
	data:    []u8, // heap; nil on failure
	on_load: proc(user: rawptr, b: ^Bitmap),
	user:    rawptr,
	ctx:     runtime.Context,
}

// Backends call this on the UI thread once the download finished (see _fetch_start).
@(private)
fetch_notify :: proc(f: ^Fetch) {
	callback_enter()
	defer callback_exit()
	b := bitmap_from_bytes(f.data)
	on_load, user := f.on_load, f.user
	delete(f.data, runtime.heap_allocator())
	delete(f.url, runtime.heap_allocator())
	free(f, runtime.heap_allocator())
	if on_load != nil {
		on_load(user, b)
	} else {
		bitmap_free(b)
	}
}

// How an image fills its view (Flutter's BoxFit).
Fit :: enum {
	Contain, // the whole image, letterboxed
	Cover,   // fills the view, cropped
	Fill,    // stretched
}

// An image view. It shows `bitmap` at once, or else downloads `url` and shows it once it is
// loaded. Its natural size is `width` × `height` when given, else the bitmap's (1 px per
// point / dp), and 0 while there is no bitmap; the cross axis of a Row / Column still stretches.
Image :: struct {
	bitmap: ^Bitmap, // the widget takes its own reference
	url:    string,
	fit:    Fit,
	width:  f64,     // points / dp; 0 for the bitmap's
	height: f64,
}

Image_Handle :: struct {
	image:  Image,   // image.bitmap and image.url are not used past image_create (see bitmap)
	ctx:    runtime.Context,
	root:   View,    // view embedded by the app
	view:   rawptr,  // NVImageView* / ImageView / GtkDrawingArea* / NVImage HWND; the handle holds a reference
	bitmap: ^Bitmap, // the one shown; owned reference
	seq:    int,     // bumped by every image_set_bitmap, so a fetch that lost the race is dropped
}

image_create :: proc(i: Image) -> ^Image_Handle {
	h := new(Image_Handle)
	h.image = i
	h.image.bitmap, h.image.url = nil, ""
	h.ctx = context
	h.bitmap = bitmap_retain(i.bitmap)
	_image_init(h)
	if i.bitmap == nil && i.url != "" {
		t := new(Image_Fetch)
		t^ = {h, h.seq}
		bitmap_fetch(i.url, image_fetched, t)
	}
	return h
}

image_view :: proc(h: ^Image_Handle) -> View {
	return h.root
}

// Shows `b` (nil for nothing) instead of the current bitmap, or of the one still downloading.
image_set_bitmap :: proc(h: ^Image_Handle, b: ^Bitmap) {
	h.seq += 1
	old := h.bitmap
	h.bitmap = bitmap_retain(b)
	_image_set_bitmap(h)
	bitmap_free(old)
}

@(private) Image_Fetch :: struct {
	h:   ^Image_Handle,
	seq: int,
}

@(private)
image_fetched :: proc(user: rawptr, b: ^Bitmap) {
	t := (^Image_Fetch)(user)
	defer free(t)
	if t.h.seq == t.seq && b != nil do image_set_bitmap(t.h, b)
	bitmap_free(b)
}

// Natural size in points / dp.
@(private)
image_natural_size :: proc "contextless" (h: ^Image_Handle) -> [2]f64 {
	s := [2]f64{h.image.width, h.image.height}
	if h.bitmap == nil do return s
	bw, bh := f64(h.bitmap.width), f64(h.bitmap.height)
	switch {
	case s.x <= 0 && s.y <= 0: s = {bw, bh}
	case s.x <= 0:             s.x = s.y * bw / bh // one side given: keep the aspect ratio
	case s.y <= 0:             s.y = s.x * bh / bw
	}
	return s
}

// Where the bitmap goes in a w × h view, for the backends that draw it themselves.
@(private)
image_fit_rect :: proc "contextless" (fit: Fit, b: ^Bitmap, w, h: f64) -> [4]f64 {
	bw, bh := f64(b.width), f64(b.height)
	if fit == .Fill || bw <= 0 || bh <= 0 do return {0, 0, w, h}
	s := fit == .Contain ? min(w / bw, h / bh) : max(w / bw, h / bh)
	return {(w - bw * s) / 2, (h - bh * s) / 2, bw * s, bh * s}
}

// A card over the current page, inside the window (not a separate OS window). A modal dialog dims
// the page and blocks it; a non-modal one floats over a page that stays usable. `content` is any
// view the app built from the widgets; it keeps its natural size (a bare list or canvas has none).
// The buttons sit in a row under the content and never close the dialog on their own: a callback
// gets the handle and calls `dialog_close` when it wants to. The dialog belongs to the page on top
// when it is shown: it hides under a page pushed later and closes when its page pops.
Dialog :: struct {
	title:    string,              // copied; "" for none
	content:  View,                // optional
	buttons:  []Dialog_Button,     // copied
	modal:    bool,
	on_close: proc(user: rawptr),  // optional; after the dialog is gone (the last call the handle is valid for)
	user:     rawptr,
}

Dialog_Button :: struct {
	title:    string, // copied
	on_click: proc(dialog: ^Dialog_Handle, user: rawptr), // optional
	user:     rawptr,
}

Dialog_Handle :: struct {
	dialog:  Dialog,               // dialog.title is an owned copy; dialog.buttons is not kept (see buttons)
	ctx:     runtime.Context,
	page:    ^Page_Handle,         // the page it was shown on
	body:    View,                 // Column [title label, content, Row of buttons]; owned by the card
	title:   ^Label_Handle,        // nil without a title
	buttons: []^Dialog_Button_Handle,
	card:    rawptr,               // NSBox* / UIView* / FrameLayout global ref / GtkBox* / NVDialog HWND
	scrim:   rawptr,               // the dimming layer, modal only
	hidden:  bool,                 // another page is on top of its page
}

@(private) Dialog_Button_Handle :: struct {
	dialog: ^Dialog_Handle,
	button: Dialog_Button, // button.title is an owned copy
	handle: ^Button_Handle,
}

// Shown dialogs in show order, and dialogs shown from inside a `build`, which appear once the
// page is shown (nav_present).
@(private) g_dialogs:         [dynamic]^Dialog_Handle
@(private) g_dialogs_pending: [dynamic]^Dialog_Handle

// Shows a dialog over the top page. From inside a `build`, it appears once that page is shown.
dialog_show :: proc(d: Dialog) -> ^Dialog_Handle {
	assert(len(g_nav) > 0, "nv.dialog_show before nv.run")
	h := new(Dialog_Handle)
	h.dialog = d
	h.dialog.title = strings.clone(d.title)
	h.dialog.buttons = nil // the app's slice; not kept
	h.ctx = context
	h.page = g_nav[len(g_nav) - 1] // inside a build: the page being built, already on the stack
	h.buttons = make([]^Dialog_Button_Handle, len(d.buttons))
	for b, i in d.buttons {
		bh := new(Dialog_Button_Handle)
		bh.dialog = h
		bh.button = b
		bh.button.title = strings.clone(b.title)
		h.buttons[i] = bh
	}
	if g_nav_building > 0 {
		append(&g_dialogs_pending, h)
		return h
	}
	dialog_present(h)
	return h
}

// Removes the dialog, calls `on_close` and frees the handle. The widget handles of the title and
// the buttons leak, like a popped page's: handles have no destroy.
dialog_close :: proc(h: ^Dialog_Handle) {
	if i, found := slice.linear_search(g_dialogs_pending[:], h); found {
		ordered_remove(&g_dialogs_pending, i) // never shown: nothing to take down
	} else {
		i, found := slice.linear_search(g_dialogs[:], h)
		if !found do return
		ordered_remove(&g_dialogs, i) // before _dialog_close: the backend reads dialog_top_modal for the state after
		_dialog_close(h)
		h.card, h.scrim, h.body = nil, nil, nil
	}
	if h.dialog.on_close != nil {
		callback_enter()
		defer callback_exit()
		h.dialog.on_close(h.dialog.user)
	}
	dialog_free(h)
}

// Builds the body from the framework's own widgets, so the backends only add the card and the
// scrim: a Column of the title (a bold label), the content and a Row of the buttons (equal widths).
@(private)
dialog_present :: proc(h: ^Dialog_Handle) {
	children := make([dynamic]Flex_Child, context.temp_allocator)
	if h.dialog.title != "" {
		h.title = label_create({text = h.dialog.title, bold = true})
		append(&children, Flex_Child{label_view(h.title), 0})
	}
	if h.dialog.content != nil do append(&children, Flex_Child{h.dialog.content, 0})
	if len(h.buttons) > 0 {
		row := make([]Flex_Child, len(h.buttons), context.temp_allocator)
		for bh, i in h.buttons {
			bh.handle = button_create({title = bh.button.title, on_click = dialog_button_clicked, user = bh})
			row[i] = {button_view(bh.handle), 1}
		}
		append(&children, Flex_Child{row_create(row, spacing = 8), 0})
	}
	h.body = column_create(children[:], spacing = 12)
	append(&g_dialogs, h)
	_dialog_show(h)
}

// The body buttons' on_click. The app's callback may close the dialog, which frees `bh`.
@(private)
dialog_button_clicked :: proc(user: rawptr) {
	bh := (^Dialog_Button_Handle)(user)
	if bh.button.on_click != nil do bh.button.on_click(bh.dialog, bh.button.user)
}

@(private)
dialog_free :: proc(h: ^Dialog_Handle) {
	for bh in h.buttons {
		delete(bh.button.title)
		free(bh)
	}
	delete(h.buttons)
	delete(h.dialog.title)
	free(h)
}

// The visible modal dialog of the top page, or nil. Contextless for the Win32 layout code.
@(private)
dialog_top_modal :: proc "contextless" () -> ^Dialog_Handle {
	if len(g_nav) == 0 do return nil
	return dialog_page_modal(g_nav[len(g_nav) - 1])
}

@(private)
dialog_page_modal :: proc "contextless" (page: ^Page_Handle) -> ^Dialog_Handle {
	#reverse for d in g_dialogs {
		if d.page == page && d.dialog.modal && !d.hidden do return d
	}
	return nil
}

@(private)
dialog_close_page :: proc(page: ^Page_Handle) {
	for i := len(g_dialogs) - 1; i >= 0; i -= 1 {
		if i < len(g_dialogs) && g_dialogs[i].page == page do dialog_close(g_dialogs[i]) // on_close may close others
	}
	for i := len(g_dialogs_pending) - 1; i >= 0; i -= 1 {
		if i < len(g_dialogs_pending) && g_dialogs_pending[i].page == page do dialog_close(g_dialogs_pending[i])
	}
}

@(private)
dialog_set_page_hidden :: proc(page: ^Page_Handle, hidden: bool) {
	for d in g_dialogs {
		if d.page != page || d.hidden == hidden do continue
		d.hidden = hidden
		_dialog_set_hidden(d, hidden)
	}
}

@(private)
dialog_flush_pending :: proc() {
	for len(g_dialogs_pending) > 0 {
		h := g_dialogs_pending[0]
		ordered_remove(&g_dialogs_pending, 0)
		dialog_present(h)
	}
}
