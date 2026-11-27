#+build windows
#+private
package nv

// Windows image backend. GDI+ decodes (GdipCreateBitmapFromStream over an SHCreateMemStream copy
// of the bytes, which GDI+ keeps reading from, so the stream lives as long as the bitmap) and
// draws. The widget is an "NVImage" window painted like the canvas. Downloads use WinINet on the
// worker thread (fetch_thread.odin) and come back as WM_NV_FETCHED to the main window. A bitmap
// from pixels is a 32bppARGB GpBitmap (straight alpha, BGRA in memory) written through LockBits.

import win "core:sys/windows"

foreign import shlwapi "system:Shlwapi.lib"
foreign import wininet "system:Wininet.lib"

@(private) WM_NV_FETCHED :: win.WM_APP + 2 // lparam: the ^Fetch

@(private) HINTERNET :: rawptr
@(private) INTERNET_OPEN_TYPE_PRECONFIG :: 0
@(private) INTERNET_FLAG_NO_UI          :: 0x0000_0200

@(private) GP_PIXEL_FORMAT_32BPP_ARGB :: i32(0x0026200A)
@(private) GP_IMAGE_LOCK_WRITE        :: u32(2)

@(private) GpRect :: struct { x, y, w, h: i32 }

@(private) GpBitmapData :: struct {
	width, height: u32,
	stride:        i32,
	format:        i32,
	scan0:         [^]u8,
	reserved:      uintptr,
}

@(default_calling_convention="system", private)
foreign shlwapi {
	SHCreateMemStream :: proc(pInit: [^]u8, cbInit: win.UINT) -> ^win.IStream ---
}

@(default_calling_convention="system", private)
foreign wininet {
	InternetOpenW       :: proc(agent: win.LPCWSTR, access: win.DWORD, proxy, bypass: win.LPCWSTR, flags: win.DWORD) -> HINTERNET ---
	InternetOpenUrlW    :: proc(h: HINTERNET, url: win.LPCWSTR, headers: win.LPCWSTR, headers_len, flags: win.DWORD, ctx: win.DWORD_PTR) -> HINTERNET ---
	InternetReadFile    :: proc(h: HINTERNET, buf: rawptr, n: win.DWORD, read: ^win.DWORD) -> win.BOOL ---
	InternetCloseHandle :: proc(h: HINTERNET) -> win.BOOL ---
}

@(private)
_bitmap_decode :: proc(b: ^Bitmap, data: []u8) -> bool {
	stream := SHCreateMemStream(raw_data(data), win.UINT(len(data)))
	if stream == nil do return false
	img: GpImage
	if GdipCreateBitmapFromStream(stream, &img) != 0 {
		(^win.IUnknown)(stream)->Release()
		return false
	}
	w, h: u32
	GdipGetImageWidth(img, &w)
	GdipGetImageHeight(img, &h)
	b.native, b.extra = img, stream
	b.width, b.height = int(w), int(h)
	return true
}

@(private)
_bitmap_free :: proc(b: ^Bitmap) {
	GdipDisposeImage(b.native)
	if b.extra != nil do (^win.IUnknown)(b.extra)->Release() // a bitmap from pixels has no stream
}

@(private)
_bitmap_rgba :: proc(b: ^Bitmap, pixels: []u8) -> bool {
	img: GpImage
	if GdipCreateBitmapFromScan0(i32(b.width), i32(b.height), 0, GP_PIXEL_FORMAT_32BPP_ARGB, nil, &img) != 0 do return false
	if !bitmap_write_rgba(img, b.width, b.height, pixels) {
		GdipDisposeImage(img)
		return false
	}
	b.native = img
	return true
}

@(private)
_bitmap_set_rgba :: proc(b: ^Bitmap, pixels: []u8) -> bool {
	return bitmap_write_rgba(b.native, b.width, b.height, pixels)
}

// RGBA rows into the bitmap's BGRA rows (GDI+ keeps 32bppARGB unpremultiplied, so only R and B swap).
@(private)
bitmap_write_rgba :: proc "contextless" (img: GpImage, w, h: int, pixels: []u8) -> bool {
	rect := GpRect{0, 0, i32(w), i32(h)}
	data: GpBitmapData
	if GdipBitmapLockBits(img, &rect, GP_IMAGE_LOCK_WRITE, GP_PIXEL_FORMAT_32BPP_ARGB, &data) != 0 do return false
	for y in 0 ..< h {
		src := pixels[y * w * 4:][:w * 4]
		dst := data.scan0[int(data.stride) * y:]
		for x in 0 ..< w {
			i := x * 4
			dst[i], dst[i + 1], dst[i + 2], dst[i + 3] = src[i + 2], src[i + 1], src[i], src[i + 3]
		}
	}
	return GdipBitmapUnlockBits(img, &data) == 0
}

// The interpolation and pixel offset modes are set once per Graphics (canvas_paint /
// image_paint); the half-pixel offset also keeps a seam off the image's edges.
@(private)
_draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	GdipDrawImageRect(p.native, b.native, f32(x), f32(y), f32(w), f32(h))
}

@(private)
_image_init :: proc(h: ^Image_Handle) {
	wnd := win.CreateWindowExW(0, wstr(CLASS_IMAGE), nil, win.WS_CHILD | win.WS_VISIBLE,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)
	h.root = View(wnd)
	h.view = rawptr(wnd)
}

// The window is gone once its page popped (a download may finish later).
@(private)
_image_set_bitmap :: proc(h: ^Image_Handle) {
	wnd := win.HWND(h.view)
	if !win.IsWindow(wnd) do return
	win.InvalidateRect(wnd, nil, false)
	flex_relayout_ancestors(wnd) // measure changed, most likely: it is cheap enough either way
}

@(private)
image_measure :: proc(hwnd: win.HWND) -> [2]i32 {
	h := (^Image_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
	if h == nil do return {}
	s := image_natural_size(h)
	return {px(s.x), px(s.y)}
}

@(private)
image_paint :: proc(hwnd: win.HWND, h: ^Image_Handle) {
	ps: win.PAINTSTRUCT
	dc := win.BeginPaint(hwnd, &ps)
	defer win.EndPaint(hwnd, &ps)
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	if rc.right <= 0 || rc.bottom <= 0 do return

	mem := win.CreateCompatibleDC(dc)
	defer win.DeleteDC(mem)
	bmp := dib_section(rc.right, rc.bottom)
	defer win.DeleteObject(win.HGDIOBJ(bmp))
	old := win.SelectObject(mem, win.HGDIOBJ(bmp))
	defer win.SelectObject(mem, old)
	win.FillRect(mem, &rc, background_brush_of(win.GetParent(hwnd))) // the letterbox shows the background

	if h.bitmap != nil {
		g: GpGraphics
		GdipCreateFromHDC(mem, &g)
		GdipSetPixelOffsetMode(g, GP_PIXEL_OFFSET_HALF)
		GdipSetInterpolationMode(g, GP_INTERPOLATION_HIGH_QUALITY_BICUBIC)
		scale := f32(g_windows.dpi) / 96
		GdipScaleWorldTransform(g, scale, scale, GP_MATRIX_ORDER_PREPEND)
		r := image_fit_rect(h.image.fit, h.bitmap, dp(rc.right), dp(rc.bottom))
		p := Painter{native = g, dc = mem}
		_draw_image(&p, h.bitmap, r[0], r[1], r[2], r[3])
		GdipDeleteGraphics(g)
	}

	win.BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, win.SRCCOPY)
}

@(private)
image_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := (^Image_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
	if h == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx

	switch msg {
	case win.WM_PAINT:
		image_paint(hwnd, h)
		return 0
	case win.WM_ERASEBKGND:
		return 1
	case win.WM_SIZE:
		win.InvalidateRect(hwnd, nil, false)
		return 0
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

// Runs on the worker thread, with its own context: allocates with nv_heap only.
@(private)
_http_get :: proc(url: string) -> []u8 {
	heap := nv_heap()
	agent := win.utf8_to_wstring("nv", heap)
	defer free(rawptr(agent), heap)
	wurl := win.utf8_to_wstring(url, heap)
	defer free(rawptr(wurl), heap)

	inet := InternetOpenW(agent, INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0)
	if inet == nil do return nil
	defer InternetCloseHandle(inet)
	req := InternetOpenUrlW(inet, wurl, nil, 0, INTERNET_FLAG_NO_UI, 0)
	if req == nil do return nil
	defer InternetCloseHandle(req)

	out := make([dynamic]u8, heap)
	buf: [16 * 1024]u8
	for {
		n: win.DWORD
		if !InternetReadFile(req, &buf[0], len(buf), &n) {
			delete(out)
			return nil
		}
		if n == 0 do break
		append(&out, ..buf[:n])
	}
	return out[:]
}

@(private)
_post_main :: proc(f: ^Fetch) {
	win.PostMessageW(g_windows.parking, WM_NV_FETCHED, 0, win.LPARAM(uintptr(f)))
}
