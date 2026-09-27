#+build linux:android
package nv

// Android image backend. BitmapFactory decodes into an android.graphics.Bitmap (a global ref).
// The widget is an nv.NvImageView (an ImageView whose natural size comes from here, so an
// explicit size can be smaller than the bitmap) scaled by its ScaleType. Downloads and assets go
// through nv.NvFetch (Java): a download runs on a Java thread and comes back to
// nativeOnFetch on the UI thread.

import "base:runtime"
import "core:os"
import "core:strings"

// ImageView.ScaleType names, indexed by Fit.
@(private) image_scale_types := [Fit]cstring{
	.Contain = "FIT_CENTER",
	.Cover   = "CENTER_CROP",
	.Fill    = "FIT_XY",
}

@(private)
_bitmap_decode :: proc(b: ^Bitmap, data: []u8) -> bool {
	env := g_android.env
	arr := jni_byte_array(env, data)
	defer jni_delete_local_ref(env, arr)
	bmp := jni_call_static_object(env, "android/graphics/BitmapFactory", "decodeByteArray", "([BII)Landroid/graphics/Bitmap;",
		jv_obj(arr), jv_int(0), jv_int(len(data)))
	if bmp == nil do return false
	defer jni_delete_local_ref(env, bmp)
	b.native = rawptr(jni_new_global_ref(env, bmp))
	b.width = int(jni_call_int(env, bmp, "getWidth", "()I"))
	b.height = int(jni_call_int(env, bmp, "getHeight", "()I"))
	return true
}

// No recycle(): an ImageView may still draw it, and the GC frees it once nothing does.
@(private)
_bitmap_free :: proc(b: ^Bitmap) {
	jni_delete_global_ref(g_android.env, jobject(b.native))
}

// The canvas is already scaled to dp. The fill Paint filters the bitmap when scaling; it is made
// opaque first, since its alpha would fade the image.
@(private)
_draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	env := g_android.env
	pt := paint(p, {0, 0, 0, 1})
	cls := jni_find_class(env, "android/graphics/RectF")
	dst := jni_new_object(env, cls, "(FFFF)V", jv_float(f32(x)), jv_float(f32(y)), jv_float(f32(x + w)), jv_float(f32(y + h)))
	jni_call_void(env, jobject(p.native), "drawBitmap",
		"(Landroid/graphics/Bitmap;Landroid/graphics/Rect;Landroid/graphics/RectF;Landroid/graphics/Paint;)V",
		jv_obj(jobject(b.native)), jv_obj(nil), jv_obj(dst), jv_obj(pt))
	jni_delete_local_ref(env, dst)
	jni_delete_local_ref(env, cls)
}

@(private)
_image_init :: proc(h: ^Image_Handle) {
	env := g_android.env
	cls := jni_find_class(env, "nv/NvImageView")
	v := jni_new_object(env, cls, "(Landroid/content/Context;)V", jv_obj(g_android.activity))
	scale := enum_value(env, "android/widget/ImageView$ScaleType", "(Ljava/lang/String;)Landroid/widget/ImageView$ScaleType;", image_scale_types[h.image.fit])
	jni_call_void(env, v, "setScaleType", "(Landroid/widget/ImageView$ScaleType;)V", jv_obj(scale))
	h.root = View(jni_new_global_ref(env, v)) // also the handle's reference: a download may land after its page popped
	h.view = rawptr(h.root)
	jni_delete_local_ref(env, scale)
	jni_delete_local_ref(env, v)
	jni_delete_local_ref(env, cls)
	_image_set_bitmap(h)
}

@(private)
_image_set_bitmap :: proc(h: ^Image_Handle) {
	env := g_android.env
	v := jobject(h.view)
	jni_call_void(env, v, "setImageBitmap", "(Landroid/graphics/Bitmap;)V", jv_obj(h.bitmap != nil ? jobject(h.bitmap.native) : nil))
	s := image_natural_size(h)
	jni_call_void(env, v, "setNaturalSize", "(II)V", jv_int(android_dp(s.x)), jv_int(android_dp(s.y)))
}

// A relative path names an APK asset (app/assets, packaged by android/build.sh).
@(private)
_asset_read :: proc(path: string, allocator := context.allocator) -> []u8 {
	if os.is_absolute_path(path) do return asset_read_file(path, allocator)
	env := g_android.env
	name := jni_string(env, strings.clone_to_cstring(path, context.temp_allocator))
	defer jni_delete_local_ref(env, name)
	arr := jni_call_static_object(env, "nv/NvFetch", "readAsset", "(Landroid/content/Context;Ljava/lang/String;)[B",
		jv_obj(g_android.activity), jv_obj(name))
	defer if arr != nil do jni_delete_local_ref(env, arr)
	return jni_bytes_clone(env, arr, allocator)
}

@(private)
_fetch_start :: proc(f: ^Fetch) {
	env := g_android.env
	url := jni_string(env, strings.clone_to_cstring(f.url, context.temp_allocator))
	defer jni_delete_local_ref(env, url)
	jni_call_static_void(env, "nv/NvFetch", "start", "(JLjava/lang/String;)V", jv_long(i64(uintptr(f))), jv_obj(url))
}

@(export, link_name="Java_nv_NvFetch_nativeOnFetch")
jni_fetch_on_fetch :: proc "c" (env: JNI_Env, _: jclass, req: jlong, data: jobject) {
	f := (^Fetch)(uintptr(req))
	context = f.ctx
	g_android.env = env
	f.data = jni_bytes_clone(env, data, runtime.heap_allocator())
	fetch_notify(f)
}
