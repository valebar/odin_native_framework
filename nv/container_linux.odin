#+build linux:default
#+private
package nv

// Linux container backend: a GtkBox that is the margin box (the GTK margin properties keep the
// box's own CSS background inside them), decorated through CSS, since GTK4 has no API for a
// widget's background. Every container gets a class of its own ("nv-c<N>") and a GtkCssProvider
// added for the display (the per-widget provider API is deprecated); container_set_color reloads
// that provider. The size request is a minimum: a larger child grows the container.

import "core:fmt"
import "core:strings"

@(private) g_container_seq: int

// What the handle keeps per container (Container_Handle.box).
@(private) Linux_Container :: struct {
	provider: ^GtkCssProvider,
	seq:      int, // the number in the widget's "nv-c<N>" class
}

@(private)
_container_init :: proc(h: ^Container_Handle) {
	c := &h.container
	box := gtk_box_new(.Vertical, 0)
	gtk_widget_set_margin_start(box, i32(c.margin.left + 0.5))
	gtk_widget_set_margin_end(box, i32(c.margin.right + 0.5))
	gtk_widget_set_margin_top(box, i32(c.margin.top + 0.5))
	gtk_widget_set_margin_bottom(box, i32(c.margin.bottom + 0.5))
	gtk_widget_set_size_request(box, c.width > 0 ? i32(c.width + 0.5) : -1, c.height > 0 ? i32(c.height + 0.5) : -1)
	gtk_widget_set_overflow(box, .Hidden) // clips the child to the corners
	// Explicit, so the child's expand flags below don't propagate up; _flex_create sets the main axis.
	gtk_widget_set_hexpand(box, false)
	gtk_widget_set_vexpand(box, false)

	g_container_seq += 1
	lc := scope_new_in(Linux_Container)
	lc^ = {gtk_css_provider_new(), g_container_seq}
	scope_on_dispose(container_dispose, lc)
	gtk_widget_add_css_class(box, strings.clone_to_cstring(fmt.tprintf("nv-c%d", lc.seq), context.temp_allocator))
	gtk_style_context_add_provider_for_display(gdk_display_get_default(), lc.provider, GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
	h.box = lc
	h.root = View(box)
	container_load_css(h)

	if c.child != nil {
		child := (^GtkWidget)(c.child)
		gtk_widget_set_hexpand(child, true)
		gtk_widget_set_vexpand(child, true)
		gtk_box_append(box, child)
	}
}

// The provider stays on the display (and keeps its rule) until the container's scope dies.
@(private)
container_dispose :: proc(data: rawptr) {
	lc := (^Linux_Container)(data)
	gtk_style_context_remove_provider_for_display(gdk_display_get_default(), lc.provider)
	g_object_unref(lc.provider)
}

@(private)
_container_set_color :: proc(h: ^Container_Handle) {
	container_load_css(h)
}

// Loads the container's decoration as the one rule of its provider (a reload replaces it).
@(private)
container_load_css :: proc(h: ^Container_Handle) {
	c := &h.container
	lc := (^Linux_Container)(h.box)
	rgba :: proc(col: Color) -> string {
		a := color_argb(col)
		return fmt.tprintf("rgba(%d, %d, %d, %.3f)", a >> 16 & 0xff, a >> 8 & 0xff, a & 0xff, clamp(col.a, 0, 1))
	}
	background := c.color.a > 0 ? rgba(c.color) : "transparent"
	border := c.border_width > 0 ? fmt.tprintf("%dpx solid %s", int(c.border_width + 0.5), rgba(c.border_color)) : "none"
	css := fmt.tprintf(".nv-c%d {{ background-color: %s; border: %s; border-radius: %dpx; padding: %dpx %dpx %dpx %dpx; }}", // fmt escapes braces doubled
		lc.seq, background, border, int(c.radius + 0.5),
		int(c.padding.top + 0.5), int(c.padding.right + 0.5), int(c.padding.bottom + 0.5), int(c.padding.left + 0.5))
	gtk_css_provider_load_from_data(lc.provider, strings.clone_to_cstring(css, context.temp_allocator), -1)
}

@(private)
_container_set_size :: proc(h: ^Container_Handle) {
	c := &h.container
	gtk_widget_set_size_request((^GtkWidget)(h.root), c.width > 0 ? i32(c.width + 0.5) : -1, c.height > 0 ? i32(c.height + 0.5) : -1)
}
