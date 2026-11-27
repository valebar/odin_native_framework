#+build linux:default
#+private
package nv

// Linux Row / Column backend: a GtkBox. A child's flex maps onto its expand flag along the
// main axis. GtkBox has no weights, so every flex > 0 child gets an equal share of the spare
// space. The flag is set explicitly for every child: the list turns both flags on at creation,
// so a flex-0 list must be turned off again, and an explicit value also stops the flag from
// propagating up through the box to its parent.

@(private)
_flex_create :: proc(f: Flex) -> View {
	box := gtk_box_new(GtkOrientation(f.axis), i32(f.spacing))
	for c in f.children {
		child := (^GtkWidget)(c.view)
		switch f.axis {
		case .Horizontal: gtk_widget_set_hexpand(child, c.flex > 0)
		case .Vertical:   gtk_widget_set_vexpand(child, c.flex > 0)
		}
		gtk_box_append(box, child)
	}
	return View(box)
}
