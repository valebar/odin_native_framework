package main

// Shared app code: identical on macOS, iOS, Android and Linux.
//
//   Column [ label, Expanded( Row [ Expanded(list, 1), Expanded(list2, 2) ] ) ]

import "core:fmt"
import nv "../nv"

State :: struct {
	items: int,
	list:  ^nv.List_Handle,
	list2: ^nv.List_Handle,
}

state := State{items = 10_000}

main :: proc() {
	nv.run("Native List", build, &state)
}

build :: proc(user: rawptr) -> nv.View {
	s := (^State)(user)
	l := nv.List{
		count = proc(user: rawptr) -> int {
			return (^State)(user).items
		},
		item = proc(user: rawptr, index: int) -> nv.Item {
			return {
				title    = fmt.tprintf("Item %d", index),
				subtitle = fmt.tprintf("row %d", index),
			}
		},
		on_select = proc(user: rawptr, index: int) {
			s := (^State)(user)
			fmt.printfln("selected %d (cells created: %d + %d)", index, s.list.cells_created, s.list2.cells_created)
		},
		row_height = 44,
		user = s,
	}
	s.list = nv.list_create(l)
	s.list2 = nv.list_create(l)

	header := nv.label_create(fmt.tprintf("%d items, twice", s.items))
	lists := nv.row_create({{nv.list_view(s.list), 1}, {nv.list_view(s.list2), 2}}, spacing = 8)
	return nv.column_create({{header, 0}, {lists, 1}}, spacing = 8)
}
