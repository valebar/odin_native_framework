package nv

// Shared public API. Platform backends: *_macos.odin / *_ios.odin (`#+build darwin`,
// split by `when IS_IOS` since build tags can't select the iOS subtarget) and
// *_android.odin (`#+build linux`).

import "base:runtime"

IS_IOS     :: ODIN_PLATFORM_SUBTARGET_IOS
IS_ANDROID :: ODIN_PLATFORM_SUBTARGET == .Android

// Opaque native view: NSView* on macOS, UIView* on iOS, global jobject on Android.
View :: distinct rawptr

Row :: struct {
	title:    string,
	subtitle: string,
}

List :: struct {
	count:      proc(user: rawptr) -> int,
	row:        proc(user: rawptr, index: int) -> Row,
	on_select:  proc(user: rawptr, index: int), // optional
	row_height: f64,
	user:       rawptr,
}

List_Handle :: struct {
	list:          List,
	ctx:           runtime.Context,
	root:          View,   // view embedded by the app
	table:         rawptr, // NSTableView* / UITableView*
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
