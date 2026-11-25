#+build-project-name nv
#+build !js
package nv

import "core:testing"
import "core:thread"

Mock_Post :: struct {
	runs:  int,
	depth: int, // g_callback_depth inside fn
}

mock_post_worker :: proc(data: rawptr) {
	post_main(proc(data: rawptr) {
		p := (^Mock_Post)(data)
		p.runs += 1
		p.depth = g_callback_depth
	}, data)
}

@(test)
test_post_main_from_worker :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	run({title = "P", build = proc(page: ^Page_Handle, user: rawptr) -> View {
		return label_view(label_create({text = "body"}))
	}})
	mock_log_clear()
	p: Mock_Post
	th := thread.create_and_start_with_data(&p, mock_post_worker, context)
	thread.join(th)
	thread.destroy(th)
	expect_log(t, "post_timer")
	testing.expect(t, p.runs == 0, "post_main ran fn on the worker")
	mock_fire_timers()
	testing.expect_value(t, p.runs, 1)
	testing.expect_value(t, p.depth, 1)
	testing.expect_value(t, g_callback_depth, 0)
}
