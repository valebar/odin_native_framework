#+build-project-name nv
#+build !js
package nv

import "core:testing"

// A page whose body is a Layout around a Row of a fixed-width side and a pane, answering like a
// master-detail: wide shows the pane and sizes the side, narrow hides the pane.
Mock_Layout_Page :: struct {
	layout: ^Layout_Handle,
	side:   ^Container_Handle,
	pane:   View,
	calls:  [dynamic][2]f64,
	resize: f64, // > 0: the answer reports this width again from inside on_layout (Windows' re-entry)
	nested: bool,
}

mock_layout_page :: proc(p: ^Mock_Layout_Page) -> Page {
	return {title = "L", user = p, build = proc(user: rawptr, _: ^Page_Handle) -> View {
		p := (^Mock_Layout_Page)(user)
		p.side = container_create({child = view(label_create({text = "side"})), width = 100})
		p.pane = view(label_create({text = "pane"}))
		p.layout = layout_create({
			child = row_create({{view(p.side), 0}, {p.pane, 1}}),
			on_layout = proc(user: rawptr, width, height: f64) {
				p := (^Mock_Layout_Page)(user)
				append(&p.calls, [2]f64{width, height})
				wide := width >= 800
				view_set_hidden(p.pane, !wide)
				container_set_size(p.side, wide ? clamp(width * 0.33, 300, 480) : width, 0)
				if p.resize > 0 && !p.nested {
					p.nested = true
					mock_layout(p.layout, p.resize, height)
					p.nested = false
				}
			},
			user = p,
		})
		return view(p.layout)
	}}
}

@(test)
test_layout_reports_real_changes :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	p: Mock_Layout_Page
	defer delete(p.calls)
	run(mock_layout_page(&p))
	expect_log(t, "theme_apply_mode System", "label_init side", "container_init", "label_init pane", "flex_create Horizontal 2",
		"layout_init flex", "nav_push L")

	mock_layout(p.layout, 0, 0) // not laid out yet
	testing.expect_value(t, len(p.calls), 0)
	mock_layout(p.layout, 400, 300)
	mock_layout(p.layout, 400, 300) // the same size again
	testing.expect_value(t, len(p.calls), 1)
	mock_layout(p.layout, 0, 0) // hidden
	mock_layout(p.layout, 400, 300) // shown again at the last size
	testing.expect_value(t, len(p.calls), 1)
	mock_layout(p.layout, 900, 300)
	testing.expect_value(t, len(p.calls), 2)
	w, h := layout_size(p.layout)
	testing.expect(t, w == 900 && h == 300)
	testing.expect_value(t, g_callback_depth, 0)
}

// The answer hides, shows and resizes views; an unchanged size is not passed on to the backend.
@(test)
test_layout_answer_hides_and_resizes :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	p: Mock_Layout_Page
	defer delete(p.calls)
	run(mock_layout_page(&p))
	mock_log_clear()
	mock_layout(p.layout, 1000, 600)
	expect_log(t, "show label pane", "container_set_size 330 0")
	testing.expect(t, p.side.container.width == 330 && p.side.container.height == 0)
	mock_layout(p.layout, 1000, 700) // same width: same answer
	expect_log(t, "show label pane")
	mock_layout(p.layout, 500, 700)
	expect_log(t, "hide label pane", "container_set_size 500 0")
}

// A size reported again from inside on_layout runs once more after it, never nested; the same size is
// dropped.
@(test)
test_layout_reentry_runs_after :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	p: Mock_Layout_Page
	defer delete(p.calls)
	run(mock_layout_page(&p))
	p.resize = 1200
	mock_layout(p.layout, 900, 500)
	testing.expect_value(t, len(p.calls), 2)
	testing.expect(t, p.calls[0] == {900, 500} && p.calls[1] == {1200, 500})
	p.resize = 1200 // reported at the size it already has
	mock_layout(p.layout, 700, 500)
	testing.expect_value(t, len(p.calls), 4) // 700, then 1200 again (a new size by then)
	clear(&p.calls)
	p.resize = 0
	mock_layout(p.layout, 1200, 500)
	testing.expect_value(t, len(p.calls), 0)
}

// Two sizes that keep answering each other stop after LAYOUT_MAX_PASSES.
@(test)
test_layout_flip_flop_stops :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	Flip :: struct { layout: ^Layout_Handle, calls: int }
	f: Flip
	run({title = "F", user = &f, build = proc(user: rawptr, _: ^Page_Handle) -> View {
		f := (^Flip)(user)
		f.layout = layout_create({child = view(label_create({text = "x"})), user = f, on_layout = proc(user: rawptr, width, height: f64) {
			f := (^Flip)(user)
			f.calls += 1
			mock_layout(f.layout, width == 100 ? 200 : 100, height)
		}})
		return view(f.layout)
	}})
	mock_layout(f.layout, 100, 100)
	testing.expect_value(t, f.calls, LAYOUT_MAX_PASSES)
}

// A popped page's Layout calls nothing while its views still show (GTK's slide).
@(test)
test_popped_page_layout_calls_nothing :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	mock.retire = .Later
	run({title = "Root", build = proc(user: rawptr, _: ^Page_Handle) -> View { return view(label_create({text = "root"})) }})
	p: Mock_Layout_Page
	defer delete(p.calls)
	push(mock_layout_page(&p))
	pop()
	mock_layout(p.layout, 900, 300)
	testing.expect_value(t, len(p.calls), 0)
	mock_retire_parked()
}
