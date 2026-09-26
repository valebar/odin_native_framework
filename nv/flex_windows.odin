#+build windows
package nv

// Windows Row / Column backend. Win32 has no layout system, so an "NVFlex" window places its
// children itself on WM_SIZE: flex-0 children get their natural main-axis size (`measure`), flex
// children split the rest in exact proportion to their weights, and the cross axis stretches.

import "core:slice"
import win "core:sys/windows"

@(private) Flex_Data :: struct {
	axis:     Axis,
	spacing:  i32, // px
	children: []Flex_Child,
}

@(private)
_flex_create :: proc(f: Flex) -> View {
	box := win.CreateWindowExW(0, wstr(CLASS_FLEX), nil, win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, nil)
	d := new(Flex_Data)
	d^ = {f.axis, px(f.spacing), slice.clone(f.children)}
	for c in f.children do win.SetParent(win.HWND(c.view), box)
	win.SetWindowLongPtrW(box, win.GWLP_USERDATA, win.LONG_PTR(uintptr(d)))
	free_all(context.temp_allocator)
	return View(box)
}

@(private)
_label_create :: proc(text: string) -> View {
	label := win.CreateWindowExW(0, wstr("Static"), wstr(text),
		win.WS_CHILD | win.WS_VISIBLE | win.SS_LEFT | win.SS_NOPREFIX | win.SS_ENDELLIPSIS,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, nil)
	win.SendMessageW(label, win.WM_SETFONT, win.WPARAM(uintptr(g_windows.title)), 0)
	free_all(context.temp_allocator)
	return View(label)
}

@(private)
flex_data :: proc "contextless" (hwnd: win.HWND) -> ^Flex_Data {
	return (^Flex_Data)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
}

@(private)
flex_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = g_windows.ctx
	switch msg {
	case win.WM_SIZE:
		flex_layout(hwnd)
		free_all(context.temp_allocator)
		return 0
	case win.WM_CTLCOLORSTATIC:
		return ctlcolor_static(wparam)
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@(private)
flex_layout :: proc(hwnd: win.HWND) {
	d := flex_data(hwnd)
	if d == nil do return
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	size := [2]i32{rc.right, rc.bottom}
	main := int(d.axis) // .Horizontal lays out along x, .Vertical along y
	cross := 1 - main

	n := len(d.children)
	natural := make([]i32, n, context.temp_allocator)
	used := d.spacing * i32(max(n - 1, 0))
	total_flex := 0
	for c, i in d.children {
		if c.flex > 0 {
			total_flex += c.flex
		} else {
			natural[i] = measure(win.HWND(c.view))[main]
			used += natural[i]
		}
	}
	spare := max(size[main] - used, 0)

	pos, spent: i32
	flex_so_far := 0
	for c, i in d.children {
		length := natural[i]
		if c.flex > 0 {
			// Cumulative split, so the rounding error never adds up.
			flex_so_far += c.flex
			end := i32(i64(spare) * i64(flex_so_far) / i64(total_flex))
			length = end - spent
			spent = end
		}
		origin, extent: [2]i32
		origin[main] = pos
		extent[main] = length
		extent[cross] = size[cross]
		win.MoveWindow(win.HWND(c.view), origin.x, origin.y, extent.x, extent.y, true)
		pos += length + d.spacing
	}
}

// Natural size of a view in px: text extent for labels, one line for inputs, the stacked children
// for Row / Column, and 0 for anything else (a list has no natural size).
@(private)
measure :: proc(hwnd: win.HWND) -> [2]i32 {
	switch class_name(hwnd) {
	case CLASS_FLEX:
		d := flex_data(hwnd)
		main := int(d.axis)
		out: [2]i32
		for c, i in d.children {
			m := measure(win.HWND(c.view))
			out[main] += m[main] + (i > 0 ? d.spacing : 0)
			out[1 - main] = max(out[1 - main], m[1 - main])
		}
		return out
	case CLASS_INPUT:
		return input_measure()
	case "Static":
		buf: [256]u16
		n := win.GetWindowTextW(hwnd, &buf[0], len(buf))
		text, _ := win.utf16_to_utf8(buf[:n], context.temp_allocator)
		dc := win.GetDC(hwnd)
		defer win.ReleaseDC(hwnd, dc)
		font := win.HFONT(uintptr(win.SendMessageW(hwnd, win.WM_GETFONT, 0, 0)))
		sz := text_size(dc, font, text)
		return {sz.cx, sz.cy}
	}
	return {}
}
