#+build linux:android
package nv

// Android canvas backend: nv.NvCanvasView (Java shim) forwards onDraw and touches. Drawing goes
// through android.graphics.Canvas, scaled by the display density so units are dp. Two
// anti-aliased Paints (fill, stroke) are kept per canvas; Android_Canvas remembers what they were
// last set to, so a primitive in the same colour (width, font) costs one JNI call, not two or
// more. The memory is cleared per frame. jni_check's ExceptionCheck after every call stays: it
// never enters Java, and it is what turns a bad draw call into a log line instead of an abort.

@(private) ANDROID_ANTI_ALIAS_FLAG :: 1 // Paint.ANTI_ALIAS_FLAG

// Per-canvas draw state (Canvas_Handle.extra, in the page's arena).
@(private) Android_Canvas :: struct {
	color:    [2]int,  // last ARGB set on the fill / stroke Paint ..
	color_ok: [2]bool, // .. and whether it is known
	width:    f32,     // last stroke width
	width_ok: bool,
	typeface: jobject, // last text state on the fill Paint
	size:     f32,
	ascent:   f32,
	text_ok:  bool,
	rect:     jobject, // a RectF global ref that _draw_image reuses
}

// MotionEvent.getActionMasked values.
@(private) ANDROID_ACTION_DOWN   :: 0
@(private) ANDROID_ACTION_UP     :: 1
@(private) ANDROID_ACTION_MOVE   :: 2
@(private) ANDROID_ACTION_CANCEL :: 3

@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	env := g_android.env

	v := nv_canvas_view_new(env, g_android.activity, i64(uintptr(h)))

	fill := paint_new(env, ANDROID_ANTI_ALIAS_FLAG)
	stroke := paint_new(env, ANDROID_ANTI_ALIAS_FLAG)
	style := paint_style_value_of(env, "STROKE")
	paint_set_style(env, stroke, style)
	cap := paint_cap_value_of(env, "ROUND")
	paint_set_stroke_cap(env, stroke, cap)

	h.root = View(android_own_ref(env, v))
	h.view = rawptr(h.root)
	h.fill = rawptr(android_own_ref(env, fill))
	h.stroke = rawptr(android_own_ref(env, stroke))
	c := scope_new_in(Android_Canvas)
	h.extra = c
	rect := rect_f_new(env, 0, 0, 0, 0)
	c.rect = android_own_ref(env, rect)
	jni_delete_local_ref(env, rect)
	jni_delete_local_ref(env, cap)
	jni_delete_local_ref(env, style)
	jni_delete_local_ref(env, stroke)
	jni_delete_local_ref(env, fill)
	jni_delete_local_ref(env, v)
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	view_invalidate(g_android.env, jobject(h.view))
}

@(private)
android_density :: proc "contextless" () -> f64 {
	android_dp(1) // reads the density on first use
	return f64(g_android.density)
}

// Paint with `color` as ARGB, and the stroke width for the stroke Paint; each is set only when
// it differs from what the Paint already has.
@(private)
paint :: proc "contextless" (p: ^Painter, color: Color, stroke := false, width: f64 = 0) -> jobject {
	env := g_android.env
	obj := jobject(stroke ? p.h.stroke : p.h.fill)
	c := (^Android_Canvas)(p.h.extra)
	i := stroke ? 1 : 0
	if argb := android_argb(color); !c.color_ok[i] || c.color[i] != argb {
		paint_set_color(env, obj, argb)
		c.color[i], c.color_ok[i] = argb, true
	}
	if w := f32(width); stroke && (!c.width_ok || c.width != w) {
		paint_set_stroke_width(env, obj, w)
		c.width, c.width_ok = w, true
	}
	return obj
}

@(private)
_fill_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	canvas_draw_rect(g_android.env, jobject(p.native), f32(x), f32(y), f32(x + w), f32(y + h), paint(p, color))
}

@(private)
_stroke_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	canvas_draw_rect(g_android.env, jobject(p.native), f32(x), f32(y), f32(x + w), f32(y + h), paint(p, color, true, width))
}

@(private)
_draw_line :: proc(p: ^Painter, x0, y0, x1, y1: f64, color: Color, width: f64) {
	canvas_draw_line(g_android.env, jobject(p.native), f32(x0), f32(y0), f32(x1), f32(y1), paint(p, color, true, width))
}

@(private)
_fill_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	canvas_draw_oval(g_android.env, jobject(p.native), f32(x), f32(y), f32(x + w), f32(y + h), paint(p, color))
}

@(private)
_stroke_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	canvas_draw_oval(g_android.env, jobject(p.native), f32(x), f32(y), f32(x + w), f32(y + h), paint(p, color, true, width))
}

// drawText takes the baseline; ascent() is negative, so baseline = top - ascent. The size and
// typeface (the style's, from android_style_typeface: a cached global ref, so the same style
// gives the same object) go on the shared fill Paint when they differ from the last text drawn;
// setTypeface returns the previous Typeface, a local ref to drop.
@(private)
_draw_text :: proc(p: ^Painter, text: string, x, y: f64, style: Text_Style) {
	env := g_android.env
	c := (^Android_Canvas)(p.h.extra)
	pt := paint(p, style.color)
	tf := android_style_typeface(env, style, false)
	if size := f32(style.size); !c.text_ok || tf != c.typeface || size != c.size {
		paint_set_text_size(env, pt, size)
		if old := paint_set_typeface(env, pt, tf); old != nil do jni_delete_local_ref(env, old)
		c.typeface, c.size, c.ascent, c.text_ok = tf, size, paint_ascent(env, pt), true
	}
	canvas_draw_text(env, jobject(p.native), text, f32(x), f32(y) - c.ascent, pt)
}

@(export, link_name="Java_nv_NvCanvasView_nativeOnDraw")
jni_canvas_on_draw :: proc "c" (env: JNI_Env, _: jclass, handle: jlong, canvas: jobject, width, height: jint) {
	h := (^Canvas_Handle)(uintptr(handle))
	context = h.ctx
	g_android.env = env
	c := (^Android_Canvas)(h.extra)
	c.color_ok, c.width_ok, c.text_ok = {}, false, false // forget the Paints' state every frame
	d := android_density()
	canvas_scale(env, canvas, f32(d), f32(d))
	canvas_draw_notify(h, rawptr(canvas), f64(width) / d, f64(height) / d)
}

@(export, link_name="Java_nv_NvCanvasView_nativeOnTouch")
jni_canvas_on_touch :: proc "c" (env: JNI_Env, _: jclass, handle: jlong, action: jint, x, y: f32) {
	h := (^Canvas_Handle)(uintptr(handle))
	context = h.ctx
	g_android.env = env
	kind: Pointer
	switch action {
	case ANDROID_ACTION_DOWN:                     kind = .Down
	case ANDROID_ACTION_MOVE:                     kind = .Move
	case ANDROID_ACTION_UP, ANDROID_ACTION_CANCEL: kind = .Up
	case: return
	}
	d := android_density()
	canvas_pointer_notify(h, kind, f64(x) / d, f64(y) / d)
}
