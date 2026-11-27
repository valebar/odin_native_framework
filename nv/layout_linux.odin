#+build linux:default
#+private
package nv

// Linux Layout backend: GTK4 has no size-allocate signal, so the Layout is a GtkBox whose layout
// manager is a GtkCustomLayout. Its allocate reports the size first, then measures and allocates
// the child, so what the app changed in on_layout is in this frame (a resize queued meanwhile makes
// the frame clock lay out again before painting). It asks for no minimum of its own: it takes the
// size it is given, and the child is clipped if it still needs more.

@(private)
_layout_init :: proc(h: ^Layout_Handle) {
	box := gtk_box_new(.Vertical, 0)
	gtk_widget_set_layout_manager(box, gtk_custom_layout_new(nil, layout_measure, layout_allocate))
	gtk_widget_set_overflow(box, .Hidden)
	gtk_widget_set_hexpand(box, false)
	gtk_widget_set_vexpand(box, false)
	g_object_set_data(box, "nv-layout", h)
	child := (^GtkWidget)(h.layout.child)
	gtk_widget_set_hexpand(child, true)
	gtk_widget_set_vexpand(child, true)
	gtk_box_append(box, child)
	h.root = View(box)
}

@(private)
layout_measure :: proc "c" (widget: ^GtkWidget, orientation: GtkOrientation, for_size: i32, minimum, natural, minimum_baseline, natural_baseline: ^i32) {
	h := (^Layout_Handle)(g_object_get_data(widget, "nv-layout"))
	min, nat, mb, nb: i32
	gtk_widget_measure((^GtkWidget)(h.layout.child), orientation, -1, &min, &nat, &mb, &nb)
	minimum^, natural^ = 0, nat
	minimum_baseline^, natural_baseline^ = -1, -1
}

@(private)
layout_allocate :: proc "c" (widget: ^GtkWidget, width, height, baseline: i32) {
	h := (^Layout_Handle)(g_object_get_data(widget, "nv-layout"))
	context = h.ctx
	layout_notify(h, f64(width), f64(height))
	child := (^GtkWidget)(h.layout.child)
	min_w, min_h, nat, mb, nb: i32
	gtk_widget_measure(child, .Horizontal, -1, &min_w, &nat, &mb, &nb)
	gtk_widget_measure(child, .Vertical, -1, &min_h, &nat, &mb, &nb)
	gtk_widget_allocate(child, max(width, min_w), max(height, min_h), -1, nil)
}
