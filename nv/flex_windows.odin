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
	d := scope_new_in(Flex_Data) // lives as long as the page: its scope dies after the window
	d^ = {f.axis, px(f.spacing), slice.clone(f.children, scope_allocator(scope_current()))}
	for c in f.children do win.SetParent(win.HWND(c.view), box)
	win.SetWindowLongPtrW(box, win.GWLP_USERDATA, win.LONG_PTR(uintptr(d)))
	return View(box)
}

// A single-line Static in `font` (label_windows.odin and the navigation bar's title); `style` adds
// to the label styles (the navigation bar centers its title vertically with SS_CENTERIMAGE).
@(private)
label_new :: proc(text: string, parent: win.HWND, style: win.DWORD, font: win.HFONT) -> win.HWND {
	label := win.CreateWindowExW(0, wstr("Static"), wstr(text),
		win.WS_CHILD | win.SS_LEFT | win.SS_NOPREFIX | win.SS_ENDELLIPSIS | style,
		0, 0, 0, 0, parent, nil, g_windows.hinstance, nil)
	win.SendMessageW(label, win.WM_SETFONT, win.WPARAM(uintptr(font)), 0)
	return label
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
		// Nested Row / Column get their WM_SIZE inside this layout's MoveWindow calls.
		callback_enter()
		defer callback_exit()
		flex_layout(hwnd)
		return 0
	case win.WM_CTLCOLORSTATIC:
		return ctlcolor_static(wparam, lparam)
	case win.WM_CTLCOLORBTN:
		return ctlcolor_button(lparam)
	case win.WM_ERASEBKGND: // no class brush: the page background, or a container's fill
		return erase_background(hwnd, win.HDC(wparam))
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

// Lays out again every Row / Column that contains `hwnd`, innermost first, after its natural size
// changed. Layout only runs on WM_SIZE, and nothing sends one when a control's content changes.
@(private)
flex_relayout_ancestors :: proc(hwnd: win.HWND) {
	for p := win.GetParent(hwnd); p != nil; p = win.GetParent(p) {
		if class_name(p) == CLASS_FLEX do flex_layout(p)
	}
}

// Natural size of a view in px: text extent for labels, one line for inputs, the title for buttons,
// the bitmap (or the given size) for images, the stacked children for Row / Column, the child plus
// the insets (or the given size) for a container, and 0 for anything else (a list or canvas has no natural size).
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
		return input_measure(hwnd)
	case CLASS_BUTTON:
		return button_measure(hwnd)
	case CLASS_IMAGE:
		return image_measure(hwnd)
	case CLASS_CONTAINER:
		return container_measure(hwnd)
	case CLASS_NAV: // fills whatever it gets, like a list
		return {}
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
