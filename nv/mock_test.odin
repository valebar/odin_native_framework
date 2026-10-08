#+build-project-name nv
package nv

// The mock backend and the fixture of the core's tests (`odin run tools/nvbuild -- test`). The
// `#+build-project-name nv` tag keeps the *_test.odin files in `odin check nv` and `odin test nv`
// and out of every app build (whose project is `app`), so no app links core:testing.
//
// The mock logs every backend call that does something ("nav_push Home", "label_set_text hi",
// "bitmap_decode refused", ..; expect_log compares); the pure queries (input_text and the theme's
// system dark / accent) only answer. It makes fake views: a Mock_View in the current scope that a
// disposer releases, the way a backend's own reference is (objc_own, android_own_ref), so
// mock.views counts the views whose scope is still alive. It checks the state each call expects
// from the core and answers from settable fields. `retire` picks when a popped page's or a closed
// dialog's scope is retired: inside _nav_release / _dialog_close (.Now: macOS, Android, iOS
// dialogs and back / swipe pops, GTK pages with no slide running) or at mock_retire_parked (.Later:
// GTK pages after a slide and GTK dialogs from an idle, Windows after DestroyWindow, iOS pages
// popped by pop()).
//
// A test plays the platform: what a native callback runs sits between callback_enter and
// callback_exit (or goes through button_notify, action_notify, nav_back_notify), and its temp
// memory dies at the outermost callback_exit, as the app's does. The core is package globals, so
// the tests run on one thread. What the core allocates with context.allocator (page, action and
// dialog handles, titles, bitmaps, fonts, the stacks' backing arrays) goes through the runner's
// per-test tracking allocator, which fails a test that leaks it (ODIN_TEST_FAIL_ON_BAD_MEMORY).
// The heap (label texts, button titles, Scope, Fetch) and the scopes' arenas are not tracked:
// mock.views catches a scope that never died.

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:slice"
import "core:strings"
import "core:testing"

when ODIN_TEST {
	#assert(#config(ODIN_TEST_THREADS, 0) == 1, "nv's tests share the core's globals: run them with -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true (nvbuild test does)")
	#assert(#config(ODIN_TEST_FAIL_ON_BAD_MEMORY, false), "nv's tests check for leaks: run them with -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true (nvbuild test does)")
}

Mock_Retire :: enum { Now, Later }

mock: struct {
	t:                 ^testing.T,
	arena:             virtual.Arena,   // the log and the views' texts: outlive every scope
	log:               [dynamic]string,
	views:             int,             // Mock_Views whose scope is alive
	retire:            Mock_Retire,
	parked:            [dynamic]^Scope, // .Later: until mock_retire_parked
	fetches:           [dynamic]^Fetch, // in fetch_start order, nil once finished
	nav_pop_ok:        bool,            // false: the platform refuses (UIKit mid-transition)
	decode_ok:         bool,
	font_ok:           bool,
	asset:             []u8,            // what _asset_read returns, whatever the path
	system_dark:       bool,
	system_accent:     Color,
	modal_after_close: ^Dialog_Handle,  // dialog_top_modal() as _dialog_close saw it
	timers:            [dynamic]^Timer, // in post_delayed order, until mock_fire_timers
}

mock_backend := Backend{
	run                 = mock_run,
	nav_push            = mock_nav_push,
	nav_pop             = mock_nav_pop,
	nav_release         = mock_nav_release,
	nav_title_changed   = mock_nav_title_changed,
	nav_actions_changed = mock_nav_actions_changed,
	list_init           = mock_list_init,
	list_reload         = mock_list_reload,
	flex_create         = mock_flex_create,
	container_init      = mock_container_init,
	container_set_color = mock_container_set_color,
	label_init          = mock_label_init,
	label_set_text      = mock_label_set_text,
	input_init          = mock_input_init,
	input_text          = mock_input_text,
	input_set_text      = mock_input_set_text,
	button_init         = mock_button_init,
	button_set_title    = mock_button_set_title,
	canvas_init         = mock_canvas_init,
	canvas_redraw       = mock_canvas_redraw,
	image_init          = mock_image_init,
	image_set_bitmap    = mock_image_set_bitmap,
	bitmap_decode       = mock_bitmap_decode,
	bitmap_free         = mock_bitmap_free,
	font_load           = mock_font_load,
	font_free           = mock_font_free,
	asset_read          = mock_asset_read,
	fetch_start         = mock_fetch_start,
	dialog_show         = mock_dialog_show,
	dialog_close        = mock_dialog_close,
	dialog_set_hidden   = mock_dialog_set_hidden,
	view_set_hidden     = mock_view_set_hidden,
	view_set_enabled    = mock_view_set_enabled,
	overlay_init        = mock_overlay_init,
	overlay_add         = mock_overlay_add,
	overlay_place       = mock_overlay_place,
	overlay_scrim_init  = mock_overlay_scrim_init,
	fab_init            = mock_fab_init,
	tabbar_init         = mock_tabbar_init,
	tabbar_select       = mock_tabbar_select,
	post_delayed        = mock_post_delayed,
	theme_system_dark   = mock_theme_system_dark,
	theme_system_accent = mock_theme_system_accent,
	theme_apply_mode    = mock_theme_apply_mode,
	theme_recolor       = mock_theme_recolor,
}

// A test that forgets mock_begin still never reaches the platform.
@(init)
mock_install :: proc "contextless" () {
	g_backend = mock_backend
}

// Starts a test on a clean core: every global back to zero (a test that crashed left them dirty,
// and its memory went with the runner's), and the mock installed with its default answers.
mock_begin :: proc(t: ^testing.T) {
	g_nav, g_nav_pending, g_dialogs, g_dialogs_pending = {}, {}, {}, {}
	g_nav_building, g_callback_depth = 0, 0
	g_scope_override, g_scopes_retired = nil, {}
	g_progress, g_scaffolds = nil, nil
	g_theme, g_dark, g_theme_live = {}, false, false
	g_backend = mock_backend
	mock = {t = t, nav_pop_ok = true, decode_ok = true, font_ok = true}
	if virtual.arena_init_growing(&mock.arena) != nil do testing.fail_now(t, "no arena for the mock")
	mock.log = make([dynamic]string, mock_allocator())
	mock.parked = make([dynamic]^Scope, mock_allocator())
	mock.fetches = make([dynamic]^Fetch, mock_allocator())
	mock.timers = make([dynamic]^Timer, mock_allocator())
}

// Ends a test, then fails on what it left. What is still up is torn down the way Android's relaunch
// reset does in jni_on_create (on_pop for every pushed page, on_close for every dialog), then the
// root is freed without its on_pop, so every scope dies; downloads in flight fail. A real app exit
// runs none of this. Then no view and no open callback bracket may be left. Nothing may still be pending: every outermost build is followed by a flush, so a
// page or dialog left queued is a core bug (it is still torn down, so the report stays short).
// The stacks' backing arrays are freed, since they hold this test's allocator.
mock_end :: proc(t: ^testing.T, loc := #caller_location) {
	testing.expect(t, g_callback_depth == 0 && g_nav_building == 0 && g_scope_override == nil, "a callback bracket was left open", loc = loc)
	testing.expectf(t, len(g_nav_pending) == 0 && len(g_dialogs_pending) == 0, "%d pages and %d dialogs were left pending",
		len(g_nav_pending), len(g_dialogs_pending), loc = loc)
	callback_enter()
	for len(g_nav) > 1 do nav_system_pop()
	if len(g_nav) == 1 {
		root := g_nav[0]
		dialog_close_page(root)
		scope_retire(root.scope)
		nav_detach_scaffold(root)
		nav_actions_free(root)
		delete(root.page.title)
		free(root)
	}
	for h in g_nav_pending {
		scope_retire(h.scope)
		nav_actions_free(h)
		delete(h.page.title)
		free(h)
	}
	for len(g_dialogs_pending) > 0 do dialog_close(g_dialogs_pending[0])
	callback_exit()
	mock_retire_parked()
	for f, i in mock.fetches do if f != nil do mock_fetch_finish(i, nil)
	mock_fire_timers() // the cancelled ones only free themselves
	delete(g_nav)
	delete(g_nav_pending)
	delete(g_dialogs)
	delete(g_dialogs_pending)
	delete(g_scopes_retired)
	g_nav, g_nav_pending, g_dialogs, g_dialogs_pending, g_scopes_retired = {}, {}, {}, {}, {}
	testing.expectf(t, g_progress == nil, "a progress outlived its scope", loc = loc)
	testing.expectf(t, g_scaffolds == nil, "a scaffold outlived its scope", loc = loc)
	testing.expectf(t, mock.views == 0, "%d views outlived their page or dialog", mock.views, loc = loc)
	virtual.arena_destroy(&mock.arena)
}

mock_allocator :: proc() -> runtime.Allocator {
	return virtual.arena_allocator(&mock.arena)
}

mock_log :: proc(format: string, args: ..any) {
	append(&mock.log, fmt.aprintf(format, ..args, allocator = mock_allocator()))
}

mock_log_clear :: proc() {
	clear(&mock.log)
}

// Fails unless the calls logged since the last check are exactly `want`, in order; starts a new log.
expect_log :: proc(t: ^testing.T, want: ..string, loc := #caller_location) {
	if !slice.equal(mock.log[:], want) {
		testing.expectf(t, false, "calls:\n\t%s\nwant:\n\t%s", strings.join(mock.log[:], "\n\t", context.temp_allocator),
			strings.join(want, "\n\t", context.temp_allocator), loc = loc)
	}
	clear(&mock.log)
}

// A precondition the core owes the backend; a broken one fails the running test.
mock_require :: proc(ok: bool, what: string, loc := #caller_location) {
	testing.expect(mock.t, ok, what, loc = loc)
}

// A fake native view in the current scope, released by a disposer like a backend's reference.
Mock_View :: struct {
	kind:   string,
	text:   string, // what the widget shows (mock arena)
	hidden: bool,
}

mock_view :: proc(kind: string, text := "") -> View {
	v := scope_new_in(Mock_View)
	v^ = {kind = kind, text = strings.clone(text, mock_allocator())}
	scope_on_dispose(mock_view_release, v)
	mock.views += 1
	return View(rawptr(v))
}

mock_view_of :: proc(v: View) -> ^Mock_View {
	return (^Mock_View)(rawptr(v))
}

mock_view_release :: proc(data: rawptr) {
	v := (^Mock_View)(data)
	mock.views -= 1
	if v.text == "" do mock_log("release %s", v.kind)
	else do mock_log("release %s %s", v.kind, v.text)
}

mock_retire :: proc(s: ^Scope) {
	switch mock.retire {
	case .Now:   scope_retire(s)
	case .Later: append(&mock.parked, s)
	}
}

// The platform's later event: unbracketed like a GTK idle or WM_NV_DESTROY, or `bracketed` like
// iOS's didMoveToParentViewController:, whose callback_exit then destroys them.
mock_retire_parked :: proc(bracketed := false) {
	if bracketed do callback_enter()
	for s in mock.parked do scope_retire(s)
	clear(&mock.parked)
	if bracketed do callback_exit()
}

// Every timer posted so far is up, in post order (a timer posted meanwhile waits for the next call).
mock_fire_timers :: proc() {
	timers := mock.timers[:]
	mock.timers = make([dynamic]^Timer, mock_allocator())
	for t in timers do timer_fire(t)
}

mock_view_name :: proc(v: View) -> string {
	m := mock_view_of(v)
	return m.text == "" ? m.kind : fmt.tprintf("%s %s", m.kind, m.text)
}

// The user typed `text` (and pressed Enter, with submit), reported the way the backends do.
mock_type :: proc(h: ^Input_Handle, text: string, submit := false) {
	mock_view_of(h.root).text = strings.clone(text, mock_allocator())
	input_notify(h, submit ? h.input.on_submit : h.input.on_change)
}

// Download `i` (fetch_start order) finished with `data` (nil = failed), posted back like
// _post_main / dispatch_async_f / nativeOnFetch.
mock_fetch_finish :: proc(i: int, data: []u8) {
	f := mock.fetches[i]
	mock.fetches[i] = nil
	f.data = slice.clone(data, runtime.heap_allocator()) // fetch_notify frees it from the heap
	fetch_notify(f)
}

// ---- the backend ----

// GTK's on_activate: the platform is up, so the theme starts and the root page is built.
mock_run :: proc() {
	callback_enter()
	defer callback_exit()
	theme_start()
	nav_show_root()
}

mock_nav_push :: proc(e: ^Page_Handle) {
	mock_require(e == g_nav[len(g_nav) - 1] && e.root != nil, "_nav_push shows the built top page")
	mock_log("nav_push %s", e.page.title)
}

mock_nav_pop :: proc(top, below: ^Page_Handle) -> bool {
	mock_require(below == g_nav[len(g_nav) - 1] && !slice.contains(g_nav[:], top), "_nav_pop: `top` already left g_nav")
	mock_log("nav_pop %s -> %s", top.page.title, below.page.title)
	return mock.nav_pop_ok
}

mock_nav_release :: proc(e: ^Page_Handle) {
	mock_require(e.root != nil && !slice.contains(g_nav[:], e), "_nav_release gets a shown page that left g_nav")
	mock_log("nav_release %s", e.page.title)
	mock_retire(e.scope)
}

mock_nav_title_changed :: proc(e: ^Page_Handle) {
	mock_require(e.root != nil, "_nav_title_changed gets a shown page")
	mock_log("nav_title_changed %s", e.page.title)
}

mock_nav_actions_changed :: proc(e: ^Page_Handle) {
	mock_require(e.root != nil, "_nav_actions_changed gets a shown page")
	mock_log("nav_actions_changed %d", len(e.actions))
}

mock_list_init :: proc(h: ^List_Handle) {
	h.root = mock_view("list")
	mock_log("list_init")
}

mock_list_reload :: proc(h: ^List_Handle) {
	mock_log("list_reload")
}

mock_flex_create :: proc(f: Flex) -> View {
	for c in f.children do mock_require(c.view != nil, "a Row / Column child is a view")
	mock_log("flex_create %v %d", f.axis, len(f.children))
	return mock_view("flex")
}

mock_container_init :: proc(h: ^Container_Handle) {
	h.root = mock_view("container")
	mock_log("container_init")
}

mock_container_set_color :: proc(h: ^Container_Handle) {
	mock_log("container_set_color %v", h.container.color)
}

mock_label_init :: proc(h: ^Label_Handle) {
	h.root = mock_view("label", h.label.text)
	mock_log("label_init %s", h.label.text)
}

mock_label_set_text :: proc(h: ^Label_Handle, text: string) {
	mock_view_of(h.root).text = strings.clone(text, mock_allocator())
	mock_log("label_set_text %s", text)
}

mock_input_init :: proc(h: ^Input_Handle) {
	h.root = mock_view("input", h.input.text)
	mock_log("input_init %s", h.input.text)
}

mock_input_text :: proc(h: ^Input_Handle, allocator := context.allocator) -> string {
	return strings.clone(mock_view_of(h.root).text, allocator)
}

// Win32, GTK and Android report a programmatic set as a change: the core keeps it silent.
mock_input_set_text :: proc(h: ^Input_Handle, text: string) {
	mock_view_of(h.root).text = strings.clone(text, mock_allocator())
	mock_log("input_set_text %s", text)
	input_notify(h, h.input.on_change)
}

mock_button_init :: proc(h: ^Button_Handle) {
	h.root = mock_view("button", h.button.title)
	mock_log("button_init %s", h.button.title)
}

mock_button_set_title :: proc(h: ^Button_Handle, title: string) {
	mock_view_of(h.root).text = strings.clone(title, mock_allocator())
	mock_log("button_set_title %s", title)
}

mock_canvas_init :: proc(h: ^Canvas_Handle) {
	h.root = mock_view("canvas")
	mock_log("canvas_init")
}

mock_canvas_redraw :: proc(h: ^Canvas_Handle) {
	mock_log("canvas_redraw")
}

mock_image_init :: proc(h: ^Image_Handle) {
	h.root = mock_view("image")
	mock_log("image_init")
}

mock_image_set_bitmap :: proc(h: ^Image_Handle) {
	mock_log("image_set_bitmap %v", h.bitmap != nil)
}

// The "image" is its size: two bytes, width and height.
mock_bitmap_decode :: proc(b: ^Bitmap, data: []u8) -> bool {
	if !mock.decode_ok || len(data) < 2 {
		mock_log("bitmap_decode refused")
		return false
	}
	b.width, b.height = int(data[0]), int(data[1])
	mock_log("bitmap_decode %dx%d", b.width, b.height)
	return true
}

mock_bitmap_free :: proc(b: ^Bitmap) {
	mock_log("bitmap_free %dx%d", b.width, b.height)
}

mock_font_load :: proc(f: ^Font, data: []u8) -> bool {
	mock_log("font_load %s", f.family)
	return mock.font_ok
}

mock_font_free :: proc(f: ^Font) {
	mock_log("font_free %s", f.family)
}

mock_asset_read :: proc(path: string, allocator := context.allocator) -> []u8 {
	mock_log("asset_read %s", path)
	return slice.clone(mock.asset, allocator)
}

mock_fetch_start :: proc(f: ^Fetch) {
	append(&mock.fetches, f)
	mock_log("fetch_start %s", f.url)
}

mock_dialog_show :: proc(h: ^Dialog_Handle) {
	mock_require(slice.contains(g_dialogs[:], h) && h.scope != nil && h.body != nil, "_dialog_show gets a built dialog in g_dialogs")
	mock_log("dialog_show %s", h.dialog.title)
}

mock_dialog_close :: proc(h: ^Dialog_Handle) {
	mock_require(!slice.contains(g_dialogs[:], h) && h.scope != nil, "_dialog_close gets a shown dialog already out of g_dialogs")
	mock.modal_after_close = dialog_top_modal() // what a backend reads to restore the page
	mock_log("dialog_close %s", h.dialog.title)
	mock_retire(h.scope)
}

mock_dialog_set_hidden :: proc(h: ^Dialog_Handle, hidden: bool) {
	mock_require(h.hidden == hidden, "_dialog_set_hidden after the core set the flag")
	mock_log("dialog_set_hidden %s %v", h.dialog.title, hidden)
}

mock_view_set_hidden :: proc(v: View, hidden: bool) {
	mock_require(v != nil, "_view_set_hidden gets a view")
	mock_view_of(v).hidden = hidden
	mock_log("%s %s", hidden ? "hide" : "show", mock_view_name(v))
}

mock_view_set_enabled :: proc(v: View, enabled: bool) {
	mock_require(v != nil, "_view_set_enabled gets a view")
	mock_log("%s %s", enabled ? "enable" : "disable", mock_view_name(v))
}

mock_overlay_init :: proc(h: ^Overlay_Handle) {
	mock_require(h.base != nil, "_overlay_init gets a base view")
	h.root = mock_view("overlay")
	mock_log("overlay_init %s", mock_view_name(h.base))
}

mock_overlay_add :: proc(h: ^Overlay_Handle, child: View, place: Overlay_Place) {
	mock_require(h.root != nil && child != nil, "_overlay_add gets a made overlay and a view")
	mock_log("overlay_add %s %v %v", mock_view_name(child), place.h, place.v)
}

mock_overlay_place :: proc(h: ^Overlay_Handle, child: View, place: Overlay_Place) {
	mock_log("overlay_place %s bottom %v", mock_view_name(child), place.margin.bottom)
}

mock_overlay_scrim_init :: proc(h: ^Overlay_Handle) {
	mock_require(h.root != nil && h.scrim == nil, "_overlay_scrim_init once per made overlay")
	h.scrim = mock_view("scrim")
	mock_log("overlay_scrim_init")
}

mock_fab_init :: proc(h: ^Fab_Handle) {
	h.root = mock_view("fab", h.fab.label)
	mock_log("fab_init %v %s", h.fab.icon, h.fab.label)
}

mock_tabbar_init :: proc(h: ^Tabbar_Handle) {
	h.root = mock_view("tabbar")
	mock_log("tabbar_init %d %d", len(h.tabs), h.selected)
}

mock_tabbar_select :: proc(h: ^Tabbar_Handle) {
	mock_log("tabbar_select %d", h.selected)
}

mock_post_delayed :: proc(ms: int, t: ^Timer) {
	append(&mock.timers, t)
	mock_log("post_delayed %d", ms)
}

mock_theme_system_dark :: proc() -> bool {
	return mock.system_dark
}

mock_theme_system_accent :: proc() -> Color {
	return mock.system_accent
}

mock_theme_apply_mode :: proc() {
	mock_log("theme_apply_mode %v", g_theme.mode)
}

mock_theme_recolor :: proc() {
	mock_log("theme_recolor %v", g_dark)
}

// ---- scripted pages and dialogs ----

// A test page: mock_page(&mp) makes a Page whose build does what the fields ask, in this order,
// and returns a label with the page's name; build and on_pop log themselves.
Mock_Page :: struct {
	name:         string,
	actions:      []Action,
	title:        string,       // build: page_set_title (the bar must not hear of it yet)
	build_actions: []Action,    // build: page_set_actions (neither)
	push:         ^Page,        // build: push (queued until this page is shown)
	dialog:       ^Mock_Dialog, // build: dialog_show (pending until this page is shown)
	close_dialog: bool,         // build: and dialog_close at once
	pop:          bool,         // build: pop (ignored)
	pop_title:    string,       // on_pop: page_set_title (the page is gone: nothing to show)
	pop_actions:  []Action,     // on_pop: page_set_actions (nor this)
	handle:       ^Page_Handle, // set by build
	label:        ^Label_Handle,
	pushed:       ^Page_Handle, // what the push returned
}

mock_page :: proc(mp: ^Mock_Page) -> Page {
	return {title = mp.name, build = mock_build, user_data = mp, on_pop = mock_on_pop, actions = mp.actions}
}

mock_build :: proc(page: ^Page_Handle, user: rawptr) -> View {
	mp := (^Mock_Page)(user)
	mock_log("build %s", mp.name)
	mp.handle = page
	if mp.title != "" do page_set_title(page, mp.title)
	if mp.build_actions != nil do page_set_actions(page, mp.build_actions)
	if mp.push != nil do mp.pushed = push(mp.push^)
	if mp.dialog != nil {
		mock_show(mp.dialog)
		if mp.close_dialog do dialog_close(mp.dialog.handle)
	}
	if mp.pop do pop()
	mp.label = label_create({text = mp.name})
	return label_view(mp.label)
}

mock_on_pop :: proc(user: rawptr) {
	mp := (^Mock_Page)(user)
	mock_log("on_pop %s", mp.name)
	mock_require(mp.label.label.text == mp.name, "on_pop still sees its page's widgets")
	if mp.pop_title != "" do page_set_title(mp.handle, mp.pop_title)
	if mp.pop_actions != nil do page_set_actions(mp.handle, mp.pop_actions)
}

Mock_Dialog :: struct {
	name:    string,
	modal:   bool,
	content: View,
	buttons: []Dialog_Button,
	reclose: bool,           // on_close calls dialog_close again (must be a no-op)
	handle:  ^Dialog_Handle, // set by mock_show
}

mock_show :: proc(md: ^Mock_Dialog) -> ^Dialog_Handle {
	md.handle = dialog_show({title = md.name, content = md.content, buttons = md.buttons, modal = md.modal, on_close = mock_on_close, user = md})
	return md.handle
}

mock_on_close :: proc(user: rawptr) {
	md := (^Mock_Dialog)(user)
	mock_log("on_close %s", md.name)
	if md.reclose do dialog_close(md.handle)
}

mock_close_clicked :: proc(d: ^Dialog_Handle, _: rawptr) {
	dialog_close(d)
}

mock_pop_clicked :: proc(_: ^Dialog_Handle, _: rawptr) {
	pop()
}

mock_action_clicked :: proc(_: rawptr) {
	mock_log("action")
}

// run with a scripted root page, its startup calls cleared from the log.
mock_launch :: proc(root: ^Mock_Page) {
	run(mock_page(root))
	mock_log_clear()
}
