#+build-project-name nv
#+build !js
package nv

import "core:fmt"
import "core:testing"

Mock_Scroll :: struct {
	canvas: ^Canvas_Handle,
	calls:  int,
	dx, dy: f64,
	depth:  int,
}

mock_scroll_page :: proc(page: ^Page_Handle, user: rawptr) -> View {
	ms := (^Mock_Scroll)(user)
	ms.canvas = canvas_create({
		on_draw = proc(user: rawptr, p: ^Painter, width, height: f64) {},
		on_scroll = proc(user: rawptr, dx, dy: f64) {
			ms := (^Mock_Scroll)(user)
			ms.calls += 1
			ms.dx += dx
			ms.dy += dy
			ms.depth = g_callback_depth
		},
		user = ms,
	})
	return canvas_view(ms.canvas)
}

@(test)
test_canvas_scroll :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms: Mock_Scroll
	run({title = "C", build = mock_scroll_page, user_data = &ms})
	canvas_scroll_notify(ms.canvas, 0, SCROLL_LINE)
	canvas_scroll_notify(ms.canvas, 0, 0) // nothing to report
	canvas_scroll_notify(ms.canvas, -3, 2)
	testing.expect_value(t, ms.calls, 2)
	testing.expect_value(t, ms.dx, -3)
	testing.expect_value(t, ms.dy, SCROLL_LINE + 2)
	testing.expect_value(t, ms.depth, 1) // bracketed like every callback
	testing.expect_value(t, g_callback_depth, 0)

	ms.canvas.canvas.on_scroll = nil // optional
	canvas_scroll_notify(ms.canvas, 0, 10)
	testing.expect_value(t, ms.calls, 2)
}

@(test)
test_view_set_hidden :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	run({title = "H", build = proc(page: ^Page_Handle, user: rawptr) -> View {
		return label_view(label_create({text = "a"}))
	}})
	mock_log_clear()
	v := g_nav[0].root
	view_set_hidden(v, true)
	view_set_hidden(v, false)
	expect_log(t, fmt.tprintf("hide %s", mock_view_name(v)), fmt.tprintf("show %s", mock_view_name(v)))
}
