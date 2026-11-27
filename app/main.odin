package main

// Shared app code: identical on macOS, iOS, Android, Linux and Windows.
//
//   Column [ label, Container( Row [ Expanded(input), Clear, Tip ] ), Expanded( Row [ Expanded(list, 1), Expanded(list2, 2) ], 2 ), Expanded(canvas, 1) ]
//
// The search row sits in a tinted, bordered, rounded Container; a detail page's header is a card
// (a Container with a margin) whose color changes while editing. Typing in the input filters both lists down to the items whose number contains the text.
// Dragging on the canvas draws strokes; the Clear button clears the filter and the strokes; the
// Tip button opens a non-modal dialog over the page. Selecting a row pushes a detail page, which
// can push another one or pop itself after a modal confirm. The bar of the root page has Add, Ask (a modal dialog with
// an input that sets the filter) and Info actions; a detail page's Edit action swaps itself for a
// Done action and marks the title. The header label follows the filter. The canvas draws an image
// embedded in the binary; a detail page shows the same image as an asset file and a photo
// downloaded from the network, plus a spinning progress and a determinate one stepped by a button. The header, the Tip button, the Ask dialog's input and the canvas
// text use a font loaded from an asset file (Tuffy Bold, public domain). The theme sets an accent
// and follows the OS light / dark; the Theme action cycles System → Light → Dark, and the canvas
// redraws with the palette on a flip. The Bench action pushes a page that times the canvas draw
// path over a fixed workload, and the Scaffold action a page with bottom tabs, a FAB, SnackBars and
// a drawer (scaffold_demo.odin). Strokes are polylines; the canvas also shows a swatch made from
// pixels, which every tap re-tints in place, clipped to a strip with a zigzag. The Ask dialog is
// light, builds its input itself (numeric keyboard, focused) and the root page logs being covered.

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"
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
	font:    ^nv.Font,   // loaded from an asset file; nil if it is missing, which means the system font
	strokes: [dynamic][dynamic][2]f64,
	swatch:  ^nv.Bitmap, // made from pixels; a tap on the canvas replaces them
	phase:   int,
}

main :: proc() {
	// On the heap, not main's stack: on Android `run` returns while the app keeps running. It lives
	// as long as the process, so it is never freed.
	state := new(State)
	state.items = 10_000
	nv.theme_set({
		accent  = {0, 0.55, 0.5, 1},
		heading = {weight = .Semibold},
		on_change = proc(user: rawptr) {
			s := (^State)(user)
			fmt.println("dark:", nv.theme_dark())
			if s.canvas != nil do nv.canvas_redraw(s.canvas)
		},
		user = state,
	})
	nv.run({
		title = "Native List",
		build = build,
		user = state,
		on_covered = proc(_: rawptr, covered: bool) {
			fmt.println("root covered:", covered)
		},
		actions = {
			{title = "Add", icon = .Add, user = state, on_click = proc(user: rawptr) {
				push_detail((^State)(user), "New item", 1)
			}},
			{title = "Ask", icon = .Edit, user = state, on_click = ask_filter},
			{title = "Info", icon = .Info, user = state, on_click = proc(user: rawptr) {
				s := (^State)(user)
				fmt.printfln("%d of %d items visible, %d strokes", len(s.visible), s.items, len(s.strokes))
			}},
			{title = "Bench", icon = .Refresh, user = state, on_click = proc(user: rawptr) {
				push_bench((^State)(user))
			}},
			{title = "Scaffold", icon = .Home, on_click = proc(_: rawptr) {
				push_scaffold_demo()
			}},
			{title = "Theme", icon = .Settings, on_click = proc(_: rawptr) {
				next := nv.Mode((int(nv.theme_mode()) + 1) % len(nv.Mode))
				fmt.println("theme mode:", next)
				nv.theme_set_mode(next)
			}},
		},
	})
}

// A light modal dialog with an input that `build` makes in the dialog's own scope (it goes when the
// dialog closes), with the numeric keyboard and the focus: Apply copies its text into the filter,
// Cancel just closes. Both close through the handle their callback gets; on_close runs after either.
ask_filter :: proc(user: rawptr) {
	s := (^State)(user)
	nv.dialog_show({
		title   = "Filter items",
		modal   = true,
		light   = true,
		width   = 360,
		radius  = 16,
		scrim   = {0, 0, 0.2, 0.5},
		build   = proc(user: rawptr, _: ^nv.Dialog_Handle) -> nv.View {
			s := (^State)(user)
			text := nv.input_text(s.filter, context.temp_allocator)
			s.ask = nv.input_create({placeholder = "Digits", text = text, keyboard = .Number, style = {font = s.font, size = 18}})
			return nv.view(s.ask)
		},
		buttons = {
			{title = "Cancel", on_click = proc(_: rawptr, d: ^nv.Dialog_Handle) {
				nv.dialog_close(d)
			}},
			{title = "Apply", user = s, on_click = proc(user: rawptr, d: ^nv.Dialog_Handle) {
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
	nv.input_focus(s.ask, select_all = true)
}

// A non-modal dialog: the page underneath stays usable, and a pushed detail page hides it.
show_tip :: proc(user: rawptr) {
	msg := nv.label_create({text = "Type digits to filter both lists."})
	nv.dialog_show({
		title   = "Tip",
		content = nv.view(msg),
		buttons = {{title = "Got it", on_click = proc(_: rawptr, d: ^nv.Dialog_Handle) { nv.dialog_close(d) }}},
		on_close = proc(_: rawptr) { fmt.println("tip closed") },
	})
}

build :: proc(user: rawptr, page: ^nv.Page_Handle) -> nv.View {
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
		style = {weight = .Semibold},
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
			if kind == .Down {
				append(&s.strokes, [dynamic][2]f64{})
				s.phase += 1
				nv.bitmap_set_rgba(s.swatch, swatch_pixels(s.phase))
			}
			if len(s.strokes) > 0 do append(&s.strokes[len(s.strokes) - 1], [2]f64{x, y})
			nv.canvas_redraw(s.canvas)
		},
		user = s,
	})

	if s.logo == nil do s.logo = nv.bitmap_from_bytes(#load("assets/sample.png")) // kept across Android relaunches
	if s.swatch == nil do s.swatch = nv.bitmap_from_rgba(SWATCH, SWATCH, swatch_pixels(s.phase))
	if s.font == nil {
		s.font = nv.font_from_file("tuffy_bold.ttf")
		if s.font == nil do fmt.println("tuffy_bold.ttf not found; using the system font")
	}
	s.tip = nv.button_create({title = "Tip", on_click = show_tip, user = s, style = {font = s.font}})

	s.header = nv.label_create({text = header_text(s), heading = true, style = {font = s.font, size = 22}})
	hint := nv.label_create({text = "Select a row for details", style = {size = 13, italic = true, color = {0, 0.55, 0.5, 1}}})
	lists := nv.row_create({{nv.view(s.list), 1}, {nv.view(s.list2), 2}}, spacing = 8)
	search := nv.row_create({{nv.view(s.filter), 1}, {nv.view(s.clear), 0}, {nv.view(s.tip), 0}}, spacing = 8)
	search_box := nv.container_create({
		child = search, padding = nv.insets_all(8), radius = 10,
		color = {0.93, 0.95, 1, 1}, border_color = {0.7, 0.75, 0.85, 1}, border_width = 1,
	})
	return nv.column_create({{nv.view(s.header), 0}, {nv.view(hint), 0}, {nv.view(search_box), 0}, {lists, 2}, {nv.view(s.canvas), 1}}, spacing = 8)
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
	card:  ^nv.Container_Handle, // the header card; tinted while editing
	done:  ^nv.Progress_Handle,  // determinate, stepped by its button
	steps: int, // tenths shown by done
}

CARD_COLOR    :: nv.Color{0.95, 0.93, 0.85, 1}
EDITING_COLOR :: nv.Color{1, 0.88, 0.6, 1}

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
	nv.container_set_color(d.card, EDITING_COLOR)
}

detail_done :: proc(user: rawptr) {
	d := (^Detail)(user)
	fmt.println("done editing")
	nv.page_set_title(d.page, d.title)
	nv.page_set_actions(d.page, {{title = "Edit", user = d, on_click = detail_edit}})
	nv.container_set_color(d.card, CARD_COLOR)
}

detail_build :: proc(user: rawptr, page: ^nv.Page_Handle) -> nv.View {
	d := (^Detail)(user)
	d.page = page
	label := nv.label_create({text = fmt.tprintf("%s, level %d", d.title, d.level), heading = true})
	d.more = nv.button_create({
		title = "Push another",
		on_click = proc(user: rawptr) {
			d := (^Detail)(user)
			push_detail(d.s, d.title, d.level + 1)
		},
		user = d,
	})
	// A modal confirm on a pushed page. Leave pops the page, which closes the dialog (its on_close
	// runs first, while the page is still there); the header's back button is blocked meanwhile. A
	// tap outside the card stays (dismissible).
	d.back = nv.button_create({
		title = "Back",
		on_click = proc(user: rawptr) {
			nv.dialog_show({
				title   = "Leave page?",
				content = nv.view(nv.label_create({text = "Unsaved edits are lost."})),
				modal   = true,
				dismissible = true,
				buttons = {
					{title = "Stay", on_click = proc(_: rawptr, d: ^nv.Dialog_Handle) { nv.dialog_close(d) }},
					{title = "Leave", on_click = proc(_: rawptr, _: ^nv.Dialog_Handle) { nv.pop() }},
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
	header := nv.row_create({{nv.view(thumb), 0}, {nv.view(label), 1}}, spacing = 12)
	d.card = nv.container_create({child = header, margin = {top = 4, bottom = 4}, padding = nv.insets_all(12), radius = 12, color = CARD_COLOR})
	// An indeterminate progress, and a determinate one with a track that its button steps by 10%.
	spinner := nv.progress_create({})
	d.done = nv.progress_create({value = f64(d.steps) / 10, track_color = {0.5, 0.5, 0.5, 0.25}})
	step := nv.button_create({
		title = "Step 10%",
		on_click = proc(user: rawptr) {
			d := (^Detail)(user)
			d.steps = (d.steps + 1) % 11
			nv.progress_set_value(d.done, f64(d.steps) / 10)
		},
		user = d,
	})
	progress := nv.row_create({{nv.view(spinner), 0}, {nv.view(d.done), 0}, {nv.view(step), 1}}, spacing = 12)
	return nv.column_create({
		{nv.view(d.card), 0}, {nv.view(d.more), 0}, {nv.view(d.back), 0}, {progress, 0}, {nv.view(photo), 1},
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
	pal := nv.theme_palette()
	nv.fill_rect(p, 0, 0, w, h, pal.surface)
	nv.stroke_rect(p, 0.5, 0.5, w - 1, h - 1, pal.separator)
	nv.fill_ellipse(p, w - 60, 12, 44, 44, {1, 0.6, 0.2, 1})
	nv.stroke_ellipse(p, w - 60, 12, 44, 44, {0.6, 0.3, 0, 1}, 2)
	nv.draw_image(p, s.logo, w - 76, h - 57, 64, 48)
	nv.draw_text(p, fmt.tprintf("Draw here (%d strokes)", len(s.strokes)), 12, 12, {color = pal.secondary_text, font = s.font})
	// The swatch and a zigzag, both cut to a strip.
	nv.clip_push(p, 12, 40, 140, 28)
	nv.draw_image(p, s.swatch, 12, 24, 140, 60)
	zigzag: [8][2]f64
	for &pt, i in zigzag do pt = {12 + f64(i) * 20, 40 + f64(i % 2) * 28}
	nv.stroke_polyline(p, zigzag[:], {1, 1, 1, 1}, 3)
	nv.clip_pop(p)
	for st in s.strokes do nv.stroke_polyline(p, st[:], pal.accent, 3)
}

SWATCH :: 32

// RGBA pixels with straight alpha: a ramp that `phase` shifts, fading towards the bottom.
swatch_pixels :: proc(phase: int) -> []u8 {
	px := make([]u8, SWATCH * SWATCH * 4, context.temp_allocator)
	for y in 0 ..< SWATCH do for x in 0 ..< SWATCH {
		i := (y * SWATCH + x) * 4
		px[i] = u8((x * 8 + phase * 40) % 256)
		px[i + 1] = u8(y * 8)
		px[i + 2] = u8(255 - x * 8)
		px[i + 3] = u8(255 - y * 4)
	}
	return px
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

// A page that times the canvas draw path: each button repaints a fixed workload for 60 frames and
// reports the average time spent inside `on_draw` (the draw calls themselves) and per frame (wall
// time, so it includes the platform's own rasterizing and compositing).
Bench :: struct {
	s:           ^State,
	kind:        Bench_Kind,
	frames_left: int,
	frames:      int,
	draw:        time.Duration, // inside on_draw's workload, summed
	start:       time.Tick,
	label:       ^nv.Label_Handle,
	canvas:      ^nv.Canvas_Handle,
}

Bench_Kind :: enum { Rects, Lines, Text, Mixed }
BENCH_FRAMES :: 60
BENCH_COLORS :: [4]nv.Color{{0.9, 0.3, 0.3, 1}, {0.3, 0.7, 0.4, 1}, {0.3, 0.5, 0.9, 1}, {0.9, 0.7, 0.2, 1}}

push_bench :: proc(s: ^State) {
	b := new(Bench)
	b.s = s
	nv.push({
		title = "Bench", build = bench_build, user = b,
		on_pop = proc(user: rawptr) { free((^Bench)(user)) },
	})
}

bench_build :: proc(user: rawptr, page: ^nv.Page_Handle) -> nv.View {
	b := (^Bench)(user)
	b.label = nv.label_create({text = "Pick a workload", heading = true})
	b.canvas = nv.canvas_create({on_draw = bench_draw, user = b})
	buttons: [len(Bench_Kind)]nv.Flex_Child
	for kind, i in Bench_Kind {
		// One proc per kind: a callback carries nothing but `user`.
		on_click: proc(user: rawptr)
		switch kind {
		case .Rects: on_click = proc(user: rawptr) { bench_start((^Bench)(user), .Rects) }
		case .Lines: on_click = proc(user: rawptr) { bench_start((^Bench)(user), .Lines) }
		case .Text:  on_click = proc(user: rawptr) { bench_start((^Bench)(user), .Text) }
		case .Mixed: on_click = proc(user: rawptr) { bench_start((^Bench)(user), .Mixed) }
		}
		button := nv.button_create({title = fmt.tprint(kind), user = b, on_click = on_click})
		buttons[i] = {nv.view(button), 1}
	}
	row := nv.row_create(buttons[:], spacing = 8)
	return nv.column_create({{nv.view(b.label), 0}, {row, 0}, {nv.view(b.canvas), 1}}, spacing = 8)
}

bench_start :: proc(b: ^Bench, kind: Bench_Kind) {
	b.kind = kind
	b.frames_left = BENCH_FRAMES
	b.frames = 0
	b.draw = 0
	b.start = time.tick_now()
	nv.canvas_redraw(b.canvas)
}

bench_draw :: proc(user: rawptr, p: ^nv.Painter, w, h: f64) {
	b := (^Bench)(user)
	pal := nv.theme_palette()
	nv.fill_rect(p, 0, 0, w, h, pal.surface)
	colors := BENCH_COLORS

	t0 := time.tick_now()
	switch b.kind {
	case .Rects:
		for i in 0..<2000 {
			x, y := f64(i % 50) * w / 50, f64(i / 50) * h / 40
			nv.fill_rect(p, x, y, w / 50 - 2, h / 40 - 2, colors[i % 4])
			nv.stroke_rect(p, x, y, w / 50 - 2, h / 40 - 2, colors[(i + 1) % 4])
		}
	case .Lines:
		for i in 0..<4000 {
			x, y := f64(i % 80) * w / 80, f64(i / 80) * h / 50
			nv.draw_line(p, x, y, x + w / 80, y + h / 50, colors[i % 4], 2)
		}
	case .Text:
		for i in 0..<300 {
			x, y := f64(i % 6) * w / 6, f64(i / 6) * h / 50
			style := nv.Text_Style{size = 12, color = colors[i % 4]}
			if i % 2 == 1 do style.font = b.s.font
			nv.draw_text(p, "Native views", x, y, style)
		}
	case .Mixed:
		for i in 0..<500 {
			x, y := f64(i % 25) * w / 25, f64(i / 25) * h / 20
			nv.fill_rect(p, x, y, w / 25 - 2, h / 20 - 2, colors[i % 4])
			nv.draw_line(p, x, y, x + w / 25, y + h / 20, colors[(i + 2) % 4], 2)
		}
		for i in 0..<100 {
			x, y := f64(i % 10) * w / 10, f64(i / 10) * h / 10
			nv.fill_ellipse(p, x, y, w / 10 - 4, h / 10 - 4, colors[(i + 1) % 4])
			nv.draw_text(p, "Mixed", x + 4, y + 4, {size = 12, font = i % 2 == 1 ? b.s.font : nil})
		}
		for i in 0..<50 do nv.draw_image(p, b.s.logo, f64(i % 10) * w / 10, f64(i / 10) * h / 5, 64, 48)
	}
	b.draw += time.tick_since(t0)
	b.frames += 1

	if b.frames_left > 0 {
		b.frames_left -= 1
		nv.canvas_redraw(b.canvas) // the next frame comes from the platform's paint cycle
		return
	}
	if b.frames == BENCH_FRAMES + 1 { // the run just finished (later static repaints are not counted)
		n := f64(b.frames)
		draw_ms := time.duration_milliseconds(b.draw) / n
		frame_ms := time.duration_milliseconds(time.tick_since(b.start)) / n
		summary := fmt.tprintf("%v: %d frames, draw %.2f ms, frame %.2f ms", b.kind, b.frames, draw_ms, frame_ms)
		fmt.println("bench", summary)
		nv.label_set_text(b.label, summary)
		b.frames += 1 // so a repaint after the run (the label relayout, a resize) leaves the result
	}
}
