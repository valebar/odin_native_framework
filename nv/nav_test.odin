#+build-project-name nv
package nv

// The core's page stack, dialogs and scopes against the mock backend (mock_test.odin). Each test
// starts with mock_begin(t) and ends with mock_end(t); callback_enter / callback_exit around a step
// stand for the native callback (a click) it runs in. Logs are exact and in order.

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
	d := Mock_Dialog{name = "D", content = label_view(content), buttons = {{title = "OK", on_click = mock_close_clicked}}}
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
