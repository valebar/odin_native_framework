#+build js
#+private
package nv

// Web canvas backend: a <canvas> filling its view (which has no size from it), at the device pixel
// ratio and redrawn whole by nv.js: at once on a resize, else on the next animation frame. A
// canvas_redraw from inside on_draw asks for the next frame, which is how a canvas animates (the
// Bench, Progress) at the display rate; a canvas that isn't shown (a page below, a hidden tab) is
// drawn when it shows again. The draw procs paint on the canvas being drawn (nv.js's `cur`), so
// Painter.native is unused; nv.js skips the colour, line width and font a call repeats (and forgets
// them at a clip_pop, whose restore brings back the state saved at its clip_push).

@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	view := js_canvas_create(h)
	scope_on_dispose(web_release, rawptr(uintptr(view)))
	h.root = web_view(view)
	h.view = rawptr(uintptr(view))
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	js_canvas_redraw(Web_Id(uintptr(h.view)))
}

@(private)
_fill_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	js_fill_rect(x, y, w, h, color_argb(color))
}

@(private)
_stroke_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	js_stroke_rect(x, y, w, h, color_argb(color), width)
}

@(private)
_draw_line :: proc(p: ^Painter, x0, y0, x1, y1: f64, color: Color, width: f64) {
	js_line(x0, y0, x1, y1, color_argb(color), width)
}

@(private)
_fill_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	js_fill_ellipse(x, y, w, h, color_argb(color))
}

@(private)
_stroke_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	js_stroke_ellipse(x, y, w, h, color_argb(color), width)
}

@(private)
_stroke_arc :: proc(p: ^Painter, cx, cy, radius, start, sweep: f64, color: Color, width: f64) {
	js_arc(cx, cy, radius, start, sweep, color_argb(color), width)
}

// The system font, or a loaded face with its own weight and slant unless the style sets them.
@(private)
_draw_text :: proc(p: ^Painter, text: string, x, y: f64, style: Text_Style) {
	weight, italic, font := web_text_font(style)
	js_draw_text(text, x, y, style.size, weight, italic, font, color_argb(style.color))
}

@(private)
_draw_text_rotated :: proc(p: ^Painter, text: string, x, y, angle: f64, style: Text_Style) {
	weight, italic, font := web_text_font(style)
	js_draw_text_rotated(text, x, y, angle, style.size, weight, italic, font, color_argb(style.color))
}

// measureText's advance; the line box is the font's ascent and descent (fontBoundingBox).
@(private)
_measure_text :: proc(p: ^Painter, text: string, style: Text_Style) -> (width, height: f64) {
	weight, italic, font := web_text_font(style)
	width = js_measure_text(text, style.size, weight, italic, font)
	return width, js_text_height(style.size, weight, italic, font)
}

@(private)
web_text_font :: proc(style: Text_Style) -> (weight: i32, italic: b32, font: i32) {
	w := web_weight(text_weight(style.weight, false))
	it := style.italic
	if f := style.font; f != nil {
		font = i32(uintptr(f.native))
		it ||= f.italic
		if style.weight == .Default do w = f.weight
	}
	return i32(w), b32(it), font
}

@(private)
_draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	js_draw_image(i32(uintptr(b.native)), x, y, w, h)
}

// nv.js reads the points through a fresh view of wasm memory.
@(private)
_stroke_polyline :: proc(p: ^Painter, points: [][2]f64, color: Color, width: f64) {
	js_polyline(raw_data(points), i32(len(points)), color_argb(color), width)
}

@(private)
_fill_polygon :: proc(p: ^Painter, points: [][2]f64, color: Color) {
	js_fill_polygon(raw_data(points), i32(len(points)), color_argb(color))
}

@(private)
_clip_push :: proc(p: ^Painter, x, y, w, h: f64) {
	js_clip_push(x, y, w, h)
}

@(private)
_clip_pop :: proc(p: ^Painter) {
	js_clip_pop()
}
