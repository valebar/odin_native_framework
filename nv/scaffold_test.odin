#+build-project-name nv
#+build !js
package nv

import "core:fmt"
import "core:testing"

// A page whose build makes a scaffold from these fields; the bodies and the drawer are labels.
Mock_Scaffold :: struct {
	tabs:     []string,     // tab titles; none = one body labelled "body"
	tab:      int,
	fab:      bool,
	drawer:   bool,
	handle:   ^Scaffold_Handle,
	page:     ^Page_Handle,
	switched: [dynamic]int, // on_tab calls
	actions:  int,          // on_action calls
}

mock_scaffold_page :: proc(ms: ^Mock_Scaffold, title := "S") -> Page {
	return {title = title, build = mock_scaffold_build, user = ms}
}

mock_scaffold_build :: proc(user: rawptr, page: ^Page_Handle) -> View {
	ms := (^Mock_Scaffold)(user)
	ms.page = page
	s := Scaffold{tab = ms.tab, user = ms, on_tab = proc(user: rawptr, index: int) {
		append(&(^Mock_Scaffold)(user).switched, index)
	}}
	if len(ms.tabs) > 0 {
		tabs := make([]Tab, len(ms.tabs), context.temp_allocator)
		for title, i in ms.tabs do tabs[i] = {title = title, icon = .Home, body = view(label_create({text = title}))}
		s.tabs = tabs
	} else {
		s.body = view(label_create({text = "body"}))
	}
	if ms.fab do s.fab = {icon = .Add, on_click = mock_action_clicked}
	if ms.drawer do s.drawer = view(label_create({text = "drawer"}))
	ms.handle = scaffold_create(s)
	return view(ms.handle)
}

mock_snack_action :: proc(user: rawptr) {
	(^Mock_Scaffold)(user).actions += 1
}

@(test)
test_scaffold_tabs :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms := Mock_Scaffold{tabs = {"A", "B", "C"}, tab = 1}
	defer delete(ms.switched)
	run(mock_scaffold_page(&ms))
	expect_log(t, "theme_apply_mode System",
		"label_init A", "label_init B", "label_init C",
		"container_init", "overlay_init container",
		"overlay_add label A Fill Fill sizes", "hide label A", "overlay_add label B Fill Fill sizes", "overlay_add label C Fill Fill sizes", "hide label C",
		"label_init ", "button_init ", "flex_create Horizontal 2", "container_init", "container_init",
		"flex_create Vertical 3", "container_init", "overlay_add container Fill End", "hide container",
		"tabbar_init 3 1", "flex_create Vertical 2",
		"nav_push S")
	h := ms.handle
	testing.expect(t, h.root != nil && ms.page.scaffold == h && h.outer == nil && h.fab == nil && g_scaffolds == nil)

	tabbar_notify(h.tabbar, 2) // the user taps C
	expect_log(t, "hide label B", "show label C")
	tabbar_notify(h.tabbar, 2) // again: nothing
	expect_log(t)
	scaffold_set_tab(h, 0)
	expect_log(t, "hide label C", "show label A", "tabbar_select 0")
	scaffold_set_tab(h, 3) // out of range
	expect_log(t)
	testing.expect(t, len(ms.switched) == 2 && ms.switched[0] == 2 && ms.switched[1] == 0)
	testing.expect(t, h.tab == 0 && h.tabbar.selected == 0)
}

@(test)
test_snackbar_hides_after_its_time :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms := Mock_Scaffold{fab = true}
	run(mock_scaffold_page(&ms))
	mock_log_clear()
	h := ms.handle

	callback_enter()
	scaffold_show_snackbar(h, {message = "Saved"})
	callback_exit()
	expect_log(t, "label_set_text Saved", "button_set_title ", "hide button", "post_delayed 4000",
		"show container", "overlay_place fab bottom 72")
	mock_fire_timers()
	expect_log(t, "hide container", "overlay_place fab bottom 16")
	testing.expect(t, !h.snack_shown && h.snack_timer == nil)
	scaffold_hide_snackbar(h) // already hidden
	expect_log(t)
}

@(test)
test_snackbar_replaces_the_shown_one :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms := Mock_Scaffold{}
	run(mock_scaffold_page(&ms))
	mock_log_clear()
	h := ms.handle

	scaffold_show_snackbar(h, {message = "One"})
	scaffold_show_snackbar(h, {message = "Two", action = "Undo", duration_ms = 1000})
	expect_log(t, "label_set_text One", "button_set_title ", "hide button", "post_delayed 4000", "show container",
		"label_set_text Two", "button_set_title Undo", "show button Undo", "post_delayed 1000") // no FAB to move
	testing.expect(t, len(mock.timers) == 2 && mock.timers[0].cancelled && !mock.timers[1].cancelled)
	timers := mock.timers[:]
	mock.timers = {}
	timer_fire(timers[0]) // the replaced one: nothing
	expect_log(t)
	testing.expect(t, h.snack_shown)
	timer_fire(timers[1])
	expect_log(t, "hide container")
}

@(test)
test_snackbar_action :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms := Mock_Scaffold{fab = true}
	run(mock_scaffold_page(&ms))
	h := ms.handle
	scaffold_show_snackbar(h, {message = "Deleted", action = "Undo", on_action = mock_snack_action, user = &ms})
	mock_log_clear()

	button_notify(h.snack_button)
	expect_log(t, "hide container", "overlay_place fab bottom 16")
	testing.expect(t, ms.actions == 1 && !h.snack_shown && mock.timers[0].cancelled)
	button_notify(h.snack_button) // a second click before the view is gone: no action left
	testing.expect(t, ms.actions == 1)
}

// The page pops while its SnackBar shows: the timer outlives the scaffold and does nothing.
@(test)
test_snackbar_timer_outlives_page :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root := Mock_Page{name = "Root"}
	ms := Mock_Scaffold{fab = true, drawer = true}
	mock_launch(&root)
	callback_enter()
	push(mock_scaffold_page(&ms, "S"))
	scaffold_show_snackbar(ms.handle, {message = "Hi"})
	callback_exit()
	views := mock.views

	callback_enter()
	pop()
	testing.expect(t, !mock.timers[0].cancelled, "the scaffold lives until the callback returns")
	callback_exit()
	testing.expect(t, mock.views < views && mock.timers[0].cancelled && g_scaffolds == nil)
	mock_log_clear()
	mock_fire_timers()
	expect_log(t)
}

@(test)
test_drawer :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms := Mock_Scaffold{drawer = true}
	run(mock_scaffold_page(&ms))
	h := ms.handle
	testing.expect(t, h.outer != nil && h.outer.scrim != nil && h.root == h.outer.root)
	testing.expect(t, nav_shows_menu(ms.page))
	mock_log_clear()

	nav_menu_notify() // the bar's menu button
	expect_log(t, "disable overlay", "show scrim", "show container")
	overlay_scrim_notify(h.outer) // a tap beside the panel
	expect_log(t, "hide container", "hide scrim", "enable overlay")
	scaffold_close_drawer(h) // already closed
	expect_log(t)

	scaffold_open_drawer(h)
	mock_log_clear()
	nav_back_notify() // the back button closes the drawer; the root page would not pop anyway
	expect_log(t, "hide container", "hide scrim", "enable overlay")
	testing.expect(t, !h.drawer_open)
}

// A light / dark flip recolors every drawer panel, an open one too.
@(test)
test_drawer_follows_theme :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms := Mock_Scaffold{drawer = true}
	run(mock_scaffold_page(&ms))
	testing.expect(t, g_scaffolds == ms.handle)
	scaffold_open_drawer(ms.handle)
	mock_log_clear()
	mock.system_dark = true
	theme_notify()
	expect_log(t, "theme_recolor true", fmt.tprintf("container_set_color %v", PALETTE_DARK.background))
}

// On a pushed page, back closes the drawer first and pops on the next press; no menu button.
@(test)
test_drawer_back_on_pushed_page :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root := Mock_Page{name = "Root"}
	ms := Mock_Scaffold{drawer = true}
	mock_launch(&root)
	callback_enter()
	push(mock_scaffold_page(&ms, "S"))
	callback_exit()
	testing.expect(t, !nav_shows_menu(ms.page) && !nav_shows_menu(g_nav[0]))
	scaffold_open_drawer(ms.handle)
	mock_log_clear()

	nav_back_notify()
	expect_log(t, "hide container", "hide scrim", "enable overlay")
	nav_menu_notify() // no menu button on this page, but the core still toggles the top page's drawer
	nav_back_notify()
	nav_back_notify()
	testing.expect(t, len(g_nav) == 1)
}

// A modal dialog blocks the menu button, like the bar's other buttons.
@(test)
test_menu_blocked_by_modal :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms := Mock_Scaffold{drawer = true}
	d := Mock_Dialog{name = "D", modal = true}
	run(mock_scaffold_page(&ms))
	mock_show(&d)
	mock_log_clear()
	nav_menu_notify()
	expect_log(t)
	testing.expect(t, !ms.handle.drawer_open)
}

@(test)
test_fab_click :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms := Mock_Scaffold{fab = true}
	run(mock_scaffold_page(&ms))
	mock_log_clear()
	fab_notify(ms.handle.fab)
	expect_log(t, "action")
}

// A Stack is an overlay over an empty base whose children all count toward its size, in order.
@(test)
test_stack_create :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	Stack_Page :: struct { stack: ^Stack_Handle }
	sp: Stack_Page
	run({title = "S", user = &sp, build = proc(user: rawptr, _: ^Page_Handle) -> View {
		back := view(label_create({text = "back"}))
		badge := view(label_create({text = "badge"}))
		(^Stack_Page)(user).stack = stack_create({
			{view = back, h = .Fill, v = .Fill},
			{view = badge, h = .End, v = .Start, margin = {0, 8, 8, 0}, width = 40},
		})
		return view((^Stack_Page)(user).stack)
	}})
	expect_log(t, "theme_apply_mode System", "label_init back", "label_init badge", "container_init", "overlay_init container",
		"overlay_add label back Fill Fill sizes", "overlay_add label badge End Start sizes", "nav_push S")
	testing.expect(t, mock_view_of(view(sp.stack)).kind == "overlay" && mock.views == 4) // two labels, the base, the overlay

	// stack_place moves a child through the overlay, as the FAB moves; a centered axis drops its margins.
	badge := sp.stack.children[1]
	stack_place(sp.stack, badge, {h = .Center, v = .End, margin = {5, 0, 5, 24}, width = 60})
	expect_log(t, "overlay_place label badge bottom 24")
	o := sp.stack.overlay
	place := stack_overlay_place({h = .Center, v = .End, margin = {5, 0, 5, 24}, width = 60})
	testing.expect(t, place.margin == {0, 0, 0, 24} && place.width == 60 && place.sizes && o.root == view(sp.stack))
}

// Each "\n" in the message makes the SnackBar 20 taller and the FAB moves with it; a one-line
// message brings it back to 48.
@(test)
test_snackbar_lines :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms := Mock_Scaffold{fab = true}
	run(mock_scaffold_page(&ms))
	mock_log_clear()
	h := ms.handle

	scaffold_show_snackbar(h, {message = "Error setting the property\nOut of range"})
	expect_log(t, "label_set_text Error setting the property\nOut of range", "button_set_title ", "hide button",
		"container_set_size 0 68", "overlay_place container bottom 8", "post_delayed 4000", "show container", "overlay_place fab bottom 92")
	scaffold_show_snackbar(h, {message = "Saved"}) // replaces it: one line again, the FAB follows
	expect_log(t, "label_set_text Saved", "button_set_title ", "hide button",
		"container_set_size 0 48", "overlay_place container bottom 8", "post_delayed 4000", "overlay_place fab bottom 72")
	scaffold_show_snackbar(h, {message = "Again"})
	expect_log(t, "label_set_text Again", "button_set_title ", "hide button", "post_delayed 4000")
	scaffold_hide_snackbar(h)
	scaffold_show_snackbar(h, {message = "A\nB\nC"}) // hidden: sized before it shows
	expect_log(t, "hide container", "overlay_place fab bottom 16", "label_set_text A\nB\nC", "button_set_title ", "hide button",
		"container_set_size 0 88", "overlay_place container bottom 8", "post_delayed 4000", "show container", "overlay_place fab bottom 112")
}

// Snackbar.color replaces the background only when it changes; alpha 0 is the default grey.
@(test)
test_snackbar_color :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms := Mock_Scaffold{}
	run(mock_scaffold_page(&ms))
	mock_log_clear()
	h := ms.handle
	scaffold_show_snackbar(h, {message = "Red", color = {1, 0, 0, 1}})
	scaffold_show_snackbar(h, {message = "Again", color = {1, 0, 0, 1}})
	scaffold_show_snackbar(h, {message = "Grey"})
	expect_log(t, "label_set_text Red", "button_set_title ", "container_set_color [1, 0, 0, 1]", "hide button", "post_delayed 4000", "show container",
		"label_set_text Again", "button_set_title ", "hide button", "post_delayed 4000",
		"label_set_text Grey", "button_set_title ", "container_set_color [0.2, 0.2, 0.2, 1]", "hide button", "post_delayed 4000")
}
