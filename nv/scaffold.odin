package nv

// Flutter's Scaffold, below the page's own bar (the AppBar is the Page: title, back button,
// actions): a body or a set of bottom tabs, a floating action button, a SnackBar and a Drawer.
// The core composes it from small native pieces (an overlay that stacks views over a base, a
// scrim, a round icon button, a tab bar, a one-shot timer) and the framework's own widgets (the
// SnackBar is a Container, the drawer panel another), so the backends only add those pieces:
//
//   outer overlay (only with a drawer): base = Column[inner overlay (flex 1), tab bar (flex 0)]
//     scrim (hidden; a tap closes the drawer), drawer panel (hidden; leading, full height)
//   inner overlay: base = the body, or with tabs an empty Container under the tab bodies
//     tab bodies (full size, all but one hidden), FAB (bottom trailing), SnackBar (bottom, full width, hidden)
//
// The tab bodies are overlay children rather than flex children of a Column: a Row / Column links
// the sizes of its flex children (exact weights), which a hidden child would have to break.
//
// Nothing animates yet: the drawer, the SnackBar and the tab bodies appear and disappear at once.

import "base:runtime"
import "core:strings"

// One bottom tab. The bodies of every tab are built up front and kept; only one is visible.
Tab :: struct {
	title: string, // copied
	icon:  Icon,
	body:  View,
}

// Flutter's FloatingActionButton: a round button in the accent color with an icon, or an extended
// one (icon and label, or only a label) when `label` is set. Floats over the body's bottom
// trailing corner and moves up while a SnackBar shows. An icon the platform has no image for shows
// Add's instead.
Fab :: struct {
	icon:     Icon,
	label:    string, // copied; "" = a round icon button
	on_click: proc(user: rawptr), // optional
	user:     rawptr,
}

// A short message at the bottom of the body, with an optional action button. One at a time: a new
// one replaces the one showing. It hides after `duration_ms` or when the action is clicked. The
// message is one line; a longer one is cut.
Snackbar :: struct {
	message:     string, // copied
	action:      string, // copied; "" = no button
	on_action:   proc(user: rawptr), // optional; the SnackBar is already hidden
	user:        rawptr,
	duration_ms: int, // 4000 when 0
}

Scaffold :: struct {
	body:   View,  // shown when `tabs` is empty
	tabs:   []Tab, // copied; with tabs, a bottom bar switches between their bodies
	tab:    int,   // the initially selected tab
	on_tab: proc(user: rawptr, index: int), // optional; after the selected tab changed
	fab:    Fab,   // shown when fab.icon != .None or fab.label != ""
	drawer: View,  // optional; the root page's bar gets a menu button that opens it (Flutter's hamburger)
	user:   rawptr,
}

Scaffold_Handle :: struct {
	scaffold:     Scaffold, // scaffold.tabs is not kept (see tabbar)
	ctx:          runtime.Context,
	root:         View, // the outer view, embedded by the app (the page's build returns it)
	inner, outer: ^Overlay_Handle, // outer is nil without a drawer
	bodies:       []View, // the tab bodies, or nil
	tab:          int,
	tabbar:       ^Tabbar_Handle, // nil without tabs
	fab:          ^Fab_Handle,    // nil without a FAB
	snack:        ^Container_Handle,
	snack_label:  ^Label_Handle,
	snack_button: ^Button_Handle,
	snack_action: proc(user: rawptr),
	snack_user:   rawptr,
	snack_shown:  bool,
	snack_timer:  ^Timer,
	panel:        ^Container_Handle, // the drawer panel, nil without a drawer
	drawer_open:  bool,
	prev, next:   ^Scaffold_Handle,  // g_scaffolds, with a drawer only
}

// Every live scaffold with a drawer, so theme_notify can recolor the panels (an open one too).
// Linked through the handles, like g_progress; scaffold_dispose unlinks.
@(private) g_scaffolds: ^Scaffold_Handle

// Where an overlay child sits (see Stack_Child): `sizes` children count toward the overlay's
// natural size (the largest of them, margins included, and the base). A Stack's children all do;
// the Scaffold's FAB, SnackBar and drawer don't, so they never set a minimum page size (Android's
// FrameLayout counts every child, and on Apple a Fill axis is pinned by required edge equalities,
// so a hidden tab body, the SnackBar's width and the drawer's height still count there: the
// Scaffold is always stretched, so only the minimum shows).
@(private) Overlay_Place :: struct {
	h, v:          Align,
	margin:        Insets,
	width, height: f64,
	sizes:         bool,
}

// A native container whose `base` fills it, with children stacked above it in add order. The
// backend makes `root` in overlay_init; `overlay_scrim_init` adds a dimming child that takes the
// pointer (the dialog's scrim, but a tap reports through overlay_scrim_notify).
@(private) Overlay_Handle :: struct {
	ctx:      runtime.Context,
	base:     View,
	root:     View,
	native:   rawptr, // backend data
	scrim:    View,   // set by overlay_scrim_init
	on_scrim: proc(user: rawptr),
	user:     rawptr,
}

@(private) Fab_Handle :: struct {
	fab:     Fab, // fab.label is an owned copy (heap)
	ctx:     runtime.Context,
	root:    View,
	control: rawptr, // NSButton* / UIButton* / ImageButton or Button / GtkButton* / NVFab HWND
	target:  rawptr, // target / listener, where the platform needs one
}

@(private) Tabbar_Handle :: struct {
	tabs:     []Tab, // titles are owned copies (heap); bodies are not used by the backends
	selected: int,
	ctx:      runtime.Context,
	root:     View,
	control:  rawptr, // NSSegmentedControl* / UITabBar* / LinearLayout / GtkBox* / NVTabbar HWND
	target:   rawptr, // delegate / listeners, where the platform needs them
	items:    rawptr, // backend per-tab data
	scaffold: ^Scaffold_Handle,
}

// A one-shot main-thread timer: the backend's _post_delayed calls timer_fire after `ms`. Heap
// memory (the backend outlives any scope), freed by timer_fire; a cancelled timer still fires but
// does nothing, like a detached Image_Fetch.
@(private) Timer :: struct {
	fn:        proc(data: rawptr),
	data:      rawptr,
	cancelled: bool,
	ctx:       runtime.Context,
}

@(private) SNACK_HEIGHT :: 48
@(private) SNACK_MARGIN :: 8
@(private) FAB_MARGIN   :: 16
@(private) DRAWER_WIDTH :: 304
@(private) SNACK_COLOR  :: Color{0.2, 0.2, 0.2, 1}

// Makes the page's scaffold; call it from the page's `build` and return `scaffold_view`. One per
// page; the views in `body`, the tab bodies and `drawer` belong to it.
scaffold_create :: proc(s: Scaffold) -> ^Scaffold_Handle {
	assert(g_nav_building > 0 && g_scope_override == nil, "nv.scaffold_create belongs in a page's build")
	page := g_nav[len(g_nav) - 1]
	assert(page.scaffold == nil, "nv: one scaffold per page")
	h := scope_new_in(Scaffold_Handle)
	h.scaffold = s
	h.scaffold.tabs = nil
	h.ctx = context
	page.scaffold = h
	scope_on_dispose(scaffold_dispose, h)

	if len(s.tabs) > 0 {
		h.tab = clamp(s.tab, 0, len(s.tabs) - 1)
		h.bodies = make([]View, len(s.tabs), scope_allocator(scope_current()))
		h.inner = overlay_new(container_view(container_create({})))
		for t, i in s.tabs {
			assert(t.body != nil, "nv.scaffold_create: every tab has a body")
			h.bodies[i] = t.body
			g_backend.overlay_add(h.inner, t.body, {h = .Fill, v = .Fill, sizes = true})
			if i != h.tab do g_backend.view_set_hidden(t.body, true)
		}
	} else {
		assert(s.body != nil, "nv.scaffold_create: a body or tabs")
		h.inner = overlay_new(s.body)
	}

	if s.fab.icon != .None || s.fab.label != "" {
		h.fab = scope_new_in(Fab_Handle)
		h.fab.fab = s.fab
		h.fab.fab.label = strings.clone(s.fab.label, nv_heap())
		h.fab.ctx = context
		scope_on_dispose(fab_dispose, h.fab)
		g_backend.fab_init(h.fab)
		g_backend.overlay_add(h.inner, h.fab.root, scaffold_fab_place(h))
	}

	h.snack_label = label_create({style = {color = {1, 1, 1, 1}}})
	h.snack_button = button_create({on_click = scaffold_snack_clicked, user = h})
	row := row_create({{label_view(h.snack_label), 1}, {button_view(h.snack_button), 0}}, spacing = 8)
	top, bottom := container_create({}), container_create({}) // centre the row in the fixed height
	h.snack = container_create({
		child  = column_create({{container_view(top), 1}, {row, 0}, {container_view(bottom), 1}}),
		color  = SNACK_COLOR, radius = 4, height = SNACK_HEIGHT, padding = {16, 0, 8, 0},
	})
	g_backend.overlay_add(h.inner, container_view(h.snack),
		{h = .Fill, v = .End, margin = insets_all(SNACK_MARGIN), height = SNACK_HEIGHT})
	g_backend.view_set_hidden(container_view(h.snack), true)

	root := h.inner.root
	if len(s.tabs) > 0 {
		h.tabbar = scope_new_in(Tabbar_Handle)
		h.tabbar.tabs = make([]Tab, len(s.tabs), scope_allocator(scope_current()))
		for t, i in s.tabs {
			h.tabbar.tabs[i] = t
			h.tabbar.tabs[i].title = strings.clone(t.title, nv_heap())
		}
		h.tabbar.selected = h.tab
		h.tabbar.ctx = context
		h.tabbar.scaffold = h
		scope_on_dispose(tabbar_dispose, h.tabbar)
		g_backend.tabbar_init(h.tabbar)
		root = column_create({{root, 1}, {h.tabbar.root, 0}})
	}

	if s.drawer != nil {
		h.outer = overlay_new(root)
		h.outer.on_scrim, h.outer.user = scaffold_scrim_tapped, h
		g_backend.overlay_scrim_init(h.outer)
		g_backend.view_set_hidden(h.outer.scrim, true)
		h.panel = container_create({child = s.drawer, color = theme_palette().background})
		g_backend.overlay_add(h.outer, container_view(h.panel), {h = .Start, v = .Fill, width = DRAWER_WIDTH})
		g_backend.view_set_hidden(container_view(h.panel), true)
		root = h.outer.root
		h.next = g_scaffolds
		if g_scaffolds != nil do g_scaffolds.prev = h
		g_scaffolds = h
	}
	h.root = root
	return h
}

scaffold_view :: proc(h: ^Scaffold_Handle) -> View {
	return h.root
}

// Selects a tab (out-of-range indexes are ignored) and calls `on_tab`.
scaffold_set_tab :: proc(h: ^Scaffold_Handle, index: int) {
	if h.tabbar == nil || index < 0 || index >= len(h.bodies) || index == h.tab do return
	scaffold_switch(h, index)
	h.tabbar.selected = index
	g_backend.tabbar_select(h.tabbar)
	if h.scaffold.on_tab != nil do h.scaffold.on_tab(h.scaffold.user, index)
}

// The scrim keeps the pointer off the page and the page is disabled, so the keyboard can't reach
// it either, as under a modal dialog.
scaffold_open_drawer :: proc(h: ^Scaffold_Handle) {
	if h.panel == nil || h.drawer_open do return
	h.drawer_open = true
	g_backend.view_set_enabled(h.outer.base, false)
	g_backend.view_set_hidden(h.outer.scrim, false)
	g_backend.view_set_hidden(container_view(h.panel), false)
}

scaffold_close_drawer :: proc(h: ^Scaffold_Handle) {
	if h.panel == nil || !h.drawer_open do return
	h.drawer_open = false
	g_backend.view_set_hidden(container_view(h.panel), true)
	g_backend.view_set_hidden(h.outer.scrim, true)
	g_backend.view_set_enabled(h.outer.base, true)
}

// Shows a SnackBar over the bottom of the body, replacing the one showing.
snackbar_show :: proc(h: ^Scaffold_Handle, s: Snackbar) {
	label_set_text(h.snack_label, s.message)
	button_set_title(h.snack_button, s.action)
	g_backend.view_set_hidden(button_view(h.snack_button), s.action == "")
	h.snack_action, h.snack_user = s.on_action, s.user
	if h.snack_timer != nil do h.snack_timer.cancelled = true
	h.snack_timer = timer_start(s.duration_ms > 0 ? s.duration_ms : 4000, scaffold_snack_expired, h)
	if h.snack_shown do return
	h.snack_shown = true
	g_backend.view_set_hidden(container_view(h.snack), false)
	if h.fab != nil do g_backend.overlay_place(h.inner, h.fab.root, scaffold_fab_place(h))
}

snackbar_hide :: proc(h: ^Scaffold_Handle) {
	if !h.snack_shown do return
	h.snack_shown = false
	if h.snack_timer != nil do h.snack_timer.cancelled = true
	h.snack_timer = nil
	h.snack_action, h.snack_user = nil, nil
	g_backend.view_set_hidden(container_view(h.snack), true)
	if h.fab != nil do g_backend.overlay_place(h.inner, h.fab.root, scaffold_fab_place(h))
}

// Never touches the page: it may be freed by now (nav_detach_scaffold already cut the link).
@(private)
scaffold_dispose :: proc(data: rawptr) {
	h := (^Scaffold_Handle)(data)
	if h.snack_timer != nil do h.snack_timer.cancelled = true
	if h.panel == nil do return
	if h.prev != nil do h.prev.next = h.next
	else do g_scaffolds = h.next
	if h.next != nil do h.next.prev = h.prev
}

// After a light / dark flip (theme_notify).
@(private)
scaffold_recolor :: proc() {
	for s := g_scaffolds; s != nil; s = s.next do container_set_color(s.panel, theme_palette().background)
}

@(private)
scaffold_fab_place :: proc(h: ^Scaffold_Handle) -> Overlay_Place {
	bottom: f64 = FAB_MARGIN
	if h.snack_shown do bottom += SNACK_HEIGHT + SNACK_MARGIN
	return {h = .End, v = .End, margin = {0, 0, FAB_MARGIN, bottom}}
}

@(private)
scaffold_switch :: proc(h: ^Scaffold_Handle, index: int) {
	g_backend.view_set_hidden(h.bodies[h.tab], true)
	g_backend.view_set_hidden(h.bodies[index], false)
	h.tab = index
}

@(private)
scaffold_snack_clicked :: proc(user: rawptr) {
	h := (^Scaffold_Handle)(user)
	cb, u := h.snack_action, h.snack_user
	snackbar_hide(h)
	if cb != nil do cb(u)
}

@(private)
scaffold_snack_expired :: proc(data: rawptr) {
	h := (^Scaffold_Handle)(data)
	h.snack_timer = nil // timer_fire frees it
	snackbar_hide(h)
}

@(private)
scaffold_scrim_tapped :: proc(user: rawptr) {
	scaffold_close_drawer((^Scaffold_Handle)(user))
}

// The top page's open drawer, which a back button / key closes before it pops anything.
@(private)
scaffold_top_drawer :: proc "contextless" () -> ^Scaffold_Handle {
	if len(g_nav) == 0 do return nil
	s := g_nav[len(g_nav) - 1].scaffold
	return s != nil && s.drawer_open ? s : nil
}

// Whether the page's bar shows the leading menu button: like Flutter, on a page with a drawer and
// no back button. Contextless for the Win32 layout code.
@(private)
nav_shows_menu :: proc "contextless" (e: ^Page_Handle) -> bool {
	return len(g_nav) == 1 && e == g_nav[0] && e.scaffold != nil && e.scaffold.panel != nil
}

// Called by the backends when the bar's menu button was clicked. Ignored while a modal dialog is up.
@(private)
nav_menu_notify :: proc() {
	if len(g_nav) == 0 || dialog_top_modal() != nil do return
	s := g_nav[len(g_nav) - 1].scaffold
	if s == nil do return
	callback_enter()
	defer callback_exit()
	if s.drawer_open do scaffold_close_drawer(s)
	else do scaffold_open_drawer(s)
}

@(private)
overlay_new :: proc(base: View) -> ^Overlay_Handle {
	o := scope_new_in(Overlay_Handle)
	o.base = base
	o.ctx = context
	g_backend.overlay_init(o)
	return o
}

// Called by the backends when the scrim was tapped.
@(private)
overlay_scrim_notify :: proc(h: ^Overlay_Handle) {
	if h.on_scrim == nil do return
	callback_enter()
	defer callback_exit()
	h.on_scrim(h.user)
}

@(private)
fab_dispose :: proc(data: rawptr) {
	delete((^Fab_Handle)(data).fab.label, nv_heap())
}

// Called by the backends when the FAB was clicked.
@(private)
fab_notify :: proc(h: ^Fab_Handle) {
	if h.fab.on_click == nil do return
	callback_enter()
	defer callback_exit()
	h.fab.on_click(h.fab.user)
}

@(private)
tabbar_dispose :: proc(data: rawptr) {
	for t in (^Tabbar_Handle)(data).tabs do delete(t.title, nv_heap())
}

// Called by the backends when the user selected tab `index` (the native bar already shows it).
@(private)
tabbar_notify :: proc(h: ^Tabbar_Handle, index: int) {
	s := h.scaffold
	if index < 0 || index >= len(s.bodies) || index == s.tab do return
	callback_enter()
	defer callback_exit()
	h.selected = index
	scaffold_switch(s, index)
	if s.scaffold.on_tab != nil do s.scaffold.on_tab(s.scaffold.user, index)
}

@(private)
timer_start :: proc(ms: int, fn: proc(data: rawptr), data: rawptr) -> ^Timer {
	t := new(Timer, nv_heap())
	t^ = {fn = fn, data = data, ctx = context}
	g_backend.post_delayed(ms, t)
	return t
}

// Called by the backends on the main thread once the timer's time is up.
@(private)
timer_fire :: proc "contextless" (t: ^Timer) {
	context = t.ctx
	if !t.cancelled {
		callback_enter()
		t.fn(t.data)
		callback_exit()
	}
	free(t, nv_heap())
}
