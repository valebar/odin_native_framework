#+build linux:default
package nv

// Linux canvas backend: a GtkDrawingArea drawn with cairo, and a GtkGestureDrag for the pointer
// (it reports offsets from the start point, so Move / Up add them back).

import "core:math"
import "core:strings"

@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	area := gtk_drawing_area_new()
	gtk_widget_set_hexpand(area, true)
	gtk_widget_set_vexpand(area, true)
	gtk_drawing_area_set_draw_func(area, rawptr(on_canvas_draw), h, nil)

	drag := gtk_gesture_drag_new()
	g_signal_connect(drag, "drag-begin", rawptr(on_canvas_drag_begin), h)
	g_signal_connect(drag, "drag-update", rawptr(on_canvas_drag_update), h)
	g_signal_connect(drag, "drag-end", rawptr(on_canvas_drag_end), h)
	gtk_widget_add_controller(area, drag) // takes ownership

	h.root = View(area)
	h.view = area
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	gtk_widget_queue_draw((^GtkWidget)(h.view))
}

@(private)
cairo_of :: #force_inline proc "contextless" (p: ^Painter, c: Color) -> ^cairo_t {
	cr := (^cairo_t)(p.native)
	cairo_set_source_rgba(cr, f64(c.r), f64(c.g), f64(c.b), f64(c.a))
	cairo_new_path(cr)
	return cr
}

@(private)
_fill_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	cr := cairo_of(p, color)
	cairo_rectangle(cr, x, y, w, h)
	cairo_fill(cr)
}

@(private)
_stroke_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	cr := cairo_of(p, color)
	cairo_set_line_width(cr, width)
	cairo_rectangle(cr, x, y, w, h)
	cairo_stroke(cr)
}

@(private)
_draw_line :: proc(p: ^Painter, x0, y0, x1, y1: f64, color: Color, width: f64) {
	cr := cairo_of(p, color)
	cairo_set_line_width(cr, width)
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
	cairo_move_to(cr, x0, y0)
	cairo_line_to(cr, x1, y1)
	cairo_stroke(cr)
}

// A unit circle scaled to the rect. The path is kept after restore, so a stroke isn't scaled.
@(private)
ellipse_path :: proc "contextless" (cr: ^cairo_t, x, y, w, h: f64) {
	cairo_save(cr)
	cairo_translate(cr, x + w / 2, y + h / 2)
	cairo_scale(cr, w / 2, h / 2)
	cairo_arc(cr, 0, 0, 1, 0, 2 * math.PI)
	cairo_restore(cr)
}

@(private)
_fill_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	cr := cairo_of(p, color)
	ellipse_path(cr, x, y, w, h)
	cairo_fill(cr)
}

@(private)
_stroke_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	cr := cairo_of(p, color)
	cairo_set_line_width(cr, width)
	ellipse_path(cr, x, y, w, h)
	cairo_stroke(cr)
}

// Cairo's toy text API; show_text starts at the baseline, so it moves down by the ascent.
@(private)
_draw_text :: proc(p: ^Painter, text: string, x, y: f64, size: f64, color: Color) {
	cr := cairo_of(p, color)
	cairo_select_font_face(cr, "sans-serif", 0, 0)
	cairo_set_font_size(cr, size)
	ext: cairo_font_extents_t
	cairo_font_extents(cr, &ext)
	cairo_move_to(cr, x, y + ext.ascent)
	cairo_show_text(cr, strings.clone_to_cstring(text, context.temp_allocator))
}

@(private)
on_canvas_draw :: proc "c" (_: ^GtkWidget, cr: ^cairo_t, width, height: i32, user: gpointer) {
	h := (^Canvas_Handle)(user)
	context = h.ctx
	canvas_draw_notify(h, cr, f64(width), f64(height))
}

@(private)
on_canvas_drag_begin :: proc "c" (_: ^GtkEventController, x, y: f64, user: gpointer) {
	h := (^Canvas_Handle)(user)
	context = h.ctx
	canvas_pointer_notify(h, .Down, x, y)
}

@(private)
canvas_drag :: proc "c" (g: ^GtkEventController, dx, dy: f64, h: ^Canvas_Handle, kind: Pointer) {
	context = h.ctx
	x, y: f64
	gtk_gesture_drag_get_start_point(g, &x, &y)
	canvas_pointer_notify(h, kind, x + dx, y + dy)
}

@(private)
on_canvas_drag_update :: proc "c" (g: ^GtkEventController, dx, dy: f64, user: gpointer) {
	canvas_drag(g, dx, dy, (^Canvas_Handle)(user), .Move)
}

@(private)
on_canvas_drag_end :: proc "c" (g: ^GtkEventController, dx, dy: f64, user: gpointer) {
	canvas_drag(g, dx, dy, (^Canvas_Handle)(user), .Up)
}
