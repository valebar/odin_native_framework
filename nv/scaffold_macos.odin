#+build darwin:default
#+private
package nv

// macOS scaffold backend; the overlay, the visibility and the timer are shared (appkit.odin). The
// scrim is an NVScrimView (a layer-backed NSView) whose mouseDown: reports the click; AppKit
// sends an unhandled click up the responder chain, never to a sibling, so the page under it gets
// nothing. The FAB is a borderless NSButton, layer-backed with the accent fill and a 28pt corner
// radius, its SF Symbol tinted white. macOS has no bottom tab bar, so the tab bar is a strip with a
// top separator and a centered NSSegmentedControl (a label and a symbol per segment).

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"
import AK "vendor:darwin/AppKit"

@(private) scrim_class, fab_target_class, tab_target_class: NS.Class

// AppKit has no subtree switch: every control below `v` is enabled or disabled (nv has no per-widget
// enabled state to restore), and a first responder inside it resigns.
@(private)
_view_set_enabled :: proc(v: View, enabled: bool) {
	walk :: proc(v: ^NS.Object, enabled: bool) {
		if send(NS.BOOL, v, "respondsToSelector:", intrinsics.objc_find_selector("setEnabled:")) {
			send(nil, v, "setEnabled:", NS.BOOL(enabled))
		}
		subviews := send(^NS.Object, v, "subviews")
		for i in 0..<send(NS.UInteger, subviews, "count") do walk(send(^NS.Object, subviews, "objectAtIndex:", i), enabled)
	}
	root := (^NS.Object)(v)
	walk(root, enabled)
	if enabled do return
	first := send(^NS.Object, g_macos.window, "firstResponder")
	if first != nil && send(NS.BOOL, first, "isKindOfClass:", intrinsics.objc_find_class("NSView")) && send(NS.BOOL, first, "isDescendantOf:", root) {
		g_macos.window->makeFirstResponder(nil)
	}
}

// Owned by the current scope.
@(private)
scrim_new :: proc(h: ^Overlay_Handle) -> ^NS.Object {
	cls := objc_class(&scrim_class, "NVScrimView", "NSView", {
		{"mouseDown:", auto_cast scrim_mouse_down, "v@:@"},
	})
	v := objc_own(send(^AK.View, (^AK.View)(objc_alloc_with_handle(cls, h)), "initWithFrame:", NS.Rect{}))
	send(nil, v, "setWantsLayer:", NS.BOOL(true))
	send(nil, send(^NS.Object, v, "layer"), "setBackgroundColor:", send(rawptr, canvas_color({0, 0, 0, 0.4}), "CGColor"))
	return v
}

@(private)
scrim_mouse_down :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	h := objc_handle(self, Overlay_Handle)
	context = h.ctx
	overlay_scrim_notify(h)
}

@(private)
_fab_init :: proc(h: ^Fab_Handle) {
	cls := objc_class(&fab_target_class, "NVFabTarget", "NSObject", {
		{"nvFab:", auto_cast fab_clicked, "v@:@"},
	})
	t := objc_own(objc_alloc_with_handle(cls, h)) // the button's target is weak
	f := &h.fab
	action := intrinsics.objc_find_selector("nvFab:")
	image := fab_symbol(f.icon)
	button: ^Button_View
	switch {
	case f.title == "" && image != nil:
		button = send(^Button_View, Button_View, "buttonWithImage:target:action:", image, t, action)
	case image != nil:
		button = send(^Button_View, Button_View, "buttonWithTitle:image:target:action:", ns_string(f.title), image, t, action)
	case:
		button = button_push(ns_string(f.title), t, action)
	}
	objc_own(button)->retain() // autoreleased; *_init makes owned views
	send(nil, button, "setBordered:", NS.BOOL(false))
	send(nil, button, "setContentTintColor:", canvas_color({1, 1, 1, 1}))
	send(nil, button, "setWantsLayer:", NS.BOOL(true))
	fab_style(button, f.title != "", theme_palette().accent)
	if f.title != "" {
		send(nil, button, "sizeToFit") // the natural width plus Material's 20pt either side
		w := send(NS.Rect, button, "frame").size.width
		layout_anchor_constant(anchor_width(button), w + 40, 999)
	}
	h.root = View(button)
	h.control = button
	h.target = t
}

@(private)
fab_clicked :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	h := objc_handle(self, Fab_Handle)
	context = h.ctx
	fab_notify(h)
}

@(private) SEGMENT_SWITCH_TRACKING_SELECT_ONE :: NS.UInteger(0)
@(private) BOX_TYPE_SEPARATOR :: NS.Integer(2)

@(private)
_tabbar_init :: proc(h: ^Tabbar_Handle) {
	cls := objc_class(&tab_target_class, "NVTabTarget", "NSObject", {
		{"nvTab:", auto_cast tab_clicked, "v@:@"},
	})
	t := objc_own(objc_alloc_with_handle(cls, h))

	labels := make([]^NS.Object, len(h.tabs), context.temp_allocator)
	for tab, i in h.tabs do labels[i] = ns_string(tab.title)
	seg := send(^AK.View, objc_class_object("NSSegmentedControl"), "segmentedControlWithLabels:trackingMode:target:action:",
		array_with_objects(raw_data(labels), len(labels)), SEGMENT_SWITCH_TRACKING_SELECT_ONE, t, intrinsics.objc_find_selector("nvTab:"))
	for tab, i in h.tabs {
		if name := sf_symbol_names[tab.icon]; name != "" {
			send(nil, seg, "setImage:forSegment:", image_system_symbol(ns_string(name), ns_string(tab.title)), NS.Integer(i))
		}
	}
	send(nil, seg, "setSelectedSegment:", NS.Integer(h.selected))
	view_set_translates_autoresizing_mask(seg, false)

	bar := objc_own(AK.View.alloc()->initWithFrame({}))
	bar->addSubview(seg) // retains it; the control is autoreleased
	layout_anchor_equal(anchor_center_x(seg), anchor_center_x(bar))
	layout_anchor_equal_offset(anchor_top(seg), anchor_top(bar), 8)
	layout_anchor_equal_offset(anchor_bottom(bar), anchor_bottom(seg), 8)
	layout_anchor_at_most(anchor_width(seg), anchor_width(bar), -16)

	line := box_new({})
	send(nil, line, "setBoxType:", BOX_TYPE_SEPARATOR)
	view_set_translates_autoresizing_mask(line, false)
	bar->addSubview(line)
	line->release() // the bar owns it
	layout_anchor_equal(anchor_top(line), anchor_top(bar))
	layout_anchor_equal(anchor_leading(line), anchor_leading(bar))
	layout_anchor_equal(anchor_trailing(line), anchor_trailing(bar))
	layout_anchor_constant(anchor_height(line), 1, LAYOUT_PRIORITY_REQUIRED)

	h.root = View(bar)
	h.control = seg
	h.target = t
}

@(private)
_tabbar_select :: proc(h: ^Tabbar_Handle) {
	send(nil, (^NS.Object)(h.control), "setSelectedSegment:", NS.Integer(h.selected))
}

@(private)
tab_clicked :: proc "c" (self: NS.id, _: NS.SEL, sender: NS.id) {
	h := objc_handle(self, Tabbar_Handle)
	context = h.ctx
	tabbar_notify(h, int(send(NS.Integer, (^NS.Object)(sender), "selectedSegment")))
}
