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

mock_scroll_page :: proc(user: rawptr, page: ^Page_Handle) -> View {
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
	return view(ms.canvas)
}

@(test)
test_canvas_scroll :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	ms: Mock_Scroll
	run({title = "C", build = mock_scroll_page, user = &ms})
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

Mock_Gestures :: struct {
	canvas:   ^Canvas_Handle,
	pointers: int,
	scales:   [dynamic]Pointer,
	scale:    f64,
	mods:     Modifiers,
	source:   Scroll_Source,
}

// A pinch holds the pointer back until it ends; modifiers() is the event's during its callback
// only; on_scroll can ask where the scroll came from.
@(test)
test_canvas_scale_and_modifiers :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	mg: Mock_Gestures
	defer delete(mg.scales)
	run({title = "G", user = &mg, build = proc(user: rawptr, _: ^Page_Handle) -> View {
		mg := (^Mock_Gestures)(user)
		mg.canvas = canvas_create({
			on_draw = proc(_: rawptr, _: ^Painter, _, _: f64) {},
			on_pointer = proc(user: rawptr, kind: Pointer, x, y: f64) {
				mg := (^Mock_Gestures)(user)
				mg.pointers += 1
				mg.mods = modifiers()
			},
			on_scroll = proc(user: rawptr, dx, dy: f64) {
				mg := (^Mock_Gestures)(user)
				mg.source = canvas_scroll_source(mg.canvas)
				mg.mods = modifiers()
			},
			on_scale = proc(user: rawptr, kind: Pointer, scale, vscale, fx, fy: f64) {
				mg := (^Mock_Gestures)(user)
				append(&mg.scales, kind)
				mg.scale = scale
			},
			user = mg,
		})
		return view(mg.canvas)
	}})
	h := mg.canvas
	canvas_pointer_notify(h, .Down, 1, 1, {.Ctrl})
	testing.expect_value(t, mg.mods, Modifiers{.Ctrl})
	testing.expect_value(t, modifiers(), Modifiers{})
	canvas_scale_notify(h, .Move, 2, 2, 0, 0) // no pinch began
	testing.expect_value(t, len(mg.scales), 0)
	canvas_scale_notify(h, .Down, 1, 1, 5, 5)
	canvas_pointer_notify(h, .Move, 2, 2) // held back
	canvas_scale_notify(h, .Move, 1.5, 1, 5, 5)
	canvas_scale_notify(h, .Up, 1.5, 1, 5, 5)
	canvas_pointer_notify(h, .Up, 3, 3)
	testing.expect_value(t, mg.pointers, 2)
	testing.expect(t, len(mg.scales) == 3 && mg.scales[0] == .Down && mg.scales[2] == .Up)
	testing.expect_value(t, mg.scale, 1.5)
	canvas_scroll_notify(h, 0, 4, {7, 8, true, true}, {.Shift})
	testing.expect_value(t, mg.source, Scroll_Source{7, 8, true, true})
	testing.expect_value(t, mg.mods, Modifiers{.Shift})
}

@(test)
test_view_set_hidden :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	run({title = "H", build = proc(user: rawptr, page: ^Page_Handle) -> View {
		return view(label_create({text = "a"}))
	}})
	mock_log_clear()
	v := g_nav[0].root
	view_set_hidden(v, true)
	view_set_hidden(v, false)
	expect_log(t, fmt.tprintf("hide %s", mock_view_name(v)), fmt.tprintf("show %s", mock_view_name(v)))
}

// Polylines need two points; clips nest, a stray pop does nothing and what on_draw leaves pushed
// is popped after it.
@(test)
test_polyline_and_clips :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	h: ^Canvas_Handle
	run({title = "C", user = &h, build = proc(user: rawptr, _: ^Page_Handle) -> View {
		(^^Canvas_Handle)(user)^ = canvas_create({on_draw = proc(_: rawptr, p: ^Painter, w, h: f64) {
			clip_pop(p) // none pushed
			stroke_polyline(p, {{0, 0}}, {1, 0, 0, 1}) // one point
			clip_push(p, 0, 0, w, h)
			clip_push(p, 1, 2, 3, 4)
			stroke_polyline(p, {{0, 0}, {5, 5}, {10, 0}}, {1, 0, 0, 1}, 2)
			clip_pop(p)
			clip_push(p, 5, 5, 1, 1) // left pushed with the outer one
		}})
		return view((^^Canvas_Handle)(user)^)
	}})
	mock_log_clear()
	canvas_draw_notify(h, nil, 100, 50)
	expect_log(t, "clip_push 0 0 100 50", "clip_push 1 2 3 4", "stroke_polyline 3 2", "clip_pop", "clip_push 5 5 1 1", "clip_pop", "clip_pop")
}

// Polygons need three points.
@(test)
test_fill_polygon :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	h: ^Canvas_Handle
	run({title = "P", user = &h, build = proc(user: rawptr, _: ^Page_Handle) -> View {
		(^^Canvas_Handle)(user)^ = canvas_create({on_draw = proc(_: rawptr, p: ^Painter, w, h: f64) {
			fill_polygon(p, {{0, 0}, {5, 5}}, {1, 0, 0, 1}) // two points
			fill_polygon(p, {{0, 0}, {5, 5}, {10, 0}}, {1, 0, 0, 1})
		}})
		return view((^^Canvas_Handle)(user)^)
	}})
	mock_log_clear()
	canvas_draw_notify(h, nil, 100, 50)
	expect_log(t, "fill_polygon 3")
}
