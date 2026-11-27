package nv

// Shared public API. Platform backends: *_macos.odin (`#+build darwin:default`) / *_ios.odin
// (`#+build darwin:ios`: the device and the simulator), with what they share in appkit.odin and
// cg.odin (`#+build darwin`), *_android.odin (`#+build linux:android`), *_linux.odin
// (`#+build linux:default`, GTK4), *_windows.odin (`#+build windows`, Win32) and *_web.odin
// (`#+build js`: the DOM, through nv/web/nv.js; web.odin). The core reaches
// them through g_backend (backend.odin), except the draw procs, which it calls directly.
//
// Widgets: a scrolling list (`list_create`), a text label (`label_create`), a text input
// (`input_create`), a push button (`button_create`), a custom-drawn canvas (`canvas_create`), an
// image (`image_create`), a circular progress indicator (`progress_create`), Flutter-style Row / Column stacks (`row_create`, `column_create`,
// `flex_create`), a Stack that layers its children (`stack_create`), a Container (`container_create`): a box with margin, border, background,
// rounded corners and padding around one child, and a Layout (`layout_create`), Flutter's LayoutBuilder: it tells the app its size.
// Images are decoded into a Bitmap from bytes, a file or a URL (`bitmap_from_bytes`,
// `bitmap_from_file`, `bitmap_fetch`), which the canvas can draw too (`draw_image`). Pages stack
// with `push` / `pop`; `run` shows the root page. A page's bar carries its title, a back button,
// its `actions` and a leading view (`page_set_title`, `page_set_actions`, `page_set_bar_leading`). A dialog (`dialog_show`,
// `dialog_close`) is a card drawn over the page inside the window, modal or not. A page's body can
// be a Flutter-style Scaffold (`scaffold_create`, scaffold.odin): bottom tabs, a floating action
// button, SnackBars (`scaffold_show_snackbar`) and a drawer opened from the bar. A Font loaded
// from bytes or an asset file (`font_from_bytes`, `font_from_file`) can replace the system font in
// labels, inputs, buttons and canvas text. A worker thread hands its results back to the main
// thread with `post_main`. The user picks a file to read or a place to save one with `file_open` /
// `file_save`.
//
// Every widget follows one shape: `X :: struct` describes it, `x_create(X) -> ^X_Handle` makes it,
// `view(h)` is the view to embed, `x_set_y(h, ..)` changes it. Row / Column / Stack return a plain
// View: their children are fixed at creation, like Flutter. Callbacks take `user` first.

import "base:builtin"
import "base:runtime"
import "core:slice"
import "core:strings"
import "core:time"

// Opaque native view: NSView* on macOS, UIView* on iOS, global jobject on Android, GtkWidget* on Linux,
// HWND on Windows, an element id (nv.js's table) on the web.
View :: distinct rawptr

// A widget's view, to embed in a Row / Column / Stack / Container / Dialog / Scaffold.
view :: proc{list_view, label_view, input_view, button_view, canvas_view, image_view, progress_view, container_view, layout_view, stack_view, scaffold_view}

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
	title_style:    Text_Style, // over the platform's row fonts (the theme's styles don't apply: rows have a fixed height)
	subtitle_style: Text_Style,
}

List_Handle :: struct {
	list:          List,
	scope:         ^Scope,
	count:         int, // what list.count said last: a detached list keeps showing that many rows
	ctx:           runtime.Context,
	root:          View,   // view embedded by the app
	table:         rawptr, // NSTableView* / UITableView* / ListView / GtkListView* / SysListView32 HWND
	data_source:   rawptr,
	cells_created: int,    // debug: proves reuse (always 0 on Windows: the virtual ListView has no row objects)
}

// Temp memory belongs to the callback in progress and is freed when the outermost one returns,
// after the scopes retired meanwhile (see Scope) were destroyed.
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
	if g_callback_depth > 0 do return
	scope_flush_retired()
	free_all(context.temp_allocator)
}

// One screen of the navigation stack. `build` runs when the page is pushed and gets the page's
// handle; `on_pop` runs after the page left the stack, so the app can free its own data (it is
// the last call the page's handle is valid for). The widgets created while the page was on top
// belong to it, and their handles stay valid through `on_pop`: nv frees them, with their native
// views, once the page's views are gone. `actions` are the trailing buttons of the page's bar
// (Flutter's AppBar.actions). Dialogs shown while the page is on top belong to it: they hide under
// a pushed page and close when the page pops. `on_covered` tells the page it went under a pushed
// page (true, once that page is shown) and came back on top after a pop (false), the system's
// back included; not on the first show, and never for the page that pops.
Page :: struct {
	title:      string, // copied
	build:      Build_Proc,
	user:       rawptr,
	on_pop:     proc(user: rawptr), // optional
	actions:    []Action,           // copied
	on_covered: proc(user: rawptr, covered: bool), // optional
}

Build_Proc :: proc(user: rawptr, page: ^Page_Handle) -> View

// System icons every platform has (SF Symbols / android.R.drawable / GTK icon names / Segoe MDL2
// Assets). A platform without a given icon shows the action's title as text instead.
Icon :: enum { None, Add, Edit, Delete, Search, Share, Settings, Refresh, Done, Info, More, Close, Menu, Home, Star, Person, Hub }

// Material's menu icon (Apache 2.0) on a 24-unit grid: Android draws it, having no hamburger
// drawable (nv.js has the same path).
@(private) MATERIAL_MENU_PATH :: "M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z"

// Material's search icon (Apache 2.0): Android draws it, its system magnifier being Holo's.
@(private) MATERIAL_SEARCH_PATH :: "M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"

// Material's hub icon (Apache 2.0) on a 24-unit grid, for the backends that draw it themselves
// (GTK bundles it, Android draws it; nv.js has the same path).
@(private) MATERIAL_HUB_PATH :: "M8.4 18.2c.38.5.6 1.12.6 1.8 0 1.66-1.34 3-3 3s-3-1.34-3-3 1.34-3 3-3c.44 0 .85.09 1.23.26l1.41-1.77c-.92-1.03-1.29-2.39-1.09-3.69l-2.03-.68C4.98 11.95 4.06 12.5 3 12.5c-1.66 0-3-1.34-3-3s1.34-3 3-3 3 1.34 3 3c0 .07 0 .14-.01.21l2.03.68c.64-1.21 1.82-2.09 3.22-2.32V5.91C9.96 5.57 9 4.4 9 3c0-1.66 1.34-3 3-3s3 1.34 3 3c0 1.4-.96 2.57-2.25 2.91v2.16c1.4.23 2.58 1.11 3.22 2.32l2.03-.68c-.01-.07-.01-.14-.01-.21 0-1.66 1.34-3 3-3s3 1.34 3 3-1.34 3-3 3c-1.06 0-1.98-.55-2.52-1.37l-2.03.68c.2 1.29-.16 2.65-1.09 3.69l1.41 1.77c.38-.17.79-.26 1.23-.26 1.66 0 3 1.34 3 3s-1.34 3-3 3-3-1.34-3-3c0-.68.22-1.3.6-1.8l-1.41-1.77c-1.35.75-3.01.76-4.37 0L8.4 18.2z"

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
// pointer is stable while the stack grows. The page's widgets live in its `scope`, which outlives
// the handle: the backend retires it once the popped page's views are gone (`_nav_release`).
Page_Handle :: struct {
	page:    Page,                    // page.title is an owned copy; page.actions is not used past push
	root:    View,                    // owned; nil while `build` runs and once released
	actions: [dynamic]^Action_Handle, // owned; freed by nav_actions_free
	native:  rawptr,                  // backend per-page object: the UIViewController on iOS
	scope:   ^Scope,                  // the page's widgets; handed to the backend by _nav_release
	scaffold: ^Scaffold_Handle,       // set by scaffold_create during `build`, nil without one
	bar_leading: View,                // page_set_bar_leading's view, nil for none
	covered: bool,                    // a page was pushed over it (on_covered(true) was the last)
}

// The page stack: g_nav[0] is the root page from `run`, the depth is len(g_nav) - 1. Backends
// implement _run (start the platform; once views can exist, inside _run or from a later platform
// callback such as Android's first onCreate, call theme_start and then nav_show_root, bracketed;
// _run may return before that; iOS builds the root itself with nav_build and nav_flush_pending,
// since its navigation controller takes the root controller up front), _nav_push
// (show the new top page, already in g_nav, with its title and chrome), _nav_pop (the native
// transition back to `below`, already the top of g_nav; false if the platform refused),
// _nav_release (the page left for good: retire `h.scope` once its views are gone; the scope's
// disposers release the views, the backend only detaches them), _nav_title_changed and
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

// Makes nv take all of its own memory from `allocator` instead of the heap: what outlives a
// callback (nv_heap), the blocks of the pages' and dialogs' arenas, downloads, timers. Call it
// before `run` and before loading fonts or bitmaps. Download threads and post_main allocate from
// other threads, so it must be thread-safe; nv frees into it as before, so an arena that ignores
// frees will do.
set_allocator :: proc(allocator: runtime.Allocator) {
	assert(len(g_nav) == 0, "nv.set_allocator before nv.run")
	g_heap = allocator
}

// Opens a window showing the root page and blocks in the platform event loop; on Android it
// returns at once and the app keeps running (the first Activity builds the page). `build` runs
// once the platform is ready to create views: before `run` the app calls only `set_allocator`,
// `theme_set` / `theme_set_mode` and the font loaders for the theme's fonts (Windows starts GDI+,
// which decodes bitmaps, in `_run`).
run :: proc(p: Page) {
	assert(len(g_nav) == 0, "nv.run twice")
	g_main_ctx = context
	append(&g_nav, nav_page_new(p))
	g_backend.run()
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
// nothing and popping from a later callback). While the platform is in the middle of a transition
// and refuses (UIKit), the page goes once it finished, if it is still the top then.
pop :: proc() {
	if len(g_nav) <= 1 || g_nav_building > 0 do return
	top := builtin.pop(&g_nav)
	if !g_backend.nav_pop(top, g_nav[len(g_nav) - 1]) {
		append(&g_nav, top) // the platform is mid-transition; the page stays for now
		g_nav_pop_waiting = top
		return
	}
	nav_finish_pop(top)
}

// The top page a refused pop is for (nil for none); nav_finish_pop clears it when the page goes
// otherwise, so a freed handle is never compared.
@(private) g_nav_pop_waiting: ^Page_Handle

// Called by the backends when a push or pop transition finished: a pop the platform refused
// meanwhile runs now.
@(private)
nav_transition_done :: proc() {
	e := g_nav_pop_waiting
	g_nav_pop_waiting = nil
	if e == nil || len(g_nav) <= 1 || g_nav[len(g_nav) - 1] != e do return
	callback_enter()
	defer callback_exit()
	pop()
}

// Runs `fn(user)` on the main thread from the event loop, soon, in post order; callable from any
// thread, so a worker hands its result back this way. `fn` runs inside a callback bracket like
// every other callback (its temp memory is freed after it), with the context `run` was called
// with: the poster's temp allocator belongs to its own thread. `user` stays the app's: nv neither
// copies nor frees it. Called after `run` only.
post_main :: proc(fn: proc(user: rawptr), user: rawptr) {
	assert(g_main_ctx.allocator.procedure != nil, "nv.post_main before nv.run")
	t := new(Timer, nv_heap())
	t^ = {fn = fn, user = user, ctx = g_main_ctx}
	g_backend.post_timer(t)
}

// The context `run` was called with, on the main thread; post_main's callbacks run with it.
@(private) g_main_ctx: runtime.Context

// Replaces the title shown in the page's bar; `title` is copied.
page_set_title :: proc(h: ^Page_Handle, title: string) {
	old := h.page.title
	h.page.title = strings.clone(title)
	delete(old)
	if h.root != nil do g_backend.nav_title_changed(h) // nil while `build` runs: the _nav_push that follows shows it
}

// Replaces the page's actions. Frees the old ones, including the one whose `on_click` may be
// making this call.
page_set_actions :: proc(h: ^Page_Handle, actions: []Action) {
	nav_actions_assign(h, actions)
	if h.root != nil do g_backend.nav_actions_changed(h)
}

// Puts `view` in the page's bar right after the back / menu button, nil removes it: the leading
// cluster of a Flutter AppBar's title. Settable any time; the bar shows the top page's. The view is
// built in this page's scope and embedded nowhere else; it lives until the page is gone, so a page
// can switch between views it built once and nil. It keeps its natural size, centred vertically; a
// bar lower than that gives it the bar's height (macOS's title bar: about 24 points). The title stays
// centred over the whole bar and moves aside only as far as the leading view and the actions need.
page_set_bar_leading :: proc(h: ^Page_Handle, view: View) {
	h.bar_leading = view
	if h.root != nil do g_backend.nav_leading_changed(h) // nil while `build` runs: the _nav_push that follows shows it
}

@(private)
nav_page_new :: proc(p: Page) -> ^Page_Handle {
	h := new(Page_Handle)
	h.page = p
	h.scope = scope_new()
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
	h.root = h.page.build(h.page.user, h)
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
	below := len(g_nav) > 1 ? g_nav[len(g_nav) - 2] : nil
	if below != nil do dialog_set_page_hidden(below, true)
	g_backend.nav_push(h)
	dialog_flush_pending()
	if below != nil && !below.covered do nav_covered_notify(below, true)
}

// Tells a page it went under another page or came back on top; `covered` tracks it, so a page
// hears each change once.
@(private)
nav_covered_notify :: proc(e: ^Page_Handle, covered: bool) {
	e.covered = covered
	if e.page.on_covered == nil do return
	callback_enter()
	defer callback_exit()
	e.page.on_covered(e.page.user, covered)
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

// The same for a page the platform names: iOS pops by controller, and a push queued behind the
// pop may already sit above it in g_nav.
@(private)
nav_system_pop_page :: proc(e: ^Page_Handle) {
	for p, i in g_nav[1:] do if p == e {
		ordered_remove(&g_nav, i + 1)
		nav_finish_pop(e)
		return
	}
}

// The page's dialogs close first (their on_close still sees a live page), and the dialogs of the
// page below come back.
@(private)
nav_finish_pop :: proc(top: ^Page_Handle) {
	dialog_close_page(top)
	file_detach_page(top)
	if top.scope != nil do top.scope.detached = true // the app frees in on_pop; the views may still show
	if g_nav_pop_waiting == top do g_nav_pop_waiting = nil
	g_backend.nav_release(top) // retires top.scope now or later: the widget handles stay valid through on_pop
	top.root, top.native, top.scope = nil, nil, nil // a page_set_* from on_pop has nothing to show
	nav_detach_scaffold(top)
	if top.page.on_pop != nil {
		callback_enter()
		defer callback_exit()
		top.page.on_pop(top.page.user)
	}
	nav_actions_free(top)
	delete(top.page.title)
	free(top)
	now := g_nav[len(g_nav) - 1]
	dialog_set_page_hidden(now, false)
	if now.covered do nav_covered_notify(now, false) // not when a page popped from under the top (iOS)
}

// The page's scaffold dies with its scope, which may outlive the page's views (and the handle):
// called wherever a page gives up its scope, so nothing reads the scaffold through the page later.
@(private)
nav_detach_scaffold :: proc "contextless" (e: ^Page_Handle) {
	e.scaffold = nil
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
// dialog is up, since the bar sits outside the scrim on macOS and GTK. An open drawer closes
// instead of the page popping, as Flutter's back does.
@(private)
nav_back_notify :: proc() {
	if dialog_top_modal() != nil do return
	callback_enter()
	defer callback_exit()
	if s := scaffold_top_drawer(); s != nil do scaffold_close_drawer(s)
	else do pop()
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

// What the backends ask of a list's owner, always through these: a detached list (see Scope)
// keeps its last count, shows empty rows and reports no selection.
@(private)
list_count :: proc(h: ^List_Handle) -> int {
	if scope_live(h.scope) do h.count = h.list.count(h.list.user)
	return h.count
}

@(private)
list_item :: proc(h: ^List_Handle, row: int) -> Item {
	if !scope_live(h.scope) do return {}
	return h.list.item(h.list.user, row)
}

@(private)
list_select :: proc(h: ^List_Handle, row: int) {
	if h.list.on_select != nil && scope_live(h.scope) do h.list.on_select(h.list.user, row)
}

list_create :: proc(l: List) -> ^List_Handle {
	h := scope_new_in(List_Handle)
	h.list = l
	if h.list.item_height <= 0 do h.list.item_height = 44
	h.ctx = context
	g_backend.list_init(h)
	return h
}

@(private)
list_view :: proc(h: ^List_Handle) -> View {
	return h.root
}

list_reload :: proc(h: ^List_Handle) {
	g_backend.list_reload(h)
}

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

// Children are fixed at creation, like Flutter. Every view lives until the page (or dialog) that
// created it is gone.
flex_create :: proc(f: Flex) -> View {
	return g_backend.flex_create(f)
}

row_create :: proc(children: []Flex_Child, spacing: f64 = 0) -> View {
	return g_backend.flex_create({axis = .Horizontal, spacing = spacing, children = children})
}

column_create :: proc(children: []Flex_Child, spacing: f64 = 0) -> View {
	return g_backend.flex_create({axis = .Vertical, spacing = spacing, children = children})
}

// Where a Stack child sits on each axis: at the start (left / top), centered, at the end, or
// stretched between the margins.
Align :: enum { Start, Center, End, Fill }

// One child of a Stack: Flutter's Align and Positioned in one. The zero value sits top-left at its
// natural size (Flutter's default topStart). `margin` is the distance from the stack's edges on the
// aligned sides (Positioned's left / top / right / bottom; ignored when centered); `width` /
// `height` fix the child's size (0 = natural; ignored on a Fill axis).
Stack_Child :: struct {
	view:          View,
	h, v:          Align,
	margin:        Insets,
	width, height: f64,
}

// Flutter's Stack: the children are layered in order, the last on top, and the topmost child under
// the pointer takes it (a plain label too, as in Flutter; an iOS label and a Windows Static, which
// answers HTTRANSPARENT, let the pointer through). The
// stack's natural size is the largest child's, margins included; a Row / Column stretches it like
// any child. Children are fixed at creation, like Row / Column; `stack_place` moves or resizes one.
stack_create :: proc(children: []Stack_Child) -> ^Stack_Handle {
	h := scope_new_in(Stack_Handle)
	h.overlay = overlay_new(view(container_create({}))) // the base sizes nothing
	h.children = make([]View, len(children), scope_allocator(scope_current()))
	for c, i in children {
		assert(c.view != nil, "nv.stack_create: a child is a view")
		h.children[i] = c.view
		g_backend.overlay_add(h.overlay, c.view, stack_overlay_place(c))
	}
	h.root = h.overlay.root
	return h
}

Stack_Handle :: struct {
	root:     View,   // embedded by the app
	children: []View, // in order (the scope's arena)
	overlay:  ^Overlay_Handle,
}

@(private)
stack_view :: proc(h: ^Stack_Handle) -> View {
	return h.root
}

// Gives `child`, one of the stack's children, a new place and size (`place.view` is ignored); its
// paint order stays.
stack_place :: proc(h: ^Stack_Handle, child: View, place: Stack_Child) {
	_, found := slice.linear_search(h.children, child)
	assert(found, "nv.stack_place: a child of this stack")
	g_backend.overlay_place(h.overlay, child, stack_overlay_place(place))
}

@(private)
stack_overlay_place :: proc "contextless" (c: Stack_Child) -> Overlay_Place {
	m := c.margin // a centered axis ignores its margins on every backend
	if c.h == .Center do m.left, m.right = 0, 0
	if c.v == .Center do m.top, m.bottom = 0, 0
	return {h = c.h, v = c.v, margin = m, width = c.width, height = c.height, sizes = true}
}

// Hides or shows any view (Flutter's Visibility / Offstage). A hidden child of a Row / Column
// takes no space, so a layout can swap between alternatives built once: Row / Column children are
// fixed at creation. Views start shown.
view_set_hidden :: proc(v: View, hidden: bool) {
	g_backend.view_set_hidden(v, hidden)
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
	h := scope_new_in(Container_Handle)
	h.container = c
	h.ctx = context
	g_backend.container_init(h)
	return h
}

@(private)
container_view :: proc(h: ^Container_Handle) -> View {
	return h.root
}

// Replaces the background color (alpha 0 removes it).
container_set_color :: proc(h: ^Container_Handle, color: Color) {
	h.container.color = color
	g_backend.container_set_color(h)
}

// Replaces `width` / `height` (0 = from the child), as Container's.
container_set_size :: proc(h: ^Container_Handle, width, height: f64) {
	if h.container.width == width && h.container.height == height do return
	h.container.width, h.container.height = width, height
	g_backend.container_set_size(h)
}

// Flutter's LayoutBuilder: `child` fills the view, which fills the slot its parent gives it (give
// it flex > 0 or a stretched cross axis: its own size must not depend on what on_layout changes).
// `on_layout` runs when the view first gets a size and whenever that size changes, before the new
// size is painted where the platform allows, so it can `view_set_hidden` / `container_set_size`
// inside. Never for 0 × 0 (hidden, not laid out yet): shown again at its last size, it is not told.
Layout :: struct {
	child:     View,
	on_layout: proc(user: rawptr, width, height: f64), // points / dp
	user:      rawptr,
}

Layout_Handle :: struct {
	layout:    Layout,
	scope:     ^Scope,
	ctx:       runtime.Context,
	root:      View,   // embedded by the app
	native:    rawptr, // backend data
	size:      [2]f64, // the last size reported; {} before the first
	notifying: bool,
	again:     bool,   // a new size arrived during on_layout (Windows re-enters synchronously)
}

layout_create :: proc(l: Layout) -> ^Layout_Handle {
	assert(l.child != nil, "nv.layout_create: the child is a view")
	h := scope_new_in(Layout_Handle)
	h.layout = l
	h.ctx = context
	g_backend.layout_init(h)
	return h
}

@(private)
layout_view :: proc(h: ^Layout_Handle) -> View {
	return h.root
}

// The size last reported to on_layout (0, 0 before the first).
layout_size :: proc(h: ^Layout_Handle) -> (width, height: f64) {
	return h.size.x, h.size.y
}

// An answer that keeps resizing the Layout itself stops after this many passes.
@(private) LAYOUT_MAX_PASSES :: 4

// Called by the backends with the view's size, whenever it may have changed.
@(private)
layout_notify :: proc(h: ^Layout_Handle, width, height: f64) {
	if width <= 0 || height <= 0 do return
	s := [2]f64{width, height}
	if s == h.size || h.layout.on_layout == nil || !scope_live(h.scope) do return
	h.size = s
	if h.notifying {
		h.again = true
		return
	}
	h.notifying = true
	defer h.notifying = false
	callback_enter()
	defer callback_exit()
	for _ in 0 ..< LAYOUT_MAX_PASSES {
		h.again = false
		h.layout.on_layout(h.layout.user, h.size.x, h.size.y)
		if !h.again || !scope_live(h.scope) do break
	}
}

// The child's distance from the container's outer edge, per side.
@(private)
container_frame :: proc "contextless" (h: ^Container_Handle) -> Insets {
	c := &h.container
	b := c.border_width
	return {c.margin.left + b + c.padding.left, c.margin.top + b + c.padding.top,
		c.margin.right + b + c.padding.right, c.margin.bottom + b + c.padding.bottom}
}

// Single-line text; `heading` makes it a heading (bold and a little larger), `style` overrides
// the theme's heading / body style (a loaded `Text_Style.font` replaces the system font; then
// `heading` only picks the heading size: load a bold face for bold text).
Label :: struct {
	text:    string, // copied
	heading: bool,
	style:   Text_Style,
}

Label_Handle :: struct {
	label: Label, // label.text is an owned copy, kept current by label_set_text
	root:  View,  // the NSTextField* / UILabel* / TextView / GtkLabel* / Static HWND, embedded by the app
}

label_create :: proc(l: Label) -> ^Label_Handle {
	h := scope_new_in(Label_Handle)
	h.label = l
	h.label.text = strings.clone(l.text, nv_heap())
	h.label.style = text_style_merge(l.style, l.heading ? g_theme.heading : g_theme.body)
	font_retain(h.label.style.font)
	scope_on_dispose(label_dispose, h)
	g_backend.label_init(h)
	return h
}

@(private)
label_dispose :: proc(data: rawptr) {
	h := (^Label_Handle)(data)
	delete(h.label.text, nv_heap())
	font_free(h.label.style.font)
}

@(private)
label_view :: proc(h: ^Label_Handle) -> View {
	return h.root
}

// Replaces the text; `text` is copied. The size of a flex-0 label follows on the next layout.
label_set_text :: proc(h: ^Label_Handle, text: string) {
	old := h.label.text
	h.label.text = strings.clone(text, nv_heap())
	delete(old, nv_heap())
	g_backend.label_set_text(h, text)
}

// Single-line text input. Callbacks get the current text, valid only during the call. `style` is
// as on Label.
Input :: struct {
	text:        string, // initial text
	placeholder: string,
	on_change:   proc(user: rawptr, text: string), // optional; on every edit by the user
	on_submit:   proc(user: rawptr, text: string), // optional; Return / Enter / the keyboard's Done key
	user:        rawptr,
	style:       Text_Style, // over the theme's body style
	keyboard:    Keyboard,
	secure:      bool,       // a password field: the text is masked
}

// The soft keyboard an Input asks for (iOS, Android, the web's inputmode); the desktops ignore it.
// Sentences capitalizes the first letter of each sentence.
Keyboard :: enum { Text, Sentences, Number, Signed_Number, Decimal }

Input_Handle :: struct {
	input:    Input,
	scope:    ^Scope,
	ctx:      runtime.Context,
	root:     View,   // view embedded by the app
	field:    rawptr, // NSTextField* / UITextField* / EditText / GtkEntry* / Edit HWND
	delegate: rawptr, // delegate / target / listener object, where the platform needs one
	silent:   bool,   // set during input_set_text, which never reports a change
}

input_create :: proc(i: Input) -> ^Input_Handle {
	h := scope_new_in(Input_Handle)
	h.input = i
	h.input.style = text_style_merge(i.style, g_theme.body)
	h.ctx = context
	font_retain(h.input.style.font)
	scope_on_dispose(input_dispose, h)
	g_backend.input_init(h)
	return h
}

@(private)
input_dispose :: proc(data: rawptr) {
	font_free((^Input_Handle)(data).input.style.font)
}

@(private)
input_view :: proc(h: ^Input_Handle) -> View {
	return h.root
}

// Returns a copy of the current text.
input_text :: proc(h: ^Input_Handle, allocator := context.allocator) -> string {
	return g_backend.input_text(h, allocator)
}

// Replaces the text without calling `on_change`.
input_set_text :: proc(h: ^Input_Handle, text: string) {
	h.silent = true
	g_backend.input_set_text(h, text)
	h.silent = false
}

// Gives the field the keyboard focus (and shows the soft keyboard on iOS / Android), selecting all
// of its text with `select_all`. Call it once the field is shown: after `build` returned, or after
// `dialog_show` for a field in the dialog.
input_focus :: proc(h: ^Input_Handle, select_all := false) {
	if !scope_live(h.scope) do return
	g_backend.input_focus(h, select_all)
}

// Called by the backends when the text changed or was submitted; `cb` is on_change or on_submit.
@(private)
input_notify :: proc(h: ^Input_Handle, cb: proc(user: rawptr, text: string)) {
	if h.silent || cb == nil || !scope_live(h.scope) do return
	callback_enter()
	defer callback_exit()
	cb(h.input.user, g_backend.input_text(h, context.temp_allocator))
}

// Push button with a text title. `style` is as on Label.
Button :: struct {
	title:    string, // copied
	on_click: proc(user: rawptr), // optional
	user:     rawptr,
	style:    Text_Style, // over the theme's body style; the color is ignored on Windows
}

Button_Handle :: struct {
	button:  Button, // button.title is an owned copy, kept current by button_set_title
	scope:   ^Scope,
	ctx:     runtime.Context,
	root:    View,   // view embedded by the app
	control: rawptr, // NSButton* / UIButton* / Button / GtkButton* / Button HWND
	target:  rawptr, // target / listener object, where the platform needs one
}

button_create :: proc(b: Button) -> ^Button_Handle {
	h := scope_new_in(Button_Handle)
	h.button = b
	h.button.title = strings.clone(b.title, nv_heap())
	h.button.style = text_style_merge(b.style, g_theme.body)
	h.ctx = context
	font_retain(h.button.style.font)
	scope_on_dispose(button_dispose, h)
	g_backend.button_init(h)
	return h
}

@(private)
button_dispose :: proc(data: rawptr) {
	h := (^Button_Handle)(data)
	delete(h.button.title, nv_heap())
	font_free(h.button.style.font)
}

@(private)
button_view :: proc(h: ^Button_Handle) -> View {
	return h.root
}

// Replaces the title; `title` is copied. The size of a flex-0 button follows on the next layout.
button_set_title :: proc(h: ^Button_Handle, title: string) {
	old := h.button.title
	h.button.title = strings.clone(title, nv_heap())
	delete(old, nv_heap())
	g_backend.button_set_title(h, title)
}

// Called by the backends when the button was clicked.
@(private)
button_notify :: proc(h: ^Button_Handle) {
	if h.button.on_click == nil || !scope_live(h.scope) do return
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
// natural size, so give it `flex` > 0 in a Row / Column. `on_scroll` reports the mouse wheel and
// touchpad scrolling over the canvas (a touch screen drags, which `on_pointer` reports): the
// distance in points the content should move, positive `dy` to see what is below (the content
// moves up), positive `dx` to see what is right. A wheel notch is SCROLL_LINE.
Canvas :: struct {
	on_draw:    proc(user: rawptr, p: ^Painter, width, height: f64),
	on_pointer: proc(user: rawptr, kind: Pointer, x, y: f64), // optional; Move only while pressed
	on_scroll:  proc(user: rawptr, dx, dy: f64),             // optional
	user:       rawptr,
	// Drawn on the GPU where the backend can (Linux: OpenGL through nanovg); elsewhere a plain
	// canvas. Without on_pointer / on_scroll it is not a pointer target: what is under it gets them.
	gpu:        bool,
}

// Points per wheel notch, for the backends whose wheel reports notches (GTK, Windows, a web page
// in line mode, Android's mouse).
SCROLL_LINE :: 40

Canvas_Handle :: struct {
	canvas: Canvas,
	scope:  ^Scope,
	ctx:    runtime.Context,
	root:   View,   // view embedded by the app
	view:   rawptr, // NVCanvasView* / NvCanvasView / GtkDrawingArea* / NVCanvas HWND
	fill:   rawptr, // Android: fill and stroke Paint global refs
	stroke: rawptr,
	extra:  rawptr, // per-backend draw state (Android_Canvas / Apple_Canvas / Linux_Canvas / Windows_Canvas)
}

// Drawing target, valid only during `on_draw`.
Painter :: struct {
	h:      ^Canvas_Handle,
	native: rawptr, // CGContextRef / android.graphics.Canvas / cairo_t* / GpGraphics*
	dc:     rawptr, // Windows: the HDC behind `native`
	clips:  int,    // clip_push depth; what on_draw leaves pushed is popped after it
}

canvas_create :: proc(c: Canvas) -> ^Canvas_Handle {
	h := scope_new_in(Canvas_Handle)
	h.canvas = c
	h.ctx = context
	g_backend.canvas_init(h)
	return h
}

@(private)
canvas_view :: proc(h: ^Canvas_Handle) -> View {
	return h.root
}

// Schedules a repaint; `on_draw` runs later from the event loop.
canvas_redraw :: proc(h: ^Canvas_Handle) {
	g_backend.canvas_redraw(h)
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

// An arc of the circle around (cx, cy). Angles are in degrees: 0 is 3 o'clock and they grow
// clockwise on screen, as in Flutter's drawArc; the ends are butt.
stroke_arc :: proc(p: ^Painter, cx, cy, radius, start, sweep: f64, color: Color, width: f64 = 1) {
	_stroke_arc(p, cx, cy, radius, start, sweep, color, width)
}

// One line of text in the system font, or in `style.font`; (x, y) is the top-left of its line box. `style` is over
// the theme's body style; a size of 0 is 15, a color of 0 is the palette's text color. The weight
// is left to the backend: `.Default` is regular for the system font and a loaded face's own.
draw_text :: proc(p: ^Painter, text: string, x, y: f64, style: Text_Style = {}) {
	s := text_style_merge(style, g_theme.body)
	if s.size <= 0 do s.size = 15
	if s.color.a == 0 do s.color = theme_palette().text
	_draw_text(p, text, x, y, s)
}

// The size `draw_text` gives `text` in the same style: its advance width and the height of its
// line box (from the top-left draw_text takes to the bottom of the descent), in points. Only
// inside `on_draw`, like the draw procs.
measure_text :: proc(p: ^Painter, text: string, style: Text_Style = {}) -> (width, height: f64) {
	s := text_style_merge(style, g_theme.body)
	if s.size <= 0 do s.size = 15
	return _measure_text(p, text, s)
}

// Called by the backends for the wheel / touchpad (see Canvas.on_scroll).
@(private)
canvas_scroll_notify :: proc(h: ^Canvas_Handle, dx, dy: f64) {
	if h.canvas.on_scroll == nil || (dx == 0 && dy == 0) || !scope_live(h.scope) do return
	callback_enter()
	defer callback_exit()
	h.canvas.on_scroll(h.canvas.user, dx, dy)
}

// Called by the backends on repaint; `native` / `dc` as in Painter.
@(private)
canvas_draw_notify :: proc(h: ^Canvas_Handle, native: rawptr, width, height: f64, dc: rawptr = nil) {
	if h.canvas.on_draw == nil || !scope_live(h.scope) do return // a sliding page's canvas stays as it was drawn
	callback_enter()
	defer callback_exit()
	p := Painter{h = h, native = native, dc = dc}
	h.canvas.on_draw(h.canvas.user, &p, width, height)
	for p.clips > 0 do clip_pop(&p)
}

@(private)
canvas_pointer_notify :: proc(h: ^Canvas_Handle, kind: Pointer, x, y: f64) {
	if h.canvas.on_pointer == nil || !scope_live(h.scope) do return
	callback_enter()
	defer callback_exit()
	h.canvas.on_pointer(h.canvas.user, kind, x, y)
}

// Draws `b` stretched over the rect.
draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	if b == nil do return
	_draw_image(p, b, x, y, w, h)
}

// One stroked path through `points`: round joins, butt ends. Fewer than two points draw nothing.
stroke_polyline :: proc(p: ^Painter, points: [][2]f64, color: Color, width: f64 = 1) {
	if len(points) < 2 do return
	if g_draw_mock != nil {
		g_draw_mock("stroke_polyline %d %v", len(points), width)
		return
	}
	_stroke_polyline(p, points, color, width)
}

// Clips what is drawn next to the rect, inside any clip already pushed, until the matching
// clip_pop; what on_draw leaves pushed is popped after it.
clip_push :: proc(p: ^Painter, x, y, w, h: f64) {
	p.clips += 1
	if g_draw_mock != nil {
		g_draw_mock("clip_push %v %v %v %v", x, y, w, h)
		return
	}
	_clip_push(p, x, y, w, h)
}

// Ends the innermost clip_push; without one it does nothing.
clip_pop :: proc(p: ^Painter) {
	if p.clips <= 0 do return
	p.clips -= 1
	if g_draw_mock != nil {
		g_draw_mock("clip_pop")
		return
	}
	_clip_pop(p)
}

// The tests' draw log (mock_test.odin); nil in an app, where the draw procs go to the backend.
@(private) g_draw_mock: proc(format: string, args: ..any)

// A decoded image in memory, drawn by Image widgets and `draw_image`. Reference counted:
// `bitmap_free` drops the caller's reference, and a widget showing the bitmap holds its own, so
// the app can free a bitmap right after handing it to a widget.
Bitmap :: struct {
	native: rawptr, // CGImageRef / android.graphics.Bitmap global ref / cairo_surface_t* / GpBitmap*
	extra:  rawptr, // Windows: the IStream GDI+ decodes from lazily
	width:  int,    // px
	height: int,
	refs:   int,
	rgba:   bool,   // made from pixels (bitmap_from_rgba): bitmap_set_rgba can replace them
}

// Decodes PNG or JPEG bytes with the platform's decoder; nil if they are not an image. `data` is
// not kept.
bitmap_from_bytes :: proc(data: []u8) -> ^Bitmap {
	if len(data) == 0 do return nil
	b := new(Bitmap)
	b.refs = 1
	if !g_backend.bitmap_decode(b, data) {
		free(b)
		return nil
	}
	return b
}

// Loads an image file. A relative path names one of the app's assets: `app/assets/`, which the
// build scripts copy next to the executable (desktop), into the app bundle (iOS) or into the APK.
bitmap_from_file :: proc(path: string) -> ^Bitmap {
	return bitmap_from_bytes(g_backend.asset_read(path, context.temp_allocator))
}

// A bitmap of `width` × `height` pixels: RGBA8 with straight alpha, rows top-down, `width * 4`
// bytes each. nil for an empty size or too few bytes. The pixels are copied, not kept.
bitmap_from_rgba :: proc(width, height: int, pixels: []u8) -> ^Bitmap {
	if width <= 0 || height <= 0 || len(pixels) < width * height * 4 do return nil
	b := new(Bitmap)
	b^ = {width = width, height = height, refs = 1, rgba = true}
	if !g_backend.bitmap_rgba(b, pixels[:width * height * 4]) {
		free(b)
		return nil
	}
	return b
}

// Replaces the pixels of a bitmap from bitmap_from_rgba, in place, with as many (same layout,
// copied). False for a decoded bitmap or another size: make a new one then. Canvases draw the new
// pixels on their next draw (canvas_redraw); an Image widget needs image_set_bitmap again.
bitmap_set_rgba :: proc(b: ^Bitmap, pixels: []u8) -> bool {
	if b == nil || !b.rgba || len(pixels) != b.width * b.height * 4 do return false
	return g_backend.bitmap_set_rgba(b, pixels)
}

// Reads one of the app's assets whole (a relative path, as for bitmap_from_file) or a file by its
// absolute path where there is a file system; false when there is none (an empty file may read as
// none too).
asset_read :: proc(path: string, allocator := context.allocator) -> ([]u8, bool) {
	data := g_backend.asset_read(path, allocator)
	return data, data != nil
}

// Downloads and decodes an image in the background. `on_load` runs later on the UI thread with
// the bitmap, which the caller then owns, or nil if the download or the decode failed.
bitmap_fetch :: proc(url: string, on_load: proc(user: rawptr, b: ^Bitmap), user: rawptr) {
	f := new(Fetch, nv_heap())
	f^ = {url = strings.clone(url, nv_heap()), on_load = on_load, user = user, ctx = context}
	g_backend.fetch_start(f)
}

bitmap_free :: proc(b: ^Bitmap) {
	if b == nil do return
	b.refs -= 1
	if b.refs > 0 do return
	g_backend.bitmap_free(b)
	free(b)
}

@(private)
bitmap_retain :: proc(b: ^Bitmap) -> ^Bitmap {
	if b != nil do b.refs += 1
	return b
}

// A loaded font face, for `Text_Style.font` (widgets, the theme and `draw_text`). Reference counted like
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
	if !g_backend.font_load(f, data) {
		delete(f.family)
		free(f)
		return nil
	}
	return f
}

// Loads a font file; a relative path names an asset, as for bitmap_from_file.
font_from_file :: proc(path: string) -> ^Font {
	return font_from_bytes(g_backend.asset_read(path, context.temp_allocator))
}

font_free :: proc(f: ^Font) {
	if f == nil do return
	f.refs -= 1
	if f.refs > 0 do return
	g_backend.font_free(f)
	delete(f.family)
	free(f)
}

@(private)
font_retain :: proc(f: ^Font) -> ^Font {
	if f != nil do f.refs += 1
	return f
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
	delete(f.data, nv_heap())
	delete(f.url, nv_heap())
	free(f, nv_heap())
	if on_load != nil {
		on_load(user, b)
	} else {
		bitmap_free(b)
	}
}

// How a file dialog ended.
File_Status :: enum { Ok, Cancelled, Failed }

// Asks the user for one file and reads it whole. `on_done` runs later on the main thread, never
// inside file_open; `name` (without a directory) and `data` are valid only during the call. One file
// dialog at a time: a new one cancels the one still open (its on_done gets .Cancelled first). It
// belongs to the top page: if that page pops first, on_done gets .Cancelled before its on_pop. On
// the web, call it from a tap (browsers open the picker only on a user gesture). Not from `build`.
File_Open :: struct {
	title:      string,   // the dialog's message, where the platform shows one
	extensions: []string, // without the dot ("json"); empty for any file
	on_done:    proc(user: rawptr, status: File_Status, name: string, data: []u8),
	user:       rawptr,
}

// Asks where to save `data` (copied) and writes it there; `name` in on_done is the file's name as
// chosen. On the web it is a download: .Ok at once with `suggested_name`.
File_Save :: struct {
	title:          string,
	suggested_name: string,
	extensions:     []string, // the first is the default
	data:           []u8,
	on_done:        proc(user: rawptr, status: File_Status, name: string), // optional
	user:           rawptr,
}

file_open :: proc(o: File_Open) {
	r := file_request_new(false, o.title, "", o.extensions, nil)
	r.on_open, r.user = o.on_done, o.user
	g_backend.file_open(r)
}

file_save :: proc(s: File_Save) {
	r := file_request_new(true, s.title, s.suggested_name, s.extensions, s.data)
	r.on_save, r.user = s.on_done, s.user
	g_backend.file_save(r)
}

// A file dialog in flight, in nv_heap. The backend reports it exactly once through file_notify,
// however it ends; a detached one (replaced, or its page popped) calls nothing then.
@(private) File_Request :: struct {
	save:       bool,
	title:      string,
	name:       string,   // save: the suggestion in; both: the chosen name out (file_set_result)
	extensions: []string,
	data:       []u8,     // save: the bytes to write; open: the bytes read
	on_open:    proc(user: rawptr, status: File_Status, name: string, data: []u8),
	on_save:    proc(user: rawptr, status: File_Status, name: string),
	user:       rawptr,
	page:       ^Page_Handle, // nil once detached
	ctx:        runtime.Context,
	native:     rawptr, // backend: the panel / picker / chooser
	extra:      rawptr, // backend
}

@(private) g_file_request: ^File_Request // the attached one

@(private)
file_request_new :: proc(save: bool, title, name: string, extensions: []string, data: []u8) -> ^File_Request {
	assert(len(g_nav) > 0 && g_nav_building == 0, "nv.file_open / file_save: after run, not inside build")
	file_detach(g_file_request)
	r := new(File_Request, nv_heap())
	r.save, r.ctx, r.page = save, context, g_nav[len(g_nav) - 1]
	r.title = strings.clone(title, nv_heap())
	r.name = strings.clone(name, nv_heap())
	r.extensions = make([]string, len(extensions), nv_heap())
	for e, i in extensions do r.extensions[i] = strings.clone(e, nv_heap())
	r.data = slice.clone(data, nv_heap())
	g_file_request = r
	return r
}

// The chosen file's name (copied; a path keeps only its last part) and, for an open, its bytes
// (taken: allocated with nv_heap).
@(private)
file_set_result :: proc(r: ^File_Request, name: string, data: []u8 = nil) {
	base := name
	if i := strings.last_index_any(base, "/\\"); i >= 0 do base = base[i + 1:]
	delete(r.name, nv_heap())
	r.name = strings.clone(base, nv_heap())
	if !r.save {
		delete(r.data, nv_heap())
		r.data = data
	}
}

// Called by the backends once per request, however it ended; frees it.
@(private)
file_notify :: proc(r: ^File_Request, status: File_Status) {
	if r.page != nil {
		if g_file_request == r do g_file_request = nil
		r.page = nil
		callback_enter()
		defer callback_exit()
		file_report(r, status)
	}
	file_request_free(r)
}

// The app hears .Cancelled now; the backend's answer, when it comes, is dropped.
@(private)
file_detach :: proc(r: ^File_Request) {
	if r == nil || r.page == nil do return
	if g_file_request == r do g_file_request = nil
	r.page = nil
	callback_enter()
	defer callback_exit()
	file_report(r, .Cancelled)
}

@(private)
file_detach_page :: proc(e: ^Page_Handle) {
	if g_file_request != nil && g_file_request.page == e do file_detach(g_file_request)
}

@(private)
file_report :: proc(r: ^File_Request, status: File_Status) {
	if r.save {
		if r.on_save != nil do r.on_save(r.user, status, status == .Ok ? r.name : "")
	} else if r.on_open != nil {
		r.on_open(r.user, status, status == .Ok ? r.name : "", status == .Ok ? r.data : nil)
	}
}

@(private)
file_request_free :: proc(r: ^File_Request) {
	delete(r.title, nv_heap())
	delete(r.name, nv_heap())
	for e in r.extensions do delete(e, nv_heap())
	delete(r.extensions, nv_heap())
	delete(r.data, nv_heap())
	free(r, nv_heap())
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
	fetch:  ^Image_Fetch, // the download of `url` in flight; the handle's death detaches it
}

image_create :: proc(i: Image) -> ^Image_Handle {
	h := scope_new_in(Image_Handle)
	h.image = i
	h.image.bitmap, h.image.url = nil, ""
	h.ctx = context
	h.bitmap = bitmap_retain(i.bitmap)
	scope_on_dispose(image_dispose, h)
	g_backend.image_init(h)
	if i.bitmap == nil && i.url != "" {
		// On the heap: the download can land after the page and its scope are gone.
		t := new(Image_Fetch, nv_heap())
		t^ = {h, h.seq}
		h.fetch = t
		bitmap_fetch(i.url, image_fetched, t)
	}
	return h
}

@(private)
image_dispose :: proc(data: rawptr) {
	h := (^Image_Handle)(data)
	if h.fetch != nil do h.fetch.h = nil // the download lands on nothing
	bitmap_free(h.bitmap)
}

@(private)
image_view :: proc(h: ^Image_Handle) -> View {
	return h.root
}

// Shows `b` (nil for nothing) instead of the current bitmap, or of the one still downloading.
image_set_bitmap :: proc(h: ^Image_Handle, b: ^Bitmap) {
	h.seq += 1
	old := h.bitmap
	h.bitmap = bitmap_retain(b)
	g_backend.image_set_bitmap(h)
	bitmap_free(old)
}

@(private) Image_Fetch :: struct {
	h:   ^Image_Handle, // nil once the handle's scope died
	seq: int,
}

@(private)
image_fetched :: proc(user: rawptr, b: ^Bitmap) {
	t := (^Image_Fetch)(user)
	defer free(t, nv_heap())
	if t.h != nil {
		t.h.fetch = nil
		if t.h.seq == t.seq && b != nil do image_set_bitmap(t.h, b)
	}
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

// Flutter's CircularProgressIndicator: a Material arc, drawn by the core on a canvas inside a
// fixed-size Container rather than a platform spinner (only AppKit has a determinate one, Win32
// none). Indeterminate, it animates by asking for the next frame from inside its own on_draw (the
// Bench's loop), so it costs nothing while its page is hidden or popped. A Row / Column stretches
// the cross axis; the circle stays `size` and centered. Default colors follow a light / dark flip.
Progress :: struct {
	value:       Maybe(f64), // nil = indeterminate; else 0..1 (clamped)
	color:       Color,      // alpha 0 = the palette's accent
	track_color: Color,      // the full circle under the arc; alpha 0 = none
	stroke:      f64,        // points / dp; 4 when 0
	size:        f64,        // the diameter including the stroke; 36 when 0
}

Progress_Handle :: struct {
	progress:   Progress,
	root:       View, // the container's root; embedded by the app
	container:  ^Container_Handle,
	canvas:     ^Canvas_Handle,
	start:      time.Tick, // origin of the indeterminate motion
	prev, next: ^Progress_Handle, // g_progress
}

// Every live progress, so theme_notify can repaint them (their default color is the palette's).
// Linked through the handles, which live in their scopes' arenas; progress_dispose unlinks.
@(private) g_progress: ^Progress_Handle

progress_create :: proc(p: Progress) -> ^Progress_Handle {
	h := scope_new_in(Progress_Handle)
	h.progress = p
	if h.progress.stroke <= 0 do h.progress.stroke = 4
	if h.progress.size <= 0 do h.progress.size = 36
	h.start = time.tick_now()
	h.canvas = canvas_create({on_draw = progress_draw, user = h})
	size := h.progress.size
	h.container = container_create({child = view(h.canvas), width = size, height = size})
	h.root = view(h.container)
	h.next = g_progress
	if g_progress != nil do g_progress.prev = h
	g_progress = h
	scope_on_dispose(progress_dispose, h)
	return h
}

@(private)
progress_dispose :: proc(data: rawptr) {
	h := (^Progress_Handle)(data)
	if h.prev != nil do h.prev.next = h.next
	else do g_progress = h.next
	if h.next != nil do h.next.prev = h.prev
}

@(private)
progress_view :: proc(h: ^Progress_Handle) -> View {
	return h.root
}

// nil switches to indeterminate (the motion continues where it was), a number to determinate.
progress_set_value :: proc(h: ^Progress_Handle, value: Maybe(f64)) {
	h.progress.value = value
	canvas_redraw(h.canvas)
}

@(private)
progress_draw :: proc(user: rawptr, p: ^Painter, w, h: f64) {
	ph := (^Progress_Handle)(user)
	pr := ph.progress
	r := (min(w, h, pr.size) - pr.stroke) / 2
	if r <= 0 do return
	cx, cy := w / 2, h / 2
	if pr.track_color.a > 0 do stroke_arc(p, cx, cy, r, 0, 360, pr.track_color, pr.stroke)
	color := pr.color.a > 0 ? pr.color : theme_palette().accent
	start, sweep: f64
	if v, ok := pr.value.?; ok {
		start, sweep = -90, clamp(v, 0, 1) * 360
	} else {
		start, sweep = progress_arc(time.duration_milliseconds(time.tick_since(ph.start)))
		canvas_redraw(ph.canvas) // the next frame
	}
	if sweep > 0 do stroke_arc(p, cx, cy, r, start, sweep, color, pr.stroke)
}

// Flutter's indeterminate motion (_CircularProgressIndicatorPainter) at `ms`, in degrees: within
// each 1333 ms cycle the head runs ahead over the first half and the tail catches up over the
// second, both on the fast-out-slow-in curve, while the whole arc turns once per 2222 ms and
// creeps 90° per cycle.
@(private)
progress_arc :: proc "contextless" (ms: f64) -> (start, sweep: f64) {
	cycle := ms / 1333
	cycle -= f64(i64(cycle))
	turn := ms / 2222
	turn -= f64(i64(turn))
	head := fast_out_slow_in(clamp(cycle * 2, 0, 1))
	tail := fast_out_slow_in(clamp(cycle * 2 - 1, 0, 1))
	start = -90 + tail * 270 + turn * 360 + cycle * 90
	sweep = max((head - tail) * 270, 0.06)
	return
}

// Material's standard curve, cubic-bezier(0.4, 0, 0.2, 1): solve x(s) = t by bisection (x is
// monotonic), then return y(s).
@(private)
fast_out_slow_in :: proc "contextless" (t: f64) -> f64 {
	bezier :: proc "contextless" (a, b, s: f64) -> f64 {
		u := 1 - s
		return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
	}
	lo, hi := 0.0, 1.0
	for _ in 0..<30 {
		mid := (lo + hi) / 2
		if bezier(0.4, 0.2, mid) < t do lo = mid
		else do hi = mid
	}
	return bezier(0, 1, (lo + hi) / 2)
}

// A card over the current page, inside the window (not a separate OS window). A modal dialog dims
// the page and blocks it; a non-modal one floats over a page that stays usable. `content` is any
// view the app built from the widgets; it keeps its natural size (a bare list or canvas has none).
// `content` belongs to the page (its widgets live until the page pops); `build` instead makes the
// content when the dialog shows, in the dialog's own scope, so its widgets go when it closes.
// The buttons sit in a row under the content and never close the dialog on their own: a callback
// gets the handle and calls `dialog_close` when it wants to; a `dismissible` modal one also closes
// on a tap on the scrim. The dialog belongs to the page on top when it is shown: it hides under a
// page pushed later and closes when its page pops.
Dialog :: struct {
	title:    string,              // copied; "" for none
	content:  View,                // optional
	buttons:  []Dialog_Button,     // copied
	modal:    bool,
	on_close: proc(user: rawptr),  // optional; after the dialog is gone (the last call the handle is valid for)
	user:     rawptr,
	build:    proc(user: rawptr, h: ^Dialog_Handle) -> View, // optional; replaces `content`
	width:    f64,                 // the card's width in points / dp; 0 = 320; at most the window's less 32
	radius:   f64,                 // the card's corner radius; 0 = the platform's
	light:    bool,                // a white card in the light appearance (its controls too), whatever the theme
	scrim:    Color,               // modal: the dimming layer; alpha 0 = black at 40%
	dismissible: bool,             // modal: a tap on the scrim closes it (dialog_close; Flutter's barrierDismissible)
}

@(private) DIALOG_WIDTH :: 320.0
@(private) DIALOG_SCRIM :: Color{0, 0, 0, 0.4}
@(private) DIALOG_LIGHT :: Color{1, 1, 1, 1} // the light card
@(private) DIALOG_LIGHT_TEXT :: Color{0, 0, 0, 1}

// The card's width before the window clamps it.
@(private)
dialog_width :: proc "contextless" (h: ^Dialog_Handle) -> f64 {
	return h.dialog.width > 0 ? h.dialog.width : DIALOG_WIDTH
}

@(private)
dialog_radius :: proc "contextless" (h: ^Dialog_Handle, platform: f64) -> f64 {
	return h.dialog.radius > 0 ? h.dialog.radius : platform
}

@(private)
dialog_scrim :: proc "contextless" (h: ^Dialog_Handle) -> Color {
	return h.dialog.scrim.a > 0 ? h.dialog.scrim : DIALOG_SCRIM
}

Dialog_Button :: struct {
	title:    string, // copied
	on_click: proc(user: rawptr, dialog: ^Dialog_Handle), // optional
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
	scope:   ^Scope,               // the body's widgets; handed to the backend by _dialog_close
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

// Removes the dialog, calls `on_close` and frees the handle. The title and the buttons live in the
// dialog's own scope, which the backend retires once the card is gone.
dialog_close :: proc(h: ^Dialog_Handle) {
	if i, found := slice.linear_search(g_dialogs_pending[:], h); found {
		ordered_remove(&g_dialogs_pending, i) // never shown: nothing to take down
	} else {
		j, shown := slice.linear_search(g_dialogs[:], h)
		if !shown do return
		ordered_remove(&g_dialogs, j) // before _dialog_close: the backend reads dialog_top_modal for the state after
		if h.scope != nil do h.scope.detached = true // its buttons call the app no more (on_close frees)
		g_backend.dialog_close(h) // retires h.scope now or later
		h.card, h.scrim, h.body, h.scope = nil, nil, nil, nil
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
// These belong to the dialog's scope, as does what `build` makes; the app's `content` stays in the
// page's.
@(private)
dialog_present :: proc(h: ^Dialog_Handle) {
	h.scope = scope_new()
	outer := g_scope_override
	g_scope_override = h.scope
	defer g_scope_override = outer
	content := h.dialog.content
	if h.dialog.build != nil do content = h.dialog.build(h.dialog.user, h)
	children := make([dynamic]Flex_Child, context.temp_allocator)
	if h.dialog.title != "" {
		style: Text_Style
		if h.dialog.light do style.color = DIALOG_LIGHT_TEXT
		h.title = label_create({text = h.dialog.title, heading = true, style = style})
		append(&children, Flex_Child{view(h.title), 0})
	}
	if content != nil do append(&children, Flex_Child{content, 0})
	if len(h.buttons) > 0 {
		row := make([]Flex_Child, len(h.buttons), context.temp_allocator)
		for bh, i in h.buttons {
			bh.handle = button_create({title = bh.button.title, on_click = dialog_button_clicked, user = bh})
			row[i] = {view(bh.handle), 1}
		}
		append(&children, Flex_Child{row_create(row, spacing = 8), 0})
	}
	h.body = column_create(children[:], spacing = 12)
	append(&g_dialogs, h)
	g_backend.dialog_show(h)
}

// The body buttons' on_click. The app's callback may close the dialog, which frees `bh`.
@(private)
dialog_button_clicked :: proc(user: rawptr) {
	bh := (^Dialog_Button_Handle)(user)
	if bh.button.on_click != nil do bh.button.on_click(bh.button.user, bh.dialog)
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

// Called by the backends when a modal dialog's scrim (`h.scrim`) was tapped: a dismissible dialog
// closes. It finds the dialog by its scrim, so a late tap on a closed one does nothing.
@(private)
dialog_scrim_notify :: proc "contextless" (scrim: rawptr) {
	if scrim == nil do return
	for d in g_dialogs {
		if d.scrim != scrim do continue
		if !d.dialog.dismissible || d.hidden do return
		context = d.ctx
		callback_enter()
		defer callback_exit()
		dialog_close(d)
		return
	}
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
		g_backend.dialog_set_hidden(d, hidden)
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

// Light or dark appearance; System follows the OS setting, live.
Mode :: enum { System, Light, Dark }

// Default is the widget's own weight (bold for headings and list titles, regular otherwise).
Weight :: enum { Default, Regular, Medium, Semibold, Bold }

// A font (the system family, or a loaded `Font`) and a text color. Zero fields inherit: a widget's
// style falls back to the theme's style for its role, and whatever is still zero is the platform's
// default (its font size for that widget, the weight above, the adaptive label color). A loaded
// font is one face: a `weight` or `italic` over it is best effort (Android derives a Typeface,
// Linux and Windows pick among the family's installed faces or synthesize, Apple keeps the face).
Text_Style :: struct {
	size:   f64, // points / dp (sp on Android)
	weight: Weight,
	italic: bool,
	color:  Color, // alpha 0 = the platform's text color, which follows light / dark
	font:   ^Font, // nil = the system font; the widget keeps its own reference
}

// The app-wide look, set once before `run`. The mode can change later (`theme_set_mode`), and
// with System it follows the OS; `on_change` runs whenever the resolved light / dark flips, so
// the app can redraw its canvases with the new palette. The text styles and the accent apply to
// widgets created afterwards.
Theme :: struct {
	mode:      Mode,
	accent:    Color,      // alpha 0 = the platform's accent: buttons, the caret, list selection, the bar
	body:      Text_Style, // labels, inputs, buttons and canvas text
	heading:   Text_Style, // heading labels and dialog titles
	bar_title: Text_Style, // the page title in the bar on iOS and Android (centred); zero: `heading`
	on_change: proc(user: rawptr), // optional
	user:      rawptr,
}

// The theme's colors for custom drawing, for the current light / dark.
Palette :: struct {
	background:     Color, // the page
	surface:        Color, // cards, canvases
	text:           Color,
	secondary_text: Color,
	separator:      Color,
	accent:         Color,
}

PALETTE_LIGHT :: Palette{
	background     = {1, 1, 1, 1},
	surface        = {0.96, 0.96, 0.98, 1},
	text           = {0.1, 0.1, 0.12, 1},
	secondary_text = {0.45, 0.45, 0.5, 1},
	separator      = {0.8, 0.8, 0.83, 1},
	accent         = {0, 0.48, 1, 1},
}

PALETTE_DARK :: Palette{
	background     = {0.11, 0.11, 0.12, 1},
	surface        = {0.17, 0.17, 0.19, 1},
	text           = {0.95, 0.95, 0.97, 1},
	secondary_text = {0.6, 0.6, 0.65, 1},
	separator      = {0.3, 0.3, 0.33, 1},
	accent         = {0.04, 0.52, 1, 1},
}

// Backends implement _theme_system_dark (the OS setting), _theme_system_accent (alpha 0 if the
// platform has none), _theme_apply_mode (make the native UI force or follow g_theme.mode) and
// _theme_recolor (repaint what the platform doesn't adapt by itself after g_dark changed). Each
// calls theme_start once the platform is up and before the root page is built, and theme_notify
// when the OS appearance changed.
@(private) g_theme:      Theme
@(private) g_dark:       bool // resolved
@(private) g_theme_live: bool // theme_start ran

theme_set :: proc(t: Theme) {
	assert(len(g_nav) == 0, "nv.theme_set after nv.run")
	g_theme = t
}

theme_set_mode :: proc(m: Mode) {
	g_theme.mode = m
	if !g_theme_live do return
	g_backend.theme_apply_mode()
	theme_notify()
}

theme_mode :: proc() -> Mode {
	return g_theme.mode
}

// The bar's title style: the theme's `bar_title`, else its `heading`.
@(private)
theme_bar_title :: proc "contextless" () -> Text_Style {
	return g_theme.bar_title != {} ? g_theme.bar_title : g_theme.heading
}

// The resolved appearance: true for dark.
theme_dark :: proc() -> bool {
	return g_theme_live ? g_dark : theme_resolve_dark()
}

theme_palette :: proc() -> Palette {
	p := theme_dark() ? PALETTE_DARK : PALETTE_LIGHT
	if g_theme.accent.a > 0 {
		p.accent = g_theme.accent
	} else if a := g_backend.theme_system_accent(); a.a > 0 {
		p.accent = a
	}
	return p
}

@(private)
theme_resolve_dark :: proc() -> bool {
	switch g_theme.mode {
	case .Light: return false
	case .Dark:  return true
	case .System: return g_backend.theme_system_dark()
	}
	return false
}

@(private)
theme_start :: proc() {
	g_backend.theme_apply_mode()
	g_dark = theme_resolve_dark()
	g_theme_live = true
}

// The OS appearance or the mode changed: recolors and tells the app if light / dark flipped.
@(private)
theme_notify :: proc() {
	if !g_theme_live do return
	dark := theme_resolve_dark()
	if dark == g_dark do return
	g_dark = dark
	g_backend.theme_recolor()
	for p := g_progress; p != nil; p = p.next do canvas_redraw(p.canvas)
	scaffold_recolor()
	if g_theme.on_change != nil {
		callback_enter()
		defer callback_exit()
		g_theme.on_change(g_theme.user)
	}
}

// `s` over `base`, field by field.
@(private)
text_style_merge :: proc "contextless" (s, base: Text_Style) -> Text_Style {
	out := s
	if out.size <= 0 do out.size = base.size
	if out.weight == .Default do out.weight = base.weight
	out.italic ||= base.italic
	if out.color.a == 0 do out.color = base.color
	if out.font == nil do out.font = base.font
	return out
}

// The weight to use, `bold` being the widget's default.
@(private)
text_weight :: proc "contextless" (w: Weight, bold: bool) -> Weight {
	if w != .Default do return w
	return bold ? .Bold : .Regular
}
