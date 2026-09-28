#+build linux:android
package nv

// Android image backend. BitmapFactory decodes into an android.graphics.Bitmap (a global ref).
// The widget is an nv.NvImageView (an ImageView whose natural size comes from here, so an
// explicit size can be smaller than the bitmap) scaled by its ScaleType. Downloads and assets go
// through nv.NvFetch (Java): a download runs on a Java thread and comes back to
// nativeOnFetch on the UI thread.

import "base:runtime"
import "core:os"

// ImageView.ScaleType names, indexed by Fit.
@(private) image_scale_types := [Fit]string{
	.Contain = "FIT_CENTER",
	.Cover   = "CENTER_CROP",
	.Fill    = "FIT_XY",
}

@(private)
_bitmap_decode :: proc(b: ^Bitmap, data: []u8) -> bool {
	env := g_android.env
	bmp := bitmap_factory_decode_byte_array(env, data, 0, len(data))
	if bmp == nil do return false
	defer jni_delete_local_ref(env, bmp)
	b.native = rawptr(jni_new_global_ref(env, bmp))
	b.width = int(bitmap_get_width(env, bmp))
	b.height = int(bitmap_get_height(env, bmp))
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
	dst := rect_f_new(env, f32(x), f32(y), f32(x + w), f32(y + h))
	canvas_draw_bitmap(env, jobject(p.native), jobject(b.native), nil, dst, pt)
	jni_delete_local_ref(env, dst)
}

@(private)
_image_init :: proc(h: ^Image_Handle) {
	env := g_android.env
	v := nv_image_view_new(env, g_android.activity)
	scale := image_view_scale_type_value_of(env, image_scale_types[h.image.fit])
	image_view_set_scale_type(env, v, scale)
	h.root = View(jni_new_global_ref(env, v)) // also the handle's reference: a download may land after its page popped
	h.view = rawptr(h.root)
	jni_delete_local_ref(env, scale)
	jni_delete_local_ref(env, v)
	_image_set_bitmap(h)
}

@(private)
_image_set_bitmap :: proc(h: ^Image_Handle) {
	env := g_android.env
	v := jobject(h.view)
	image_view_set_image_bitmap(env, v, h.bitmap != nil ? jobject(h.bitmap.native) : nil)
	s := image_natural_size(h)
	nv_image_view_set_natural_size(env, v, android_dp(s.x), android_dp(s.y))
}

// A relative path names an APK asset (app/assets, packaged by android/build.sh).
@(private)
_asset_read :: proc(path: string, allocator := context.allocator) -> []u8 {
	if os.is_absolute_path(path) do return asset_read_file(path, allocator)
	env := g_android.env
	arr := nv_fetch_read_asset(env, g_android.activity, path)
	defer if arr != nil do jni_delete_local_ref(env, arr)
	return jni_bytes_clone(env, arr, allocator)
}

@(private)
_fetch_start :: proc(f: ^Fetch) {
	nv_fetch_start(g_android.env, i64(uintptr(f)), f.url)
}

@(export, link_name="Java_nv_NvFetch_nativeOnFetch")
jni_fetch_on_fetch :: proc "c" (env: JNI_Env, _: jclass, req: jlong, data: jobject) {
	f := (^Fetch)(uintptr(req))
	context = f.ctx
	g_android.env = env
	f.data = jni_bytes_clone(env, data, runtime.heap_allocator())
	fetch_notify(f)
}
