package main

// Shared app code: identical on macOS, iOS, Android, Linux and Windows.
//
//   Column [ label, Row [ Expanded(input), Clear, Tip ], Expanded( Row [ Expanded(list, 1), Expanded(list2, 2) ], 2 ), Expanded(canvas, 1) ]
//
// Typing in the input filters both lists down to the items whose number contains the text.
// Dragging on the canvas draws strokes; the Clear button clears the filter and the strokes; the
// Tip button opens a non-modal dialog over the page. Selecting a row pushes a detail page, which
// can push another one or pop itself after a modal confirm. The bar of the root page has Add, Ask (a modal dialog with
// an input that sets the filter) and Info actions; a detail page's Edit action swaps itself for a
// Done action and marks the title. The header label follows the filter. The canvas draws an image
// embedded in the binary; a detail page shows the same image as an asset file and a photo
// downloaded from the network.

import "core:fmt"
import "core:strconv"
import "core:strings"
import nv "../nv"

State :: struct {
	items:   int,
	visible: [dynamic]int, // item numbers that match the filter
	header:  ^nv.Label_Handle,
	list:    ^nv.List_Handle,
	list2:   ^nv.List_Handle,
	filter:  ^nv.Input_Handle,
	clear:   ^nv.Button_Handle,
	tip:     ^nv.Button_Handle,
	ask:     ^nv.Input_Handle, // the input inside the Ask dialog, while it is open
	canvas:  ^nv.Canvas_Handle,
	logo:    ^nv.Bitmap, // decoded from the bytes embedded below, drawn on the canvas
	strokes: [dynamic][dynamic][2]f64,
}

state := State{items = 10_000}

main :: proc() {
	nv.run({
		title = "Native List",
		build = build,
		user  = &state,
		actions = {
			{title = "Add", icon = .Add, user = &state, on_click = proc(user: rawptr) {
				push_detail((^State)(user), "New item", 1)
			}},
			{title = "Ask", icon = .Edit, user = &state, on_click = ask_filter},
			{title = "Info", icon = .Info, user = &state, on_click = proc(user: rawptr) {
				s := (^State)(user)
				fmt.printfln("%d of %d items visible, %d strokes", len(s.visible), s.items, len(s.strokes))
			}},
		},
	})
}

// A modal dialog with an input: Apply copies its text into the filter, Cancel just closes. Both
// close through the handle their callback gets; on_close runs after either.
ask_filter :: proc(user: rawptr) {
	s := (^State)(user)
	s.ask = nv.input_create({placeholder = "Digits", text = nv.input_text(s.filter, context.temp_allocator)})
	nv.dialog_show({
		title   = "Filter items",
		content = nv.input_view(s.ask),
		modal   = true,
		buttons = {
			{title = "Cancel", on_click = proc(d: ^nv.Dialog_Handle, _: rawptr) {
				nv.dialog_close(d)
			}},
			{title = "Apply", user = s, on_click = proc(d: ^nv.Dialog_Handle, user: rawptr) {
				s := (^State)(user)
				text := nv.input_text(s.ask, context.temp_allocator)
				nv.input_set_text(s.filter, text)
				set_filter(s, text)
				nv.dialog_close(d)
			}},
		},
		on_close = proc(user: rawptr) {
			(^State)(user).ask = nil
			fmt.println("ask closed")
		},
		user = s,
	})
}

// A non-modal dialog: the page underneath stays usable, and a pushed detail page hides it.
show_tip :: proc(user: rawptr) {
	msg := nv.label_create({text = "Type digits to filter both lists."})
	nv.dialog_show({
		title   = "Tip",
		content = nv.label_view(msg),
		buttons = {{title = "Got it", on_click = proc(d: ^nv.Dialog_Handle, _: rawptr) { nv.dialog_close(d) }}},
		on_close = proc(_: rawptr) { fmt.println("tip closed") },
	})
}

build :: proc(page: ^nv.Page_Handle, user: rawptr) -> nv.View {
	s := (^State)(user)
	apply_filter(s, "")

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
		item_height = 44,
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

	s.tip = nv.button_create({title = "Tip", on_click = show_tip, user = s})
	if s.logo == nil do s.logo = nv.bitmap_from_bytes(#load("assets/sample.png")) // kept across Android relaunches

	s.header = nv.label_create({text = header_text(s), bold = true})
	lists := nv.row_create({{nv.list_view(s.list), 1}, {nv.list_view(s.list2), 2}}, spacing = 8)
	search := nv.row_create({{nv.input_view(s.filter), 1}, {nv.button_view(s.clear), 0}, {nv.button_view(s.tip), 0}}, spacing = 8)
	return nv.column_create({{nv.label_view(s.header), 0}, {search, 0}, {lists, 2}, {nv.canvas_view(s.canvas), 1}}, spacing = 8)
}

header_text :: proc(s: ^State) -> string {
	return fmt.tprintf("%d of %d items, twice", len(s.visible), s.items)
}

// One pushed page. The title is cloned because the page outlives the callback that pushed it.
// Its widget handles are leaked on pop, like the root page's: handles have no destroy yet.
Detail :: struct {
	s:     ^State,
	page:  ^nv.Page_Handle, // valid until on_pop
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
	nv.push({
		title = d.title, build = detail_build, user = d, on_pop = detail_free,
		actions = {{title = "Edit", user = d, on_click = detail_edit}},
	})
}

// Edit swaps the bar's action for Done and marks the title; Done restores both: the runtime path
// of page_set_actions / page_set_title.
detail_edit :: proc(user: rawptr) {
	d := (^Detail)(user)
	fmt.println("editing")
	nv.page_set_title(d.page, fmt.tprintf("%s (editing)", d.title))
	nv.page_set_actions(d.page, {{title = "Done", icon = .Done, user = d, on_click = detail_done}})
}

detail_done :: proc(user: rawptr) {
	d := (^Detail)(user)
	fmt.println("done editing")
	nv.page_set_title(d.page, d.title)
	nv.page_set_actions(d.page, {{title = "Edit", user = d, on_click = detail_edit}})
}

detail_build :: proc(page: ^nv.Page_Handle, user: rawptr) -> nv.View {
	d := (^Detail)(user)
	d.page = page
	label := nv.label_create({text = fmt.tprintf("%s, level %d", d.title, d.level), bold = true})
	d.more = nv.button_create({
		title = "Push another",
		on_click = proc(user: rawptr) {
			d := (^Detail)(user)
			push_detail(d.s, d.title, d.level + 1)
		},
		user = d,
	})
	// A modal confirm on a pushed page. Leave pops the page, which closes the dialog (its on_close
	// runs first, while the page is still there); the header's back button is blocked meanwhile.
	d.back = nv.button_create({
		title = "Back",
		on_click = proc(user: rawptr) {
			nv.dialog_show({
				title   = "Leave page?",
				content = nv.label_view(nv.label_create({text = "Unsaved edits are lost."})),
				modal   = true,
				buttons = {
					{title = "Stay", on_click = proc(d: ^nv.Dialog_Handle, _: rawptr) { nv.dialog_close(d) }},
					{title = "Leave", on_click = proc(_: ^nv.Dialog_Handle, _: rawptr) { nv.pop() }},
				},
				on_close = proc(_: rawptr) { fmt.println("leave closed") },
			})
		},
		user = d,
	})
	// An asset file at a fixed size next to the label, and a download that fills the rest of the page.
	icon := nv.bitmap_from_file("sample.png")
	thumb := nv.image_create({bitmap = icon, width = 64, height = 48})
	nv.bitmap_free(icon) // the widget holds its own reference
	photo := nv.image_create({url = fmt.tprintf("https://picsum.photos/id/%d/600/400", 10 + d.level), fit = .Cover})
	header := nv.row_create({{nv.image_view(thumb), 0}, {nv.label_view(label), 1}}, spacing = 12)
	return nv.column_create({
		{header, 0}, {nv.button_view(d.more), 0}, {nv.button_view(d.back), 0}, {nv.image_view(photo), 1},
	}, spacing = 8)
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
	nv.draw_image(p, s.logo, w - 76, h - 57, 64, 48)
	nv.draw_text(p, fmt.tprintf("Draw here (%d strokes)", len(s.strokes)), 12, 12, 15, {0.3, 0.3, 0.35, 1})
	for st in s.strokes {
		for i in 1..<len(st) do nv.draw_line(p, st[i-1].x, st[i-1].y, st[i].x, st[i].y, {0.1, 0.3, 0.9, 1}, 3)
	}
}

set_filter :: proc(s: ^State, text: string) {
	apply_filter(s, text)
	nv.list_reload(s.list)
	nv.list_reload(s.list2)
	nv.label_set_text(s.header, header_text(s))
}

apply_filter :: proc(s: ^State, text: string) {
	clear(&s.visible)
	buf: [32]byte
	for n in 0..<s.items {
		if strings.contains(strconv.write_int(buf[:], i64(n), 10), text) do append(&s.visible, n)
	}
}
