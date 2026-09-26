package nv

// Shared public API. Platform backends: *_macos.odin / *_ios.odin (`#+build darwin`,
// split by `when IS_IOS` since build tags can't select the iOS subtarget),
// *_android.odin (`#+build linux:android`) and *_linux.odin (`#+build linux:default`, GTK4).
//
// Widgets: a scrolling list (`list_create`), a text label (`label_create`) and Flutter-style
// Row / Column stacks (`row_create`, `column_create`, `flex_create`).

import "base:runtime"

IS_IOS     :: ODIN_PLATFORM_SUBTARGET_IOS
IS_ANDROID :: ODIN_PLATFORM_SUBTARGET == .Android

// Opaque native view: NSView* on macOS, UIView* on iOS, global jobject on Android, GtkWidget* on Linux.
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
	table:         rawptr, // NSTableView* / UITableView* / ListView / GtkListView*
	data_source:   rawptr,
	cells_created: int,    // debug: proves reuse
}

Build_Proc :: proc(user: rawptr) -> View

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
// UILayoutConstraintAxis and LinearLayout.HORIZONTAL / VERTICAL, so backends cast directly.
Axis :: enum { Horizontal, Vertical }

// One child of a Row / Column. `flex` 0 keeps the natural size; `flex` > 0 shares the space left
// on the main axis in proportion to the other flex children (Flutter's Expanded). The cross axis
// always stretches. Weights other than 1 are exact on Apple and Android; GTK shares equally.
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
