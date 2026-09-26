package main

// Shared app code: identical on macOS and iOS.

import "core:fmt"
import nv "../nv"

State :: struct {
	items: int,
	list:  ^nv.List_Handle,
}

state := State{items = 10_000}

main :: proc() {
	nv.run("Native List", build, &state)
}

build :: proc(user: rawptr) -> nv.View {
	s := (^State)(user)
	s.list = nv.list_create({
		count = proc(user: rawptr) -> int {
			return (^State)(user).items
		},
		row = proc(user: rawptr, index: int) -> nv.Row {
			return {
				title    = fmt.tprintf("Item %d", index),
				subtitle = fmt.tprintf("row %d", index),
			}
		},
		on_select = proc(user: rawptr, index: int) {
			s := (^State)(user)
			fmt.printfln("selected %d (cells created: %d)", index, s.list.cells_created)
		},
		row_height = 44,
		user = s,
	})
	return nv.list_view(s.list)
}
