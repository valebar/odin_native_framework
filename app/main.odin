package main

// Shared app code: identical on macOS, iOS, Android, Linux and Windows.
//
//   Column [ label, input, Expanded( Row [ Expanded(list, 1), Expanded(list2, 2) ] ) ]
//
// Typing in the input filters both lists down to the items whose number contains the text.

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
}

state := State{items = 10_000}

main :: proc() {
	nv.run("Native List", build, &state)
}

build :: proc(user: rawptr) -> nv.View {
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
			fmt.printfln("selected %d (cells created: %d + %d)", s.visible[index], s.list.cells_created, s.list2.cells_created)
		},
		row_height = 44,
		user = s,
	}
	s.list = nv.list_create(l)
	s.list2 = nv.list_create(l)

	s.filter = nv.input_create({
		placeholder = "Filter by number",
		on_change = proc(user: rawptr, text: string) {
			s := (^State)(user)
			apply_filter(s, text)
			nv.list_reload(s.list)
			nv.list_reload(s.list2)
		},
		on_submit = proc(user: rawptr, text: string) {
			s := (^State)(user)
			fmt.printfln("submitted %q: %d matches", text, len(s.visible))
		},
		user = s,
	})

	header := nv.label_create(fmt.tprintf("%d items, twice", s.items))
	lists := nv.row_create({{nv.list_view(s.list), 1}, {nv.list_view(s.list2), 2}}, spacing = 8)
	return nv.column_create({{header, 0}, {nv.input_view(s.filter), 0}, {lists, 1}}, spacing = 8)
}

apply_filter :: proc(s: ^State, text: string) {
	clear(&s.visible)
	buf: [32]byte
	for n in 0..<s.items {
		if strings.contains(strconv.write_int(buf[:], i64(n), 10), text) do append(&s.visible, n)
	}
}
