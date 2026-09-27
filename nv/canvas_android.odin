#+build linux:android
package nv

// Android canvas backend: nv.NvCanvasView (Java shim) forwards onDraw and touches. Drawing goes
// through android.graphics.Canvas, scaled by the display density so units are dp. Two
// anti-aliased Paints (fill, stroke) are kept per canvas and recolored on every primitive.

import "core:strings"

@(private) ANDROID_ANTI_ALIAS_FLAG :: 1 // Paint.ANTI_ALIAS_FLAG

// MotionEvent.getActionMasked values.
@(private) ANDROID_ACTION_DOWN   :: 0
@(private) ANDROID_ACTION_UP     :: 1
@(private) ANDROID_ACTION_MOVE   :: 2
@(private) ANDROID_ACTION_CANCEL :: 3

@(private)
_canvas_init :: proc(h: ^Canvas_Handle) {
	env := g_android.env

	v_cls := jni_find_class(env, "nv/NvCanvasView")
	v := jni_new_object(env, v_cls, "(Landroid/content/Context;J)V", jv_obj(g_android.activity), jv_long(i64(uintptr(h))))

	p_cls := jni_find_class(env, "android/graphics/Paint")
	fill := jni_new_object(env, p_cls, "(I)V", jv_int(ANDROID_ANTI_ALIAS_FLAG))
	stroke := jni_new_object(env, p_cls, "(I)V", jv_int(ANDROID_ANTI_ALIAS_FLAG))
	style := enum_value(env, "android/graphics/Paint$Style", "(Ljava/lang/String;)Landroid/graphics/Paint$Style;", "STROKE")
	jni_call_void(env, stroke, "setStyle", "(Landroid/graphics/Paint$Style;)V", jv_obj(style))
	cap := enum_value(env, "android/graphics/Paint$Cap", "(Ljava/lang/String;)Landroid/graphics/Paint$Cap;", "ROUND")
	jni_call_void(env, stroke, "setStrokeCap", "(Landroid/graphics/Paint$Cap;)V", jv_obj(cap))

	h.root = View(jni_new_global_ref(env, v))
	h.view = rawptr(h.root)
	h.fill = rawptr(jni_new_global_ref(env, fill))
	h.stroke = rawptr(jni_new_global_ref(env, stroke))
	jni_delete_local_ref(env, cap)
	jni_delete_local_ref(env, style)
	jni_delete_local_ref(env, stroke)
	jni_delete_local_ref(env, fill)
	jni_delete_local_ref(env, p_cls)
	jni_delete_local_ref(env, v)
	jni_delete_local_ref(env, v_cls)
}

// Enum constant by name, through the enum's static valueOf. Returns a local ref.
@(private)
enum_value :: proc "contextless" (env: JNI_Env, cls, sig, name: cstring) -> jobject {
	s := jni_string(env, name)
	defer jni_delete_local_ref(env, s)
	return jni_call_static_object(env, cls, "valueOf", sig, jv_obj(s))
}

@(private)
_canvas_redraw :: proc(h: ^Canvas_Handle) {
	jni_call_void(g_android.env, jobject(h.view), "invalidate", "()V")
}

@(private)
android_density :: proc "contextless" () -> f64 {
	android_dp(1) // reads the density on first use
	return f64(g_android.density)
}

// Paint with `c` as ARGB, and the stroke width for the stroke Paint.
@(private)
paint :: proc "contextless" (p: ^Painter, c: Color, stroke := false, width: f64 = 0) -> jobject {
	env := g_android.env
	obj := jobject(stroke ? p.h.stroke : p.h.fill)
	u8c :: proc "contextless" (f: f32) -> u32 { return u32(clamp(f, 0, 1) * 255 + 0.5) }
	argb := u8c(c.a) << 24 | u8c(c.r) << 16 | u8c(c.g) << 8 | u8c(c.b)
	jni_call_void(env, obj, "setColor", "(I)V", jvalue{i = jint(i32(argb))})
	if stroke do jni_call_void(env, obj, "setStrokeWidth", "(F)V", jv_float(f32(width)))
	return obj
}

@(private)
canvas_call4 :: proc "contextless" (p: ^Painter, name: cstring, a, b, c, d: f64, pt: jobject) {
	jni_call_void(g_android.env, jobject(p.native), name, "(FFFFLandroid/graphics/Paint;)V",
		jv_float(f32(a)), jv_float(f32(b)), jv_float(f32(c)), jv_float(f32(d)), jv_obj(pt))
}

@(private)
_fill_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	canvas_call4(p, "drawRect", x, y, x + w, y + h, paint(p, color))
}

@(private)
_stroke_rect :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	canvas_call4(p, "drawRect", x, y, x + w, y + h, paint(p, color, true, width))
}

@(private)
_draw_line :: proc(p: ^Painter, x0, y0, x1, y1: f64, color: Color, width: f64) {
	canvas_call4(p, "drawLine", x0, y0, x1, y1, paint(p, color, true, width))
}

@(private)
_fill_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color) {
	canvas_call4(p, "drawOval", x, y, x + w, y + h, paint(p, color))
}

@(private)
_stroke_ellipse :: proc(p: ^Painter, x, y, w, h: f64, color: Color, width: f64) {
	canvas_call4(p, "drawOval", x, y, x + w, y + h, paint(p, color, true, width))
}

// drawText takes the baseline; ascent() is negative, so baseline = top - ascent. The typeface is
// set on every call (null for the system font), since the Paint is shared; setTypeface returns
// the Typeface, hence the object call.
@(private)
_draw_text :: proc(p: ^Painter, text: string, x, y: f64, size: f64, color: Color, font: ^Font) {
	env := g_android.env
	pt := paint(p, color)
	jni_call_void(env, pt, "setTextSize", "(F)V", jv_float(f32(size)))
	tf := jni_call_object(env, pt, "setTypeface", "(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;",
		jv_obj(font != nil ? jobject(font.native) : nil))
	if tf != nil do jni_delete_local_ref(env, tf)
	ascent := jni_call_float(env, pt, "ascent", "()F")
	s := jni_string(env, strings.clone_to_cstring(text, context.temp_allocator))
	defer jni_delete_local_ref(env, s)
	jni_call_void(env, jobject(p.native), "drawText", "(Ljava/lang/String;FFLandroid/graphics/Paint;)V",
		jv_obj(s), jv_float(f32(x)), jv_float(f32(y) - ascent), jv_obj(pt))
}

@(export, link_name="Java_nv_NvCanvasView_nativeOnDraw")
jni_canvas_on_draw :: proc "c" (env: JNI_Env, _: jclass, handle: jlong, canvas: jobject, width, height: jint) {
	h := (^Canvas_Handle)(uintptr(handle))
	context = h.ctx
	g_android.env = env
	d := android_density()
	jni_call_void(env, canvas, "scale", "(FF)V", jv_float(f32(d)), jv_float(f32(d)))
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
