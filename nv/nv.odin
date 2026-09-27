package nv

// Shared public API. Platform backends: *_macos.odin / *_ios.odin (`#+build darwin`,
// split by `when IS_IOS` since build tags can't select the iOS subtarget),
// *_android.odin (`#+build linux:android`), *_linux.odin (`#+build linux:default`, GTK4) and
// *_windows.odin (`#+build windows`, Win32).
//
// Widgets: a scrolling list (`list_create`), a text label (`label_create`), a text input
// (`input_create`), a push button (`button_create`), a custom-drawn canvas (`canvas_create`) and
// Flutter-style Row / Column stacks (`row_create`, `column_create`, `flex_create`). Pages stack
// with `push` / `pop`; `run` shows the root page. A page's bar carries its title, a back button
// and its `actions` (`page_set_title`, `page_set_actions`).
//
// Every widget follows one shape: `X :: struct` describes it, `x_create(X) -> ^X_Handle` makes it,
// `x_view(h)` is the view to embed, `x_set_y(h, ..)` changes it. Row / Column return a plain View:
// their children are fixed at creation, like Flutter.

import "base:builtin"
import "base:runtime"
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
// the trailing buttons of the page's bar (Flutter's AppBar.actions).
Page :: struct {
	title:   string, // copied
	build:   Build_Proc,
	user:    rawptr,
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
// `pop` shadows the builtin, hence builtin.pop.
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
	_nav_push(h)
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
	h.root = h.page.build(h, h.page.user)
	g_nav_building -= 1
}

// Builds and shows the root page; every backend calls this once views can exist, bracketed.
@(private)
nav_show_root :: proc() {
	nav_build(g_nav[0])
	_nav_push(g_nav[0])
	nav_flush_pending()
}

@(private)
nav_flush_pending :: proc() {
	for len(g_nav_pending) > 0 {
		h := g_nav_pending[0]
		ordered_remove(&g_nav_pending, 0)
		append(&g_nav, h)
		nav_build(h)
		_nav_push(h)
	}
}

// Bookkeeping for a pop the platform already performed.
@(private)
nav_system_pop :: proc() {
	if len(g_nav) <= 1 do return
	top := builtin.pop(&g_nav)
	nav_finish_pop(top)
}

@(private)
nav_finish_pop :: proc(top: ^Page_Handle) {
	_nav_release(top)
	top.root, top.native = nil, nil // a page_set_* from on_pop has nothing to show
	if top.page.on_pop != nil {
		callback_enter()
		defer callback_exit()
		top.page.on_pop(top.page.user)
	}
	nav_actions_free(top)
	delete(top.page.title)
	free(top)
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

// Called by the backends when an action was clicked. The callback may replace the page's actions
// or pop the page, which frees `h`, so nothing is read from it afterwards.
@(private)
action_notify :: proc(h: ^Action_Handle) {
	cb, user := h.action.on_click, h.action.user
	if cb == nil do return
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

// Single-line bold text.
Label :: struct {
	text: string, // copied
}

Label_Handle :: struct {
	label: Label, // label.text is an owned copy, kept current by label_set_text
	root:  View,  // the NSTextField* / UILabel* / TextView / GtkLabel* / Static HWND, embedded by the app
}

label_create :: proc(l: Label) -> ^Label_Handle {
	h := new(Label_Handle)
	h.label = l
	h.label.text = strings.clone(l.text)
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

// Single-line text input. Callbacks get the current text, valid only during the call.
Input :: struct {
	text:        string, // initial text
	placeholder: string,
	on_change:   proc(user: rawptr, text: string), // optional; on every edit by the user
	on_submit:   proc(user: rawptr, text: string), // optional; Return / Enter / the keyboard's Done key
	user:        rawptr,
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

// Push button with a text title.
Button :: struct {
	title:    string, // copied
	on_click: proc(user: rawptr), // optional
	user:     rawptr,
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

// One line of text in the system font; (x, y) is the top-left of its line box.
draw_text :: proc(p: ^Painter, text: string, x, y: f64, size: f64, color: Color) {
	_draw_text(p, text, x, y, size, color)
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
