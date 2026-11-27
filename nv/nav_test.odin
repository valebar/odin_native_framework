#+build-project-name nv
#+build !js
package nv

// The core's page stack, dialogs and scopes against the mock backend (mock_test.odin). Each test
// starts with mock_begin(t) and ends with mock_end(t); callback_enter / callback_exit around a step
// stand for the native callback (a click) it runs in. Logs are exact and in order.

import "base:runtime"
import "core:testing"

@(test)
test_push_and_pop :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b := Mock_Page{name = "Root"}, Mock_Page{name = "B"}
	run(mock_page(&root))
	expect_log(t, "theme_apply_mode System", "build Root", "label_init Root", "nav_push Root")

	callback_enter() // a click on the root page
	bh := push(mock_page(&b))
	expect_log(t, "build B", "label_init B", "nav_push B")
	testing.expect(t, len(g_nav) == 2 && g_nav[1] == bh)
	pop()
	expect_log(t, "nav_pop B -> Root", "nav_release B", "on_pop B") // retired, not destroyed: the click still runs
	testing.expect_value(t, b.label.label.text, "B")
	callback_exit()
	expect_log(t, "release label B")
	testing.expect_value(t, len(g_nav), 1)
}

// app/main.odin's "Leave": a dialog's button pops the page under it.
@(test)
test_pop_from_dialog_button :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b := Mock_Page{name = "Root"}, Mock_Page{name = "B"}
	d := Mock_Dialog{name = "D", modal = true, buttons = {
		{title = "Stay", on_click = mock_close_clicked},
		{title = "Leave", on_click = mock_pop_clicked},
	}}
	mock_launch(&root)
	callback_enter()
	push(mock_page(&b))
	mock_show(&d)
	callback_exit()
	mock_log_clear()

	button_notify(d.handle.buttons[1].handle)
	expect_log(t, "nav_pop B -> Root", "dialog_close D", "on_close D", "nav_release B", "on_pop B",
		// only after the click returned: the dialog's body (LIFO), then the page
		"release flex", "release flex", "release button Leave", "release button Stay", "release label D",
		"release label B")
	testing.expect(t, mock.modal_after_close == nil && mock.views == 1)
}

// A push from a click whose page pushes another in its build: push's own flush shows it, after the
// first page and its dialog.
@(test)
test_push_from_click_flushes :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, c := Mock_Page{name = "Root"}, Mock_Page{name = "C"}
	d := Mock_Dialog{name = "D"}
	c_page := mock_page(&c)
	b := Mock_Page{name = "B", push = &c_page, dialog = &d}
	mock_launch(&root)
	callback_enter()
	push(mock_page(&b))
	expect_log(t, "build B", "label_init B", "nav_push B", "label_init D", "flex_create Vertical 1", "dialog_show D",
		"build C", "label_init C", "dialog_set_hidden D true", "nav_push C")
	callback_exit()
	testing.expect(t, len(g_nav) == 3 && g_nav[2] == b.pushed && d.handle.page == b.handle)
}

// A push from a build (a deep link) waits until that page is shown, so pages stack in call order.
@(test)
test_push_from_build_waits :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	c := Mock_Page{name = "C"}
	c_page := mock_page(&c)
	b := Mock_Page{name = "B", push = &c_page}
	b_page := mock_page(&b)
	root := Mock_Page{name = "Root", push = &b_page}
	run(mock_page(&root))
	expect_log(t, "theme_apply_mode System", "build Root", "label_init Root", "nav_push Root",
		"build B", "label_init B", "nav_push B", "build C", "label_init C", "nav_push C")
	testing.expect(t, len(g_nav) == 3 && g_nav[1] == root.pushed && g_nav[2] == b.pushed)
}

@(test)
test_pop_ignored :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root := Mock_Page{name = "Root", pop = true} // inside its own build: ignored
	run(mock_page(&root))
	expect_log(t, "theme_apply_mode System", "build Root", "label_init Root", "nav_push Root")

	nav_back_notify() // the root has no page to go back to
	callback_enter()
	pop()
	callback_exit()
	expect_log(t)

	b := Mock_Page{name = "B", pop = true}
	callback_enter()
	push(mock_page(&b))
	callback_exit()
	expect_log(t, "build B", "label_init B", "nav_push B")
	testing.expect_value(t, len(g_nav), 2)
}

// UIKit refuses a pop during a transition: the page stays, with its handle.
@(test)
test_refused_pop_keeps_page :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b := Mock_Page{name = "Root"}, Mock_Page{name = "B"}
	mock_launch(&root)
	callback_enter()
	push(mock_page(&b))
	mock_log_clear()
	mock.nav_pop_ok = false
	pop()
	expect_log(t, "nav_pop B -> Root")
	testing.expect(t, len(g_nav) == 2 && g_nav[1] == b.handle)

	mock.nav_pop_ok = true
	pop()
	callback_exit()
	expect_log(t, "nav_pop B -> Root", "nav_release B", "on_pop B", "release label B")
}

// A popped page's dialogs close before its scope is handed over, and the page below gets its
// dialogs back.
@(test)
test_pop_closes_dialogs_first :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b := Mock_Page{name = "Root"}, Mock_Page{name = "B"}
	r, d := Mock_Dialog{name = "R", modal = true}, Mock_Dialog{name = "D"}
	mock_launch(&root)
	callback_enter()
	mock_show(&r)
	push(mock_page(&b))
	mock_show(&d)
	callback_exit()
	expect_log(t, "label_init R", "flex_create Vertical 1", "dialog_show R", "build B", "label_init B",
		"dialog_set_hidden R true", "nav_push B", "label_init D", "flex_create Vertical 1", "dialog_show D")
	testing.expect(t, dialog_top_modal() == nil, "the root's modal dialog hides under B")

	callback_enter()
	pop()
	expect_log(t, "nav_pop B -> Root", "dialog_close D", "on_close D", "nav_release B", "on_pop B", "dialog_set_hidden R false")
	callback_exit()
	expect_log(t, "release flex", "release label D", "release label B")
	testing.expect(t, dialog_top_modal() == r.handle)
}

// page_set_title / page_set_actions reach the bar only once the page is shown, and not after its
// pop; an action may replace the actions that hold it.
@(test)
test_page_setters_wait_for_root :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root := Mock_Page{name = "Root", title = "Home", build_actions = {{title = "Add"}}}
	run(mock_page(&root))
	expect_log(t, "theme_apply_mode System", "build Root", "label_init Root", "nav_push Home")
	testing.expect(t, len(root.handle.actions) == 1 && root.handle.actions[0].action.title == "Add")

	replace :: proc(user: rawptr) {
		page_set_actions((^Page_Handle)(user), {{title = "Done"}})
	}
	page_set_title(root.handle, "Main")
	page_set_actions(root.handle, {{title = "Edit", on_click = replace, user = root.handle}})
	expect_log(t, "nav_title_changed Main", "nav_actions_changed 1")
	action_notify(root.handle.actions[0]) // frees the Action_Handle it runs from
	expect_log(t, "nav_actions_changed 1")
	testing.expect_value(t, root.handle.actions[0].action.title, "Done")

	b := Mock_Page{name = "B", pop_title = "Gone", pop_actions = {{title = "Gone"}}}
	callback_enter()
	push(mock_page(&b))
	pop()
	callback_exit()
	expect_log(t, "build B", "label_init B", "nav_push B", "nav_pop B -> Main", "nav_release B", "on_pop B", "release label B")
}

@(test)
test_dialog_in_build_waits_for_page :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	d := Mock_Dialog{name = "D"}
	root := Mock_Page{name = "Root", dialog = &d}
	run(mock_page(&root))
	expect_log(t, "theme_apply_mode System", "build Root", "label_init Root", "nav_push Root",
		"label_init D", "flex_create Vertical 1", "dialog_show D")
	testing.expect(t, d.handle.page == root.handle)
}

// The app's content belongs to the page, the title and the buttons to the dialog.
@(test)
test_dialog_content_belongs_to_page :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b := Mock_Page{name = "Root"}, Mock_Page{name = "B"}
	mock_launch(&root)
	callback_enter()
	push(mock_page(&b))
	content := label_create({text = "body"})
	mock_log_clear()
	d := Mock_Dialog{name = "D", content = view(content), buttons = {{title = "OK", on_click = mock_close_clicked}}}
	mock_show(&d)
	callback_exit()
	expect_log(t, "label_init D", "button_init OK", "flex_create Horizontal 1", "flex_create Vertical 3", "dialog_show D")

	button_notify(d.handle.buttons[0].handle)
	expect_log(t, "dialog_close D", "on_close D", "release flex", "release flex", "release button OK", "release label D")
	testing.expect_value(t, content.label.text, "body")

	callback_enter()
	pop()
	callback_exit()
	expect_log(t, "nav_pop B -> Root", "nav_release B", "on_pop B", "release label body", "release label B")
}

@(test)
test_dialog_closes_once :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	d := Mock_Dialog{name = "D", reclose = true}
	root := Mock_Page{name = "Root", dialog = &d, close_dialog = true}
	run(mock_page(&root)) // closed while pending: on_close runs, the dialog is never shown
	expect_log(t, "theme_apply_mode System", "build Root", "on_close D", "label_init Root", "nav_push Root")

	e := Mock_Dialog{name = "E", reclose = true}
	callback_enter()
	mock_show(&e)
	dialog_close(e.handle)
	callback_exit()
	expect_log(t, "label_init E", "flex_create Vertical 1", "dialog_show E", "dialog_close E", "on_close E", "release flex", "release label E")
	testing.expect_value(t, len(g_dialogs), 0)
}

@(test)
test_modal_blocks_back_and_actions :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root := Mock_Page{name = "Root"}
	b := Mock_Page{name = "B", actions = {{title = "Edit", on_click = mock_action_clicked}}}
	m := Mock_Dialog{name = "M", modal = true}
	mock_launch(&root)
	callback_enter()
	push(mock_page(&b))
	mock_show(&m)
	callback_exit()
	mock_log_clear()
	testing.expect(t, dialog_top_modal() == m.handle)

	nav_back_notify()
	action_notify(b.handle.actions[0])
	expect_log(t)

	callback_enter()
	dialog_close(m.handle)
	callback_exit()
	testing.expect(t, mock.modal_after_close == nil)
	action_notify(b.handle.actions[0])
	nav_back_notify()
	expect_log(t, "dialog_close M", "on_close M", "release flex", "release label M",
		"action", "nav_pop B -> Root", "nav_release B", "on_pop B", "release label B")
}

@(test)
test_retire_waits_for_outermost_callback :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	log_dispose :: proc(data: rawptr) {
		mock_log("dispose %d", int(uintptr(data)))
	}
	s := scope_new()
	g_scope_override = s
	for i in 1 ..= 3 do scope_on_dispose(log_dispose, rawptr(uintptr(i)))
	g_scope_override = nil

	callback_enter()
	callback_enter()
	scope_retire(s)
	callback_exit()
	expect_log(t) // an inner callback returned: the outer one may still use the scope
	callback_exit()
	expect_log(t, "dispose 3", "dispose 2", "dispose 1")
	scope_retire(nil)
}

// GTK, Windows and iOS retire a popped page's scope only once its views are really gone.
@(test)
test_retire_later :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	mock.retire = .Later
	root, b, c := Mock_Page{name = "Root"}, Mock_Page{name = "B"}, Mock_Page{name = "C"}
	mock_launch(&root)
	callback_enter()
	push(mock_page(&b))
	pop()
	callback_exit()
	expect_log(t, "build B", "label_init B", "nav_push B", "nav_pop B -> Root", "nav_release B", "on_pop B")
	testing.expect_value(t, b.label.label.text, "B")
	testing.expect_value(t, mock.views, 2)
	mock_retire_parked() // a GTK idle, after the slide
	expect_log(t, "release label B")

	callback_enter()
	push(mock_page(&c))
	pop()
	callback_exit()
	mock_log_clear()
	mock_retire_parked(bracketed = true) // iOS's didMoveToParentViewController:
	expect_log(t, "release label C")
}

// A pop the platform made (iOS back button or swipe) names its page: with a push queued behind it,
// that page is not the top of g_nav.
@(test)
test_system_pop_by_identity :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b, c := Mock_Page{name = "Root"}, Mock_Page{name = "B"}, Mock_Page{name = "C"}
	mock_launch(&root)
	callback_enter()
	push(mock_page(&b))
	ch := push(mock_page(&c))
	mock_log_clear()
	nav_system_pop_page(b.handle)
	expect_log(t, "nav_release B", "on_pop B")
	callback_exit()
	expect_log(t, "release label B")
	testing.expect(t, len(g_nav) == 2 && g_nav[1] == ch)
}

// set_allocator: nv_heap and the blocks of every scope come from the app's allocator, and a popped
// page's go back to it.
@(test)
test_set_allocator :: proc(t: ^testing.T) {
	Counts :: struct {
		allocs, frees: int,
	}
	counts: Counts
	counting := runtime.Allocator{
		procedure = proc(data: rawptr, mode: runtime.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, runtime.Allocator_Error) {
			c := (^Counts)(data)
			#partial switch mode {
			case .Alloc, .Alloc_Non_Zeroed: c.allocs += 1
			case .Free:                     c.frees += 1
			}
			return runtime.heap_allocator_proc(nil, mode, size, alignment, old_memory, old_size, loc)
		},
		data = rawptr(&counts), // cleared before the test returns
	}
	mock_begin(t)
	defer g_heap = {} // after mock_end, which frees the scopes into it
	defer mock_end(t)
	set_allocator(counting)
	root, b := Mock_Page{name = "Root"}, Mock_Page{name = "B"}
	run(mock_page(&root))
	testing.expect(t, counts.allocs > 0, "the root's scope and label text")
	before := counts
	callback_enter()
	push(mock_page(&b))
	pop()
	callback_exit()
	testing.expect(t, counts.allocs > before.allocs, "B's scope came from it")
	testing.expect(t, counts.frees > before.frees, "and went back to it")
}

// A page's widgets, one of each kind that calls the app, and how many calls reached it.
@(private = "file")
Widget_Page :: struct {
	button: ^Button_Handle,
	canvas: ^Canvas_Handle,
	input:  ^Input_Handle,
	list:   ^List_Handle,
	calls:  int,
}

@(private = "file")
widget_page_build :: proc(user: rawptr, page: ^Page_Handle) -> View {
	w := (^Widget_Page)(user)
	w.button = button_create({title = "Tap", user = w, on_click = proc(user: rawptr) { (^Widget_Page)(user).calls += 1 }})
	w.canvas = canvas_create({
		on_draw    = proc(user: rawptr, _: ^Painter, _, _: f64) { (^Widget_Page)(user).calls += 1 },
		on_pointer = proc(user: rawptr, _: Pointer, _, _: f64) { (^Widget_Page)(user).calls += 1 },
		on_scroll  = proc(user: rawptr, _, _: f64) { (^Widget_Page)(user).calls += 1 },
		user       = w,
	})
	w.input = input_create({user = w, on_change = proc(user: rawptr, _: string) { (^Widget_Page)(user).calls += 1 }})
	w.list = list_create({
		count     = proc(user: rawptr) -> int { (^Widget_Page)(user).calls += 1; return 3 },
		item      = proc(user: rawptr, _: int) -> Item { (^Widget_Page)(user).calls += 1; return {title = "row"} },
		on_select = proc(user: rawptr, _: int) { (^Widget_Page)(user).calls += 1 },
		user      = w,
	})
	return column_create({{view(w.button), 0}, {view(w.canvas), 1}, {view(w.input), 0}, {view(w.list), 1}})
}

// Every callback once, the way the backends report them.
@(private = "file")
widget_page_poke :: proc(w: ^Widget_Page) {
	button_notify(w.button)
	canvas_draw_notify(w.canvas, nil, 10, 10)
	canvas_pointer_notify(w.canvas, .Up, 1, 1)
	canvas_scroll_notify(w.canvas, 0, 5)
	input_notify(w.input, w.input.input.on_change)
	_ = list_count(w.list)
	_ = list_item(w.list, 0)
	list_select(w.list, 0)
}

// GTK's and iOS's slide: a popped page is still on screen, but its on_pop may have freed what its
// widgets' callbacks reach, so none reaches the app any more.
@(test)
test_popped_page_calls_nothing :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	mock.retire = .Later
	root := Mock_Page{name = "Root"}
	w: Widget_Page
	mock_launch(&root)
	callback_enter()
	push({title = "B", build = widget_page_build, user = &w})
	callback_exit()
	widget_page_poke(&w)
	testing.expect_value(t, w.calls, 8)

	callback_enter()
	pop()
	callback_exit()
	w.calls = 0
	widget_page_poke(&w)
	testing.expect_value(t, w.calls, 0)
	testing.expect_value(t, list_count(w.list), 3) // the rows it showed
	testing.expect_value(t, list_item(w.list, 0), Item{})
	mock_log_clear()
}

// The same for a dialog being taken down: a second click on its button does nothing.
@(test)
test_closed_dialog_calls_nothing :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	mock.retire = .Later
	root := Mock_Page{name = "Root"}
	d := Mock_Dialog{name = "D", buttons = {{title = "Close", on_click = proc(_: rawptr, d: ^Dialog_Handle) {
		mock_log("clicked")
		dialog_close(d)
	}}}}
	mock_launch(&root)
	callback_enter()
	mock_show(&d)
	callback_exit()
	button := d.handle.buttons[0].handle
	button_notify(button)
	mock_log_clear()
	button_notify(button) // before the platform took the dialog down
	expect_log(t)
}

// UIKit refuses a pop while a transition still runs: the page goes once it finished.
@(test)
test_refused_pop_waits_for_the_transition :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b := Mock_Page{name = "Root"}, Mock_Page{name = "B"}
	mock_launch(&root)
	callback_enter()
	push(mock_page(&b))
	mock.nav_pop_ok = false // B still slides in
	pop()
	callback_exit()
	testing.expect_value(t, len(g_nav), 2)
	mock_log_clear()

	mock.nav_pop_ok = true
	nav_transition_done()
	expect_log(t, "nav_pop B -> Root", "nav_release B", "on_pop B", "release label B")
	testing.expect_value(t, len(g_nav), 1)
	nav_transition_done() // nothing waits now
	expect_log(t)
}

// A waiting pop is dropped when its page went another way (a back swipe) before the transition
// ended: the next page is not popped in its place.
@(test)
test_refused_pop_dropped_when_page_went :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b, c := Mock_Page{name = "Root"}, Mock_Page{name = "B"}, Mock_Page{name = "C"}
	mock_launch(&root)
	callback_enter()
	push(mock_page(&b))
	mock.nav_pop_ok = false
	pop()
	callback_exit()
	mock.nav_pop_ok = true
	callback_enter()
	nav_system_pop() // the user swiped B away
	push(mock_page(&c))
	callback_exit()
	mock_log_clear()
	nav_transition_done()
	expect_log(t)
	testing.expect(t, len(g_nav) == 2 && g_nav[1].page.title == "C")
}

// Bar leading: set during build it waits for the push; later it reaches the backend for any shown
// page; nil keeps the view alive with its page.
Mock_Leading_Page :: struct {
	page:    ^Page_Handle,
	cluster: View,
}

@(test)
test_bar_leading_from_build_waits :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	lp: Mock_Leading_Page
	run({title = "Root", user = &lp, build = proc(user: rawptr, page: ^Page_Handle) -> View {
		lp := (^Mock_Leading_Page)(user)
		lp.page = page
		lp.cluster = view(label_create({text = "cluster"}))
		page_set_bar_leading(page, lp.cluster)
		return view(label_create({text = "body"}))
	}})
	expect_log(t, "theme_apply_mode System", "label_init cluster", "label_init body", "nav_push Root")
	testing.expect(t, lp.page.bar_leading == lp.cluster)
}

@(test)
test_bar_leading_set_clear_reset :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	lp: Mock_Leading_Page
	run({title = "Root", user = &lp, build = proc(user: rawptr, page: ^Page_Handle) -> View {
		lp := (^Mock_Leading_Page)(user)
		lp.page = page
		lp.cluster = view(label_create({text = "cluster"}))
		return view(label_create({text = "body"}))
	}})
	mock_log_clear()
	views := mock.views
	page_set_bar_leading(lp.page, lp.cluster)
	page_set_bar_leading(lp.page, nil)
	page_set_bar_leading(lp.page, lp.cluster)
	expect_log(t, "nav_leading_changed Root label cluster", "nav_leading_changed Root none", "nav_leading_changed Root label cluster")
	testing.expect_value(t, mock.views, views)
}

// A page below the top hears of it too (the backend decides what to show); a popped page's view
// dies with its scope.
@(test)
test_bar_leading_on_lower_page :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	lp: Mock_Leading_Page
	run({title = "Root", user = &lp, build = proc(user: rawptr, page: ^Page_Handle) -> View {
		lp := (^Mock_Leading_Page)(user)
		lp.page = page
		lp.cluster = view(label_create({text = "cluster"}))
		return view(label_create({text = "body"}))
	}})
	push({title = "Top", build = proc(user: rawptr, page: ^Page_Handle) -> View {
		page_set_bar_leading(page, view(label_create({text = "top cluster"})))
		return view(label_create({text = "top"}))
	}})
	mock_log_clear()
	page_set_bar_leading(lp.page, lp.cluster)
	expect_log(t, "nav_leading_changed Root label cluster")
	pop()
	testing.expect_value(t, mock.views, 2) // the root's cluster and body; the top page's two went
}

// on_covered: the page below hears true once the pushed page is shown, the page back on top false
// after a pop (the system's too); never the popped page, nor on the first show.
@(test)
test_on_covered :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b, c := Mock_Page{name = "Root", log_covered = true}, Mock_Page{name = "B", log_covered = true}, Mock_Page{name = "C", log_covered = true}
	run(mock_page(&root))
	expect_log(t, "theme_apply_mode System", "build Root", "label_init Root", "nav_push Root")

	callback_enter()
	push(mock_page(&b))
	pop()
	callback_exit()
	expect_log(t, "build B", "label_init B", "nav_push B", "covered Root",
		"nav_pop B -> Root", "nav_release B", "on_pop B", "uncovered Root", "release label B")

	cp := mock_page(&c)
	b.push = &cp // B's build pushes C: both covers come after their page is shown
	callback_enter()
	push(mock_page(&b))
	callback_exit()
	expect_log(t, "build B", "label_init B", "nav_push B", "covered Root", "build C", "label_init C", "nav_push C", "covered B")

	callback_enter() // the user swiped C away
	nav_system_pop()
	callback_exit()
	expect_log(t, "nav_release C", "on_pop C", "uncovered B", "release label C")

	callback_enter()
	push(cp)
	nav_system_pop_page(b.handle) // iOS: B went from under C, which stays on top
	callback_exit()
	expect_log(t, "build C", "label_init C", "nav_push C", "covered B", "nav_release B", "on_pop B", "release label B")
	testing.expect(t, len(g_nav) == 2 && g_nav[0].covered && !g_nav[1].covered)
}

// Dialog.build makes the content in the dialog's scope: its widgets go when the dialog closes,
// shown from a page's build (pending) and from a click alike; `content` stays the page's.
@(test)
test_dialog_build_belongs_to_dialog :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	d := Mock_Dialog{name = "D", build = true, buttons = {{title = "OK", on_click = mock_close_clicked}}}
	root := Mock_Page{name = "Root", dialog = &d}
	run(mock_page(&root))
	expect_log(t, "theme_apply_mode System", "build Root", "label_init Root", "nav_push Root",
		"label_init built", "label_init D", "button_init OK", "flex_create Horizontal 1", "flex_create Vertical 3", "dialog_show D")
	testing.expect_value(t, mock.views, 6)
	button_notify(d.handle.buttons[0].handle)
	expect_log(t, "dialog_close D", "on_close D", "release flex", "release flex", "release button OK", "release label D", "release label built")
	testing.expect_value(t, mock.views, 1)

	e := Mock_Dialog{name = "E", build = true, light = true}
	callback_enter()
	mock_show(&e)
	testing.expect(t, e.handle.title.label.style.color == DIALOG_LIGHT_TEXT && e.built.label.text == "built")
	dialog_close(e.handle)
	callback_exit()
	expect_log(t, "label_init built", "label_init E", "flex_create Vertical 2", "dialog_show E", "dialog_close E", "on_close E",
		"release flex", "release label E", "release label built")
	testing.expect_value(t, mock.views, 1)
}

// A tap on a dismissible dialog's scrim closes it; not on another modal one's, a hidden one's or a
// closed one's, and a non-modal one has no scrim.
@(test)
test_dismissible_dialog :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b := Mock_Page{name = "Root"}, Mock_Page{name = "B"}
	n := Mock_Dialog{name = "N", dismissible = true}
	e := Mock_Dialog{name = "E", modal = true}
	d := Mock_Dialog{name = "D", modal = true, dismissible = true}
	mock_launch(&root)
	callback_enter()
	mock_show(&n)
	mock_show(&e)
	callback_exit()
	testing.expect(t, n.handle.scrim == nil && e.handle.scrim != nil)
	mock_log_clear()
	dialog_scrim_notify(e.handle.scrim)
	dialog_scrim_notify(nil)
	expect_log(t)

	callback_enter()
	mock_show(&d)
	push(mock_page(&b))
	callback_exit()
	scrim := d.handle.scrim
	mock_log_clear()
	dialog_scrim_notify(scrim) // hidden under B
	expect_log(t)

	callback_enter()
	pop()
	callback_exit()
	mock_log_clear()
	dialog_scrim_notify(scrim)
	expect_log(t, "dialog_close D", "on_close D", "release flex", "release label D")
	testing.expect(t, len(g_dialogs) == 2 && dialog_top_modal() == e.handle && g_callback_depth == 0)
	dialog_scrim_notify(scrim) // closed
	expect_log(t)
}

@(test)
test_dialog_card_defaults :: proc(t: ^testing.T) {
	h: Dialog_Handle
	testing.expect(t, dialog_width(&h) == 320 && dialog_radius(&h, 12) == 12 && dialog_scrim(&h) == DIALOG_SCRIM)
	h.dialog = {width = 400, radius = 20, scrim = {0, 0, 0, 0.6}}
	testing.expect(t, dialog_width(&h) == 400 && dialog_radius(&h, 12) == 20 && dialog_scrim(&h) == {0, 0, 0, 0.6})
}
