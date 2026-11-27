#+build linux:android
#+private
package nv

// Android image backend. BitmapFactory decodes into an android.graphics.Bitmap (a global ref);
// pixels go into a mutable ARGB_8888 Bitmap through AndroidBitmap_lockPixels (libjnigraphics).
// The widget is an nv.NvImageView (an ImageView whose natural size comes from here, so an
// explicit size can be smaller than the bitmap) scaled by its ScaleType. Downloads and assets go
// through nv.NvFetch (Java): a download runs on a Java thread and comes back to
// nativeOnFetch on the UI thread.

import "core:os"

foreign import jnigraphics "system:jnigraphics"

@(private) Android_Bitmap_Info :: struct {
	width, height, stride: u32,
	format:                i32,
	flags:                 u32,
}

@(private) ANDROID_BITMAP_FORMAT_RGBA_8888 :: 1

@(private)
foreign jnigraphics {
	AndroidBitmap_getInfo      :: proc "c" (env: JNI_Env, bitmap: jobject, info: ^Android_Bitmap_Info) -> i32 ---
	AndroidBitmap_lockPixels   :: proc "c" (env: JNI_Env, bitmap: jobject, pixels: ^rawptr) -> i32 ---
	AndroidBitmap_unlockPixels :: proc "c" (env: JNI_Env, bitmap: jobject) -> i32 ---
}

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
// opaque first, since its alpha would fade the image. The destination is the canvas's one RectF.
@(private)
_draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	env := g_android.env
	pt := paint(p, {0, 0, 0, 1})
	dst := (^Android_Canvas)(p.h.extra).rect
	rect_f_set(env, dst, f32(x), f32(y), f32(x + w), f32(y + h))
	canvas_draw_bitmap(env, jobject(p.native), jobject(b.native), nil, dst, pt)
}

@(private)
_image_init :: proc(h: ^Image_Handle) {
	env := g_android.env
	v := nv_image_view_new(env, g_android.activity)
	scale := image_view_scale_type_value_of(env, image_scale_types[h.image.fit])
	image_view_set_scale_type(env, v, scale)
	h.root = View(android_own_ref(env, v))
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
	f.data = jni_bytes_clone(env, data, nv_heap())
	fetch_notify(f)
}

// Bitmap.createBitmap(w, h, ARGB_8888) is mutable; the global ref goes like a decoded one's.
@(private)
_bitmap_rgba :: proc(b: ^Bitmap, pixels: []u8) -> bool {
	env := g_android.env
	config := bitmap_config_value_of(env, "ARGB_8888")
	bmp := bitmap_create_bitmap(env, b.width, b.height, config)
	jni_delete_local_ref(env, config)
	if bmp == nil do return false
	defer jni_delete_local_ref(env, bmp)
	if !android_bitmap_copy(env, bmp, b.width, b.height, pixels) do return false
	b.native = rawptr(jni_new_global_ref(env, bmp))
	return true
}

@(private)
_bitmap_set_rgba :: proc(b: ^Bitmap, pixels: []u8) -> bool {
	return android_bitmap_copy(g_android.env, jobject(b.native), b.width, b.height, pixels)
}

// Copies straight-alpha RGBA rows into the locked Bitmap, premultiplied as ARGB_8888 holds them
// (R, G, B, A in memory) at its own stride. Unlocking bumps the bitmap's generation, so the
// renderer uploads the new pixels on the next draw.
@(private)
android_bitmap_copy :: proc "contextless" (env: JNI_Env, bmp: jobject, w, h: int, pixels: []u8) -> bool {
	info: Android_Bitmap_Info
	if AndroidBitmap_getInfo(env, bmp, &info) != 0 do return false
	if info.format != ANDROID_BITMAP_FORMAT_RGBA_8888 || int(info.width) != w || int(info.height) != h do return false
	dst: rawptr
	if AndroidBitmap_lockPixels(env, bmp, &dst) != 0 do return false
	defer AndroidBitmap_unlockPixels(env, bmp)
	if dst == nil do return false
	for y in 0 ..< h {
		src := pixels[y * w * 4:][:w * 4]
		row := ([^]u8)(dst)[y * int(info.stride):][:w * 4]
		for x := 0; x < w * 4; x += 4 {
			a := u32(src[x + 3])
			if a == 255 {
				row[x], row[x + 1], row[x + 2], row[x + 3] = src[x], src[x + 1], src[x + 2], 255
				continue
			}
			row[x]     = u8((u32(src[x]) * a + 127) / 255)
			row[x + 1] = u8((u32(src[x + 1]) * a + 127) / 255)
			row[x + 2] = u8((u32(src[x + 2]) * a + 127) / 255)
			row[x + 3] = u8(a)
		}
	}
	return true
}
