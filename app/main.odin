package main

// Shared app code: identical on macOS, iOS, Android, Linux and Windows.
//
//   Column [ label, Row [ Expanded(input), button ], Expanded( Row [ Expanded(list, 1), Expanded(list2, 2) ], 2 ), Expanded(canvas, 1) ]
//
// Typing in the input filters both lists down to the items whose number contains the text.
// Dragging on the canvas draws strokes; the button clears the filter and the strokes. Selecting
// a row pushes a detail page, which can push another one or pop itself. The bar of the root page
// has Add and Info actions; a detail page's Edit action swaps itself for a Done action.

import "core:fmt"
import "core:strconv"
import "core:strings"
import nv "../nv"

State :: struct {
	items:   int,
	visible: [dynamic]int, // item numbers that match the filter
	list:    ^nv.List_Handle,
	list2:   ^nv.List_Handle,
	filter:  ^nv.Input_Handle,
	clear:   ^nv.Button_Handle,
	canvas:  ^nv.Canvas_Handle,
	strokes: [dynamic][dynamic][2]f64,
}

state := State{items = 10_000}

main :: proc() {
	nv.run("Native List", build, &state)
}

build :: proc(user: rawptr) -> nv.View {
	s := (^State)(user)
	apply_filter(s, "")

	// The root page has no Page struct, so its actions are set from its build.
	nv.page_set_actions({
		{title = "Add", icon = .Add, user = s, on_click = proc(user: rawptr) {
			push_detail((^State)(user), "New item", 1)
		}},
		{title = "Info", icon = .Info, user = s, on_click = proc(user: rawptr) {
			s := (^State)(user)
			fmt.printfln("%d of %d items visible, %d strokes", len(s.visible), s.items, len(s.strokes))
		}},
	})

	l := nv.List{
		count = proc(user: rawptr) -> int {
			return len((^State)(user).visible)
		},
		item = proc(user: rawptr, index: int) -> nv.Item {
			n := (^State)(user).visible[index]
			return {
				title    = fmt.tprintf("Item %d", n),
				subtitle = fmt.tprintf("row %d", index),
			}
		},
		on_select = proc(user: rawptr, index: int) {
			s := (^State)(user)
			n := s.visible[index]
			fmt.printfln("selected %d (cells created: %d + %d)", n, s.list.cells_created, s.list2.cells_created)
			push_detail(s, fmt.tprintf("Item %d", n), 1)
		},
		row_height = 44,
		user = s,
	}
	s.list = nv.list_create(l)
	s.list2 = nv.list_create(l)

	s.filter = nv.input_create({
		placeholder = "Filter by number",
		on_change = proc(user: rawptr, text: string) {
			set_filter((^State)(user), text)
		},
		on_submit = proc(user: rawptr, text: string) {
			s := (^State)(user)
			fmt.printfln("submitted %q: %d matches", text, len(s.visible))
		},
		user = s,
	})

	s.clear = nv.button_create({
		title = "Clear",
		on_click = proc(user: rawptr) {
			s := (^State)(user)
			nv.input_set_text(s.filter, "")
			set_filter(s, "")
			for st in s.strokes do delete(st)
			clear(&s.strokes)
			nv.canvas_redraw(s.canvas)
		},
		user = s,
	})

	s.canvas = nv.canvas_create({
		on_draw = draw_canvas,
		on_pointer = proc(user: rawptr, kind: nv.Pointer, x, y: f64) {
			s := (^State)(user)
			if kind == .Down do append(&s.strokes, [dynamic][2]f64{})
			if len(s.strokes) > 0 do append(&s.strokes[len(s.strokes) - 1], [2]f64{x, y})
			nv.canvas_redraw(s.canvas)
		},
		user = s,
	})

	header := nv.label_create(fmt.tprintf("%d items, twice", s.items))
	lists := nv.row_create({{nv.list_view(s.list), 1}, {nv.list_view(s.list2), 2}}, spacing = 8)
	search := nv.row_create({{nv.input_view(s.filter), 1}, {nv.button_view(s.clear), 0}}, spacing = 8)
	return nv.column_create({{header, 0}, {search, 0}, {lists, 2}, {nv.canvas_view(s.canvas), 1}}, spacing = 8)
}

// One pushed page. The title is cloned because the page outlives the callback that pushed it.
// Its widget handles are leaked on pop, like the root page's: handles have no destroy yet.
Detail :: struct {
	s:     ^State,
	title: string,
	level: int,
	more:  ^nv.Button_Handle,
	back:  ^nv.Button_Handle,
}

push_detail :: proc(s: ^State, title: string, level: int) {
	d := new(Detail)
	d.s = s
	d.title = strings.clone(title)
	d.level = level
	nv.push({title = d.title, build = detail_build, user = d, on_pop = detail_free, actions = edit_actions})
}

// Edit swaps the bar's action for Done, which swaps it back: the runtime path of page_set_actions.
edit_actions := []nv.Action{{title = "Edit", on_click = proc(user: rawptr) {
	fmt.println("editing")
	nv.page_set_actions(done_actions)
}}}

done_actions := []nv.Action{{title = "Done", icon = .Done, on_click = proc(user: rawptr) {
	fmt.println("done editing")
	nv.page_set_actions(edit_actions)
}}}

detail_build :: proc(user: rawptr) -> nv.View {
	d := (^Detail)(user)
	label := nv.label_create(fmt.tprintf("%s, level %d", d.title, d.level))
	d.more = nv.button_create({
		title = "Push another",
		on_click = proc(user: rawptr) {
			d := (^Detail)(user)
			push_detail(d.s, d.title, d.level + 1)
		},
		user = d,
	})
	d.back = nv.button_create({
		title = "Back",
		on_click = proc(user: rawptr) {
			nv.pop()
		},
		user = d,
	})
	return nv.column_create({{label, 0}, {nv.button_view(d.more), 0}, {nv.button_view(d.back), 0}}, spacing = 8)
}

detail_free :: proc(user: rawptr) {
	d := (^Detail)(user)
	fmt.printfln("popped %q, level %d", d.title, d.level)
	delete(d.title)
	free(d)
}

draw_canvas :: proc(user: rawptr, p: ^nv.Painter, w, h: f64) {
	s := (^State)(user)
	nv.fill_rect(p, 0, 0, w, h, {0.96, 0.96, 0.98, 1})
	nv.stroke_rect(p, 0.5, 0.5, w - 1, h - 1, {0.7, 0.7, 0.75, 1})
	nv.fill_ellipse(p, w - 60, 12, 44, 44, {1, 0.6, 0.2, 1})
	nv.stroke_ellipse(p, w - 60, 12, 44, 44, {0.6, 0.3, 0, 1}, 2)
	nv.draw_text(p, fmt.tprintf("Draw here (%d strokes)", len(s.strokes)), 12, 12, 15, {0.3, 0.3, 0.35, 1})
	for st in s.strokes {
		for i in 1..<len(st) do nv.draw_line(p, st[i-1].x, st[i-1].y, st[i].x, st[i].y, {0.1, 0.3, 0.9, 1}, 3)
	}
}

set_filter :: proc(s: ^State, text: string) {
	apply_filter(s, text)
	nv.list_reload(s.list)
	nv.list_reload(s.list2)
}

apply_filter :: proc(s: ^State, text: string) {
	clear(&s.visible)
	buf: [32]byte
	for n in 0..<s.items {
		if strings.contains(strconv.write_int(buf[:], i64(n), 10), text) do append(&s.visible, n)
	}
}
