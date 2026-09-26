package nv

// Shared public API. Platform backends: *_macos.odin / *_ios.odin (`#+build darwin`,
// split by `when IS_IOS` since build tags can't select the iOS subtarget),
// *_android.odin (`#+build linux:android`), *_linux.odin (`#+build linux:default`, GTK4) and
// *_windows.odin (`#+build windows`, Win32).
//
// Widgets: a scrolling list (`list_create`), a text label (`label_create`), a text input
// (`input_create`), a push button (`button_create`) and Flutter-style Row / Column stacks
// (`row_create`, `column_create`, `flex_create`).

import "base:runtime"

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
	on_select:  proc(user: rawptr, index: int), // optional
	row_height: f64,
	user:       rawptr,
}

List_Handle :: struct {
	list:          List,
	ctx:           runtime.Context,
	root:          View,   // view embedded by the app
	table:         rawptr, // NSTableView* / UITableView* / ListView / GtkListView* / SysListView32 HWND
	data_source:   rawptr,
	cells_created: int,    // debug: proves reuse (always 0 on Windows: the virtual ListView has no row objects)
}

Build_Proc :: proc(user: rawptr) -> View

// Temp memory belongs to the callback in progress and is freed when the outermost one returns.
// Callbacks nest: an on_click that calls input_set_text or list_reload can trigger a change
// notification or a row callback, and a Win32 layout re-enters the procs of nested views. An inner
// callback that freed would wipe strings the outer one (and the app) still holds. So every entry
// from the platform into Odin code that allocates or calls the app is bracketed by these, and
// procs the app calls never free.
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

// Opens a window and blocks in the platform event loop.
// `build` runs once the platform is ready to create views.
run :: proc(title: string, build: Build_Proc, user: rawptr = nil) {
	_run(title, build, user)
}

list_create :: proc(l: List) -> ^List_Handle {
	h := new(List_Handle)
	h.list = l
	if h.list.row_height <= 0 do h.list.row_height = 44
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

// Single-line bold text. `text` is copied.
label_create :: proc(text: string) -> View {
	return _label_create(text)
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
	title:    string,
	on_click: proc(user: rawptr), // optional
	user:     rawptr,
}

Button_Handle :: struct {
	button:  Button,
	ctx:     runtime.Context,
	root:    View,   // view embedded by the app
	control: rawptr, // NSButton* / UIButton* / Button / GtkButton* / Button HWND
	target:  rawptr, // target / listener object, where the platform needs one
}

button_create :: proc(b: Button) -> ^Button_Handle {
	h := new(Button_Handle)
	h.button = b
	h.ctx = context
	_button_init(h)
	return h
}

button_view :: proc(h: ^Button_Handle) -> View {
	return h.root
}

// Replaces the title; `title` is copied. The size of a flex-0 button follows on the next layout.
button_set_title :: proc(h: ^Button_Handle, title: string) {
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
