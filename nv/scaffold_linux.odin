#+build linux:default
#+private
package nv

// Linux scaffold backend: the overlay is a GtkOverlay (its child the base, the rest overlay
// children placed by halign / valign, margins and a size request), the scrim a "nv-scrim" box with
// a click gesture, the FAB a GtkButton with the "nv-fab" class (app_linux.odin; the accent from
// theme_linux.odin), the tab bar a homogeneous box of grouped, flat GtkToggleButtons, and the timer
// g_timeout_add. The parents own the widgets, as everywhere in this backend.

import "core:strings"

@(private)
_view_set_hidden :: proc(v: View, hidden: bool) {
	gtk_widget_set_visible((^GtkWidget)(v), !hidden)
}

@(private)
_view_set_enabled :: proc(v: View, enabled: bool) {
	gtk_widget_set_sensitive((^GtkWidget)(v), gboolean(enabled))
}

@(private)
_overlay_init :: proc(h: ^Overlay_Handle) {
	overlay := gtk_overlay_new()
	base := (^GtkWidget)(h.base)
	gtk_widget_set_hexpand(base, true)
	gtk_widget_set_vexpand(base, true)
	gtk_overlay_set_child(overlay, base)
	h.root = View(overlay)
}

@(private)
_overlay_add :: proc(h: ^Overlay_Handle, child: View, place: Overlay_Place) {
	gtk_overlay_add_overlay((^GtkWidget)(h.root), (^GtkWidget)(child)) // above the earlier ones
	if place.sizes do gtk_overlay_set_measure_overlay((^GtkWidget)(h.root), (^GtkWidget)(child), true) // the main child always counts
	_overlay_place(h, child, place)
}

@(private)
_overlay_place :: proc(h: ^Overlay_Handle, child: View, place: Overlay_Place) {
	align :: proc(a: Align) -> GtkAlign {
		switch a {
		case .Start:  return .Start
		case .Center: return .Center
		case .End:    return .End
		case .Fill:   return .Fill
		}
		return .Fill
	}
	w := (^GtkWidget)(child)
	gtk_widget_set_halign(w, align(place.h))
	gtk_widget_set_valign(w, align(place.v))
	gtk_widget_set_margin_start(w, i32(place.margin.left))
	gtk_widget_set_margin_top(w, i32(place.margin.top))
	gtk_widget_set_margin_end(w, i32(place.margin.right))
	gtk_widget_set_margin_bottom(w, i32(place.margin.bottom))

	// The place's size is the child's size request, which is also where a child keeps a size of its
	// own (a container's width / height). A place without one leaves the child's alone; one with a
	// size saves the child's first (as object data) and a later place without one restores it.
	pw := place.width > 0 && place.h != .Fill ? i32(place.width + 0.5) : -1
	ph := place.height > 0 && place.v != .Fill ? i32(place.height + 0.5) : -1
	saved := uintptr(g_object_get_data(w, OVERLAY_OWN_SIZE))
	if pw < 0 && ph < 0 {
		if saved != 0 {
			ow, oh := overlay_own_size_unpack(saved)
			gtk_widget_set_size_request(w, ow, oh)
			g_object_set_data(w, OVERLAY_OWN_SIZE, nil)
		}
		return
	}
	if saved == 0 {
		ow, oh: i32
		gtk_widget_get_size_request(w, &ow, &oh)
		saved = overlay_own_size_pack(ow, oh)
		g_object_set_data(w, OVERLAY_OWN_SIZE, rawptr(saved))
	}
	ow, oh := overlay_own_size_unpack(saved)
	gtk_widget_set_size_request(w, pw >= 0 ? pw : ow, ph >= 0 ? ph : oh)
}

@(private) OVERLAY_OWN_SIZE :: "nv-own-size"

// The child's own size request (-1: none) in a pointer that is never nil.
@(private)
overlay_own_size_pack :: proc(w, h: i32) -> uintptr {
	return 1 << 31 | uintptr(u16(w + 1)) << 16 | uintptr(u16(h + 1))
}

@(private)
overlay_own_size_unpack :: proc(p: uintptr) -> (w, h: i32) {
	return i32(p >> 16 & 0xffff) - 1, i32(p & 0xffff) - 1
}

@(private)
_overlay_scrim_init :: proc(h: ^Overlay_Handle) {
	scrim := gtk_box_new(.Vertical, 0)
	gtk_widget_add_css_class(scrim, "nv-scrim")
	click := gtk_gesture_click_new()
	g_signal_connect(click, "pressed", rawptr(on_scrim_pressed), h)
	gtk_widget_add_controller(scrim, click)
	gtk_overlay_add_overlay((^GtkWidget)(h.root), scrim) // fills the overlay (halign / valign Fill)
	h.scrim = View(scrim)
}

@(private)
on_scrim_pressed :: proc "c" (_: ^GtkEventController, _: i32, _, _: f64, user: gpointer) {
	h := (^Overlay_Handle)(user)
	context = h.ctx
	overlay_scrim_notify(h)
}

@(private)
_fab_init :: proc(h: ^Fab_Handle) {
	f := &h.fab
	icon := gtk_icon_names[f.icon]
	b: ^GtkWidget
	if f.title == "" && icon == "" do icon = gtk_icon_names[.Add] // no image for it here
	if f.title == "" {
		b = gtk_button_new()
		gtk_button_set_child(b, fab_icon(icon))
	} else {
		b = gtk_button_new()
		gtk_widget_add_css_class(b, "nv-extended")
		box := gtk_box_new(.Horizontal, 8)
		if icon != "" do gtk_box_append(box, fab_icon(icon))
		gtk_box_append(box, gtk_label_new(strings.clone_to_cstring(f.title, context.temp_allocator)))
		gtk_widget_set_halign(box, .Center)
		gtk_button_set_child(b, box)
	}
	gtk_widget_add_css_class(b, "nv-fab")
	g_signal_connect(b, "clicked", rawptr(on_fab_clicked), h)
	h.root = View(b)
	h.control = b
}

@(private)
fab_icon :: proc(name: cstring) -> ^GtkWidget {
	img := gtk_image_new_from_icon_name(name)
	gtk_image_set_pixel_size(img, 24)
	return img
}

@(private)
on_fab_clicked :: proc "c" (_: ^GtkWidget, user: gpointer) {
	h := (^Fab_Handle)(user)
	context = h.ctx
	fab_notify(h)
}

// The tab buttons, in tab order (Tabbar_Handle.items, in the scope's arena).
@(private)
_tabbar_init :: proc(h: ^Tabbar_Handle) {
	bar := gtk_box_new(.Horizontal, 0)
	gtk_box_set_homogeneous(bar, true)
	gtk_widget_add_css_class(bar, "nv-tabbar")
	buttons := make([]^GtkWidget, len(h.tabs), scope_allocator(scope_current()))
	for t, i in h.tabs {
		b := gtk_toggle_button_new()
		gtk_widget_add_css_class(b, "flat")
		box := gtk_box_new(.Vertical, 2)
		if icon := gtk_icon_names[t.icon]; icon != "" {
			img := gtk_image_new_from_icon_name(icon)
			gtk_image_set_pixel_size(img, 20)
			gtk_box_append(box, img)
		}
		gtk_box_append(box, gtk_label_new(strings.clone_to_cstring(t.title, context.temp_allocator)))
		gtk_button_set_child(b, box)
		if i > 0 do gtk_toggle_button_set_group(b, buttons[0])
		gtk_toggle_button_set_active(b, i == h.selected) // before the signal: no report
		g_signal_connect(b, "toggled", rawptr(on_tab_toggled), h)
		gtk_box_append(bar, b)
		buttons[i] = b
	}
	h.items = raw_data(buttons)
	h.root = View(bar)
	h.control = bar
}

@(private)
_tabbar_select :: proc(h: ^Tabbar_Handle) {
	buttons := ([^]^GtkWidget)(h.items)
	gtk_toggle_button_set_active(buttons[h.selected], true) // "toggled" reports the tab already selected: ignored
}

// Both the button turned off and the one turned on report; only the active one counts.
@(private)
on_tab_toggled :: proc "c" (b: ^GtkWidget, user: gpointer) {
	h := (^Tabbar_Handle)(user)
	context = h.ctx
	if !gtk_toggle_button_get_active(b) do return
	buttons := ([^]^GtkWidget)(h.items)
	for i in 0..<len(h.tabs) do if buttons[i] == b {
		tabbar_notify(h, i)
		return
	}
}

@(private)
_post_delayed :: proc(ms: int, t: ^Timer) {
	g_timeout_add(guint(max(ms, 0)), timer_source, t)
}

// g_idle_add is thread-safe: it attaches to the default main context from any thread.
@(private)
_post_timer :: proc(t: ^Timer) {
	g_idle_add(timer_source, t)
}

@(private)
timer_source :: proc "c" (data: gpointer) -> gboolean {
	timer_fire((^Timer)(data))
	return G_SOURCE_REMOVE
}
