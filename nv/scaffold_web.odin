#+build js
package nv

// Web scaffold backend. The overlay is a one-cell grid (.nv-overlay, nv.css): the base and the
// children that size it share the cell, placed by justify-self / align-self and margins; the others
// (the FAB, the SnackBar, the scrim, the drawer) are absolutely placed layers that size nothing.
// Every child is positioned, so the paint order is the add order. The scrim and the FAB report a
// click; the tab bar is a row of buttons; the timer is setTimeout. Hidden is `display: none`, and
// a disabled subtree is `inert` (no pointer, focus or keyboard).

import "core:fmt"

@(private)
_view_set_hidden :: proc(v: View, hidden: bool) {
	js_hidden(web_id(v), b32(hidden))
}

@(private)
_view_set_enabled :: proc(v: View, enabled: bool) {
	js_inert(web_id(v), b32(!enabled))
}

@(private)
_overlay_init :: proc(h: ^Overlay_Handle) {
	root := web_create("div", "nv-overlay")
	h.root = web_view(root)
	js_append(root, web_id(h.base))
	_overlay_place(h, h.base, {h = .Fill, v = .Fill, sizes = true})
}

@(private)
_overlay_add :: proc(h: ^Overlay_Handle, child: View, place: Overlay_Place) {
	js_append(web_id(h.root), web_id(child))
	_overlay_place(h, child, place)
}

@(private)
_overlay_place :: proc(h: ^Overlay_Handle, child: View, place: Overlay_Place) {
	c := web_id(child)
	m := place.margin
	js_class(c, "nv-abs", !place.sizes)
	if place.sizes {
		self :: proc(a: Align) -> string {
			switch a {
			case .Start:  return "start"
			case .Center: return "center"
			case .End:    return "end"
			case .Fill:   return "stretch"
			}
			return "stretch"
		}
		js_style(c, "justify-self", self(place.h))
		js_style(c, "align-self", self(place.v))
		js_style(c, "margin", web_insets(m))
	} else {
		// Offsets from the aligned edges; a centered axis is moved back by half its own size.
		edges :: proc(a: Align, near, far: f64) -> (start, end, shift: string) {
			switch a {
			case .Start:  return web_px(near), "auto", "0"
			case .Center: return "50%", "auto", "-50%"
			case .End:    return "auto", web_px(far), "0"
			case .Fill:   return web_px(near), web_px(far), "0"
			}
			return "0", "0", "0"
		}
		left, right, tx := edges(place.h, m.left, m.right)
		top, bottom, ty := edges(place.v, m.top, m.bottom)
		js_style(c, "left", left)
		js_style(c, "right", right)
		js_style(c, "top", top)
		js_style(c, "bottom", bottom)
		js_style(c, "transform", tx == "0" && ty == "0" ? "none" : fmt.tprintf("translate(%s, %s)", tx, ty))
	}
	// A size on a non-Fill axis; Fill clears a fixed natural size (nv-fw), so the child stretches.
	size :: proc(a: Align, v: f64) -> string {
		if a == .Fill do return "auto"
		return v > 0 ? web_px(v) : ""
	}
	js_style(c, "width", size(place.h, place.width))
	js_style(c, "height", size(place.v, place.height))
}

@(private)
_overlay_scrim_init :: proc(h: ^Overlay_Handle) {
	scrim := web_create("div", "nv-scrim nv-abs")
	js_listen(scrim, .Scrim, h, 0)
	js_append(web_id(h.root), scrim)
	h.scrim = web_view(scrim)
}

// A round icon button, or an extended one with the label; an icon-less round FAB shows Add.
@(private)
_fab_init :: proc(h: ^Fab_Handle) {
	f := &h.fab
	b := web_create("button", f.label == "" ? "nv-fab nv-round" : "nv-fab")
	js_attr(b, "type", "button")
	icon := f.icon
	if f.label == "" {
		if icon == .None do icon = .Add
		js_attr(b, "aria-label", fmt.tprint(icon))
	}
	if icon != .None do js_icon(b, i32(icon))
	if f.label != "" {
		text := web_create("span")
		js_text(text, f.label)
		js_append(b, text)
	}
	js_listen(b, .Fab, h, 0)
	h.root = web_view(b)
	h.control = rawptr(uintptr(b))
}

// The tab buttons in tab order (Tabbar_Handle.items, in the scope's arena).
@(private)
_tabbar_init :: proc(h: ^Tabbar_Handle) {
	bar := web_create("nav", "nv-tabbar")
	buttons := make([]Web_Id, len(h.tabs), scope_allocator(scope_current()))
	for t, i in h.tabs {
		b := web_create("button", "nv-tab")
		js_attr(b, "type", "button")
		if t.icon != .None do js_icon(b, i32(t.icon))
		title := web_create("span")
		js_text(title, t.title)
		js_append(b, title)
		js_listen(b, .Tab, h, i32(i))
		js_append(bar, b)
		buttons[i] = b
	}
	h.items = raw_data(buttons)
	h.root = web_view(bar)
	h.control = rawptr(uintptr(bar))
	_tabbar_select(h)
}

@(private)
_tabbar_select :: proc(h: ^Tabbar_Handle) {
	buttons := ([^]Web_Id)(h.items)
	for i in 0..<len(h.tabs) do js_class(buttons[i], "nv-selected", i == h.selected)
}

// The bar shows the new tab before on_tab runs (which may pop the page).
@(private)
web_tab_clicked :: proc(h: ^Tabbar_Handle, index: int) {
	if index == h.scaffold.tab do return
	buttons := ([^]Web_Id)(h.items)
	for i in 0..<len(h.tabs) do js_class(buttons[i], "nv-selected", i == index)
	tabbar_notify(h, index)
}

@(private)
_post_delayed :: proc(ms: int, t: ^Timer) {
	js_timeout(i32(max(ms, 0)), t)
}
