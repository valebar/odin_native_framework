package main

// The Scaffold page: three bottom tabs (the Profile tab is a Stack), a FAB that counts and shows a
// SnackBar with Undo (two lines on every third tap), and a drawer whose buttons switch tabs. A
// pushed page has a back button instead of the bar's menu button (as in Flutter), so the Home tab
// opens the drawer with a button.

import "core:fmt"
import nv "../nv"

Scaffold_Demo :: struct {
	scaffold: ^nv.Scaffold_Handle,
	count:    int,
	counter:  ^nv.Label_Handle,
	picks:    [3]Drawer_Pick, // what each drawer button selects
}

Drawer_Pick :: struct {
	d:   ^Scaffold_Demo,
	tab: int,
}

push_scaffold_demo :: proc() {
	nv.push({title = "Scaffold", build = scaffold_demo_build, user = new(Scaffold_Demo), on_pop = proc(user: rawptr) {
		free((^Scaffold_Demo)(user))
	}})
}

scaffold_demo_build :: proc(user: rawptr, page: ^nv.Page_Handle) -> nv.View {
	d := (^Scaffold_Demo)(user)
	d.counter = nv.label_create({text = "Tapped 0 times", heading = true})
	open := nv.button_create({title = "Open drawer", user = d, on_click = proc(user: rawptr) {
		nv.scaffold_open_drawer((^Scaffold_Demo)(user).scaffold)
	}})
	hint := nv.label_create({text = "The + button counts; Undo takes it back."})
	home := nv.container_create({
		padding = nv.insets_all(16),
		child   = nv.column_create({{nv.view(d.counter), 0}, {nv.view(hint), 0}, {nv.view(open), 0}, {nv.view(nv.container_create({})), 1}}, spacing = 12),
	})

	tab_page :: proc(text: string, color: nv.Color) -> nv.View {
		l := nv.label_create({text = text, heading = true})
		return nv.view(nv.container_create({child = nv.view(l), padding = nv.insets_all(24), color = color}))
	}

	drawer_button :: proc(d: ^Scaffold_Demo, title: string, tab: int) -> nv.Flex_Child {
		d.picks[tab] = {d, tab}
		b := nv.button_create({title = title, user = &d.picks[tab], on_click = proc(user: rawptr) {
			p := (^Drawer_Pick)(user)
			nv.scaffold_set_tab(p.d.scaffold, p.tab)
			nv.scaffold_close_drawer(p.d.scaffold)
		}})
		return {nv.view(b), 0}
	}
	drawer := nv.container_create({
		padding = nv.insets_all(16),
		child = nv.column_create({
			{nv.view(nv.label_create({text = "Menu", heading = true})), 0},
			drawer_button(d, "Home", 0), drawer_button(d, "Favorites", 1), drawer_button(d, "Profile", 2),
			{nv.view(nv.container_create({})), 1},
		}, spacing = 8),
	})

	d.scaffold = nv.scaffold_create({
		tabs = {
			{title = "Home", icon = .Home, body = nv.view(home)},
			{title = "Favorites", icon = .Star, body = tab_page("Favorites", {1, 0.95, 0.8, 1})},
			{title = "Profile", icon = .Person, body = profile_stack()},
		},
		on_tab = proc(_: rawptr, index: int) { fmt.println("tab:", index) },
		fab = {icon = .Add, user = d, on_click = proc(user: rawptr) {
			d := (^Scaffold_Demo)(user)
			d.count += 1
			nv.label_set_text(d.counter, fmt.tprintf("Tapped %d times", d.count))
			msg := d.count % 3 == 0 ? fmt.tprintf("Count is %d\nA multiple of three", d.count) : fmt.tprintf("Count is %d", d.count)
			nv.scaffold_show_snackbar(d.scaffold, {message = msg, action = "Undo", user = d, on_action = proc(user: rawptr) {
				d := (^Scaffold_Demo)(user)
				d.count -= 1
				nv.label_set_text(d.counter, fmt.tprintf("Tapped %d times", d.count))
				fmt.println("undo")
			}, color = d.count % 2 == 0 ? {0.1, 0.35, 0.3, 1} : {}}) // every other one tinted
		}},
		drawer = nv.view(drawer),
		user = d,
	})
	return nv.view(d.scaffold)
}

// A Stack: a tinted box filling the tab, a centered heading over it, a badge in the top-right
// corner and a caption at the bottom left.
profile_stack :: proc() -> nv.View {
	tint := nv.container_create({color = {0.85, 0.93, 1, 1}})
	name := nv.label_create({text = "Profile", heading = true})
	badge := nv.container_create({
		child = nv.view(nv.label_create({text = "NEW", style = {size = 12, weight = .Bold, color = {1, 1, 1, 1}}})),
		color = {0.85, 0.2, 0.3, 1}, radius = 10, padding = nv.insets_symmetric(8, 2),
	})
	caption := nv.label_create({text = "A Stack: fill, center, top-right and bottom-left children"})
	return nv.view(nv.stack_create({
		{view = nv.view(tint), h = .Fill, v = .Fill},
		{view = nv.view(name), h = .Center, v = .Center},
		{view = nv.view(badge), h = .End, v = .Start, margin = {0, 12, 12, 0}},
		{view = nv.view(caption), h = .Start, v = .End, margin = {16, 0, 0, 16}},
	}))
}
