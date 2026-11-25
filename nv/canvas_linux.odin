#+build linux:default
package nv

// Linux canvas backend: a GtkDrawingArea drawn with cairo, a GtkGestureDrag for the pointer
// (it reports offsets from the start point, so Move / Up add them back) and a
// GtkEventControllerScroll for the wheel / touchpad.

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

	scroll := gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)
	g_signal_connect(scroll, "scroll", rawptr(on_canvas_scroll), h)
	gtk_widget_add_controller(area, scroll)

	// The canvas holds its own reference, so a pending tick can still be removed when the scope dies.
	g_object_ref_sink(area)
	h.extra = scope_new_in(Linux_Canvas)
	scope_on_dispose(canvas_dispose, h)

	h.root = View(area)
	h.view = area
}

// Per-canvas redraw state (Canvas_Handle.extra, in the page's arena).
@(private) Linux_Canvas :: struct {
	drawing: bool,  // inside the draw func
	tick:    guint, // the pending tick callback (canvas_tick), 0 when none
}

@(private)
canvas_dispose :: proc(data: rawptr) {
	h := (^Canvas_Handle)(data)
	c := (^Linux_Canvas)(h.extra)
	if c.tick != 0 do gtk_widget_remove_tick_callback((^GtkWidget)(h.view), c.tick)
	g_object_unref(h.view)
}

// A queue_draw issued from inside the canvas's own draw func is lost (GTK clears the flag when the
// snapshot returns), so a redraw it asks for waits for the next frame clock tick, one at most per
// canvas: that is how a canvas animates (the Bench, Progress).
@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	c := (^Linux_Canvas)(h.extra)
	area := (^GtkWidget)(h.view)
	if !c.drawing {
		gtk_widget_queue_draw(area)
	} else if c.tick == 0 {
		c.tick = gtk_widget_add_tick_callback(area, rawptr(canvas_tick), h, nil)
	}
}

@(private)
canvas_tick :: proc "c" (area: ^GtkWidget, _: rawptr, user: gpointer) -> gboolean {
	(^Linux_Canvas)((^Canvas_Handle)(user).extra).tick = 0
	gtk_widget_queue_draw(area)
	return G_SOURCE_REMOVE
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

// cairo_arc grows clockwise in a y-down space; cairo_of cleared the path, so no line leads in.
// The cap is butt, since _draw_line leaves it round.
@(private)
_stroke_arc :: proc(p: ^Painter, cx, cy, radius, start, sweep: f64, color: Color, width: f64) {
	cr := cairo_of(p, color)
	cairo_set_line_width(cr, width)
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
	a0 := start * math.PI / 180
	cairo_arc(cr, cx, cy, radius, a0, a0 + sweep * math.PI / 180)
	cairo_stroke(cr)
}

// Cairo's toy text API; show_text starts at the baseline, so it moves down by the ascent. A loaded
// font is selected by family: cairo-ft resolves it through the fontconfig config it was added to.
// The API only knows normal and bold, so Semibold is bold too.
@(private)
_draw_text :: proc(p: ^Painter, text: string, x, y: f64, style: Text_Style) {
	cr := cairo_of(p, style.color)
	ext := canvas_font(cr, style)
	cairo_move_to(cr, x, y + ext.ascent)
	cairo_show_text(cr, strings.clone_to_cstring(text, context.temp_allocator))
}

@(private)
_measure_text :: proc(p: ^Painter, text: string, style: Text_Style) -> (width, height: f64) {
	cr := (^cairo_t)(p.native)
	ext := canvas_font(cr, style)
	te: cairo_text_extents_t
	cairo_text_extents(cr, strings.clone_to_cstring(text, context.temp_allocator), &te)
	return te.x_advance, ext.ascent + ext.descent
}

// Selects the style's face and size on `cr`; its extents.
@(private)
canvas_font :: proc(cr: ^cairo_t, style: Text_Style) -> (ext: cairo_font_extents_t) {
	family: cstring = "sans-serif"
	italic, bold := style.italic, style.weight >= .Semibold
	if f := style.font; f != nil {
		family = strings.clone_to_cstring(f.family, context.temp_allocator)
		italic ||= f.italic
		if style.weight == .Default do bold = f.weight >= 600
	}
	cairo_select_font_face(cr, family, italic ? CAIRO_FONT_SLANT_ITALIC : 0, bold ? CAIRO_FONT_WEIGHT_BOLD : 0)
	cairo_set_font_size(cr, style.size)
	cairo_font_extents(cr, &ext)
	return
}

@(private)
on_canvas_draw :: proc "c" (_: ^GtkWidget, cr: ^cairo_t, width, height: i32, user: gpointer) {
	h := (^Canvas_Handle)(user)
	context = h.ctx
	c := (^Linux_Canvas)(h.extra)
	c.drawing = true
	defer c.drawing = false
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

// Wheel deltas come in notches, a touchpad's (GDK_SCROLL_UNIT_SURFACE) in pixels; both are
// positive towards the bottom / right, like on_scroll.
@(private)
on_canvas_scroll :: proc "c" (c: ^GtkEventController, dx, dy: f64, user: gpointer) -> gboolean {
	h := (^Canvas_Handle)(user)
	context = h.ctx
	if h.canvas.on_scroll == nil do return false
	k := gtk_event_controller_scroll_get_unit(c) == GDK_SCROLL_UNIT_WHEEL ? f64(SCROLL_LINE) : 1
	canvas_scroll_notify(h, dx * k, dy * k)
	return true
}
