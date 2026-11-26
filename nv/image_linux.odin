#+build linux:default
package nv

// Linux image backend. GTK decodes (gdk_texture_new_from_bytes, GTK 4.6), and the pixels are
// downloaded once into a cairo image surface, which is all the bitmap keeps: both the canvas and
// the widget draw with cairo. The widget is a GtkDrawingArea rather than a GtkPicture, since its
// natural size (gtk_drawing_area_set_content_width / height) can then be exactly the requested
// one. Downloads use libcurl on the worker thread (fetch_thread.odin) and come back through
// g_idle_add, which is thread-safe.

import "base:runtime"
import "core:strings"

foreign import curl "system:curl"

@(private) CURL_GLOBAL_DEFAULT    :: i64(3)
@(private) CURLOPT_WRITEDATA      :: i32(10001)
@(private) CURLOPT_URL            :: i32(10002)
@(private) CURLOPT_USERAGENT      :: i32(10018)
@(private) CURLOPT_WRITEFUNCTION  :: i32(20011)
@(private) CURLOPT_FAILONERROR    :: i32(45)
@(private) CURLOPT_FOLLOWLOCATION :: i32(52)
@(private) CURLOPT_NOSIGNAL       :: i32(99)

@(default_calling_convention="c", private)
foreign curl {
	curl_global_init  :: proc(flags: i64) -> i32 ---
	curl_easy_init    :: proc() -> rawptr ---
	curl_easy_setopt  :: proc(handle: rawptr, option: i32, #c_vararg args: ..any) -> i32 ---
	curl_easy_perform :: proc(handle: rawptr) -> i32 ---
	curl_easy_cleanup :: proc(handle: rawptr) ---
}

@(private)
_bitmap_decode :: proc(b: ^Bitmap, data: []u8) -> bool {
	bytes := g_bytes_new(raw_data(data), uint(len(data)))
	defer g_bytes_unref(bytes)
	err: ^GError
	texture := gdk_texture_new_from_bytes(bytes, &err)
	if texture == nil {
		if err != nil do g_error_free(err)
		return false
	}
	defer g_object_unref(texture)
	w, h := gdk_texture_get_width(texture), gdk_texture_get_height(texture)
	surface := cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h)
	gdk_texture_download(texture, cairo_image_surface_get_data(surface), uint(cairo_image_surface_get_stride(surface)))
	cairo_surface_mark_dirty(surface)
	b.native = surface
	b.width, b.height = int(w), int(h)
	return true
}

@(private)
_bitmap_free :: proc(b: ^Bitmap) {
	cairo_surface_destroy((^cairo_surface_t)(b.native))
}

@(private)
_draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	cr := (^cairo_t)(p.native)
	cairo_save(cr)
	cairo_translate(cr, x, y)
	cairo_scale(cr, w / f64(b.width), h / f64(b.height))
	cairo_set_source_surface(cr, (^cairo_surface_t)(b.native), 0, 0)
	cairo_new_path(cr)
	cairo_rectangle(cr, 0, 0, f64(b.width), f64(b.height))
	cairo_fill(cr)
	cairo_restore(cr)
}

@(private)
_image_init :: proc(h: ^Image_Handle) {
	area := gtk_drawing_area_new()
	gtk_drawing_area_set_draw_func(area, rawptr(on_image_draw), h, nil)
	h.root = View(area)
	h.view = area // owned by the tree; a download that lands after the scope died is dropped (image_dispose)
	image_update_size(h)
}

@(private)
_image_set_bitmap :: proc(h: ^Image_Handle) {
	image_update_size(h)
	gtk_widget_queue_draw((^GtkWidget)(h.view))
}

@(private)
image_update_size :: proc(h: ^Image_Handle) {
	s := image_natural_size(h)
	gtk_drawing_area_set_content_width((^GtkWidget)(h.view), i32(s.x + 0.5))
	gtk_drawing_area_set_content_height((^GtkWidget)(h.view), i32(s.y + 0.5))
}

@(private)
on_image_draw :: proc "c" (_: ^GtkWidget, cr: ^cairo_t, width, height: i32, user: gpointer) {
	h := (^Image_Handle)(user)
	if h.bitmap == nil do return
	context = h.ctx
	r := image_fit_rect(h.image.fit, h.bitmap, f64(width), f64(height))
	p := Painter{native = cr}
	_draw_image(&p, h.bitmap, r[0], r[1], r[2], r[3])
}

// Runs on the worker thread, with its own context: allocates with nv_heap only.
@(private)
_http_get :: proc(url: string) -> []u8 {
	heap := nv_heap()
	curl_url := strings.clone_to_cstring(url, heap)
	defer delete(curl_url, heap)
	c := curl_easy_init()
	if c == nil do return nil
	defer curl_easy_cleanup(c)

	out := make([dynamic]u8, heap)
	curl_easy_setopt(c, CURLOPT_URL, curl_url)
	curl_easy_setopt(c, CURLOPT_USERAGENT, cstring("nv"))
	curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, i64(1))
	curl_easy_setopt(c, CURLOPT_FAILONERROR, i64(1))
	curl_easy_setopt(c, CURLOPT_NOSIGNAL, i64(1)) // no SIGALRM on a thread
	curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, rawptr(curl_write))
	curl_easy_setopt(c, CURLOPT_WRITEDATA, rawptr(&out))
	if curl_easy_perform(c) != 0 {
		delete(out)
		return nil
	}
	return out[:]
}

@(private)
curl_write :: proc "c" (ptr: [^]u8, size, nmemb: uint, user: rawptr) -> uint {
	context = runtime.default_context()
	append((^[dynamic]u8)(user), ..ptr[:size * nmemb])
	return size * nmemb
}

@(private)
_post_main :: proc(f: ^Fetch) {
	g_idle_add(fetch_idle, f)
}

@(private)
fetch_idle :: proc "c" (data: gpointer) -> gboolean {
	f := (^Fetch)(data)
	context = f.ctx
	fetch_notify(f)
	return G_SOURCE_REMOVE
}
