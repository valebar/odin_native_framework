#+build darwin:ios
package nv

// iOS scaffold backend; the overlay, the visibility and the timer are shared (appkit.odin). The
// scrim is an NVScrimView (a UIView) whose touchesEnded:withEvent: reports the tap; a UIView
// takes the touches that land on it, so the page under it gets nothing. The FAB is a system
// UIButton with the accent background and a 28pt corner radius on its layer, its SF Symbol tinted
// white. The tab bar is a standalone UITabBar whose NVTabBarDelegate reports the selection; it sits
// at the bottom of the page's safe area, so it ends above the home indicator.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(private) scrim_class, fab_target_class, tab_delegate_class: NS.Class

// Owned by the current scope.
// The scrim already takes the touches; this keeps a hardware keyboard's focus off the page too.
@(private)
_view_set_enabled :: proc(v: View, enabled: bool) {
	send(nil, (^NS.Object)(v), "setUserInteractionEnabled:", NS.BOOL(enabled))
	if !enabled do send(NS.BOOL, (^NS.Object)(v), "endEditing:", NS.BOOL(true))
}

@(private)
scrim_new :: proc(h: ^Overlay_Handle) -> ^NS.Object {
	cls := objc_class(&scrim_class, "NVScrimView", "UIView", {
		{"touchesEnded:withEvent:", auto_cast scrim_touches_ended, "v@:@@"},
	})
	v := objc_own(send(^UI_View, (^UI_View)(objc_alloc_with_handle(cls, h)), "initWithFrame:", NS.Rect{}))
	ui_view_set_background_color(v, ui_color_with_white_alpha(0, 0.4))
	return v
}

@(private)
scrim_touches_ended :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id, _: NS.id) {
	h := objc_handle(self, Overlay_Handle)
	context = h.ctx
	overlay_scrim_notify(h)
}

@(private)
_fab_init :: proc(h: ^Fab_Handle) {
	cls := objc_class(&fab_target_class, "NVFabTarget", "NSObject", {
		{"nvFab:", auto_cast fab_clicked, "v@:@"},
	})
	t := objc_own(objc_alloc_with_handle(cls, h)) // not retained by the button
	f := &h.fab
	button := ui_button_system() // autoreleased
	objc_own(button)->retain()
	if image := fab_symbol(f.icon); image != nil do send(nil, button, "setImage:forState:", image, UI_CONTROL_STATE_NORMAL)
	if f.label != "" {
		ui_button_set_title(button, ns_string(f.label))
		send(nil, button, "setTitleColor:forState:", canvas_color({1, 1, 1, 1}), UI_CONTROL_STATE_NORMAL)
		// Material's 20pt either side of the content, and 8pt between the icon and the label.
		send(nil, button, "setContentEdgeInsets:", UI_Edge_Insets{0, 20, 0, 20})
		send(nil, button, "setTitleEdgeInsets:", UI_Edge_Insets{0, 8, 0, -8})
	}
	send(nil, button, "setTintColor:", canvas_color({1, 1, 1, 1}))
	fab_style(button, f.label != "", theme_palette().accent)
	ui_control_add_target(button, t, intrinsics.objc_find_selector("nvFab:"), UI_CONTROL_EVENT_TOUCH_UP_INSIDE)
	h.root = View(button)
	h.control = button
	h.target = t
}

// UIEdgeInsets: top, left, bottom, right.
@(private) UI_Edge_Insets :: struct { top, left, bottom, right: NS.Float }

@(private)
fab_clicked :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	h := objc_handle(self, Fab_Handle)
	context = h.ctx
	fab_notify(h)
}

// The items' tags are their indexes.
@(private)
_tabbar_init :: proc(h: ^Tabbar_Handle) {
	cls := objc_class(&tab_delegate_class, "NVTabBarDelegate", "NSObject", {
		{"tabBar:didSelectItem:", auto_cast tab_selected, "v@:@@"},
	}, {"UITabBarDelegate"})
	d := objc_own(objc_alloc_with_handle(cls, h))
	bar := objc_own(send(^UI_View, send(^UI_View, objc_class_object("UITabBar"), "alloc"), "initWithFrame:", NS.Rect{}))

	items := make([]^NS.Object, len(h.tabs), context.temp_allocator)
	for tab, i in h.tabs {
		image: ^UI_Image
		if name := sf_symbol_names[tab.icon]; name != "" do image = ui_image_system(ns_string(name))
		item := send(^NS.Object, objc_class_object("UITabBarItem"), "alloc")
		items[i] = send(^NS.Object, item, "initWithTitle:image:tag:", ns_string(tab.title), image, NS.Integer(i))
	}
	array := array_with_objects(raw_data(items), len(items)) // retains the items
	for item in items do send(nil, item, "release")
	send(nil, bar, "setItems:", array)
	send(nil, bar, "setDelegate:", d)
	objc_clear_delegate_on_dispose(bar)
	h.root = View(bar)
	h.control = bar
	h.target = d
	_tabbar_select(h)
}

@(private)
_tabbar_select :: proc(h: ^Tabbar_Handle) {
	bar := (^NS.Object)(h.control)
	items := send(^NS.Array, bar, "items")
	send(nil, bar, "setSelectedItem:", send(^NS.Object, items, "objectAtIndex:", NS.UInteger(h.selected)))
}

@(private)
tab_selected :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id, item: NS.id) {
	h := objc_handle(self, Tabbar_Handle)
	context = h.ctx
	tabbar_notify(h, int(object_tag((^NS.Object)(item))))
}
