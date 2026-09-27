#+build windows
package nv

// Windows image backend. GDI+ decodes (GdipCreateBitmapFromStream over an SHCreateMemStream copy
// of the bytes, which GDI+ keeps reading from, so the stream lives as long as the bitmap) and
// draws. The widget is an "NVImage" window painted like the canvas. Downloads use WinINet on the
// worker thread (fetch_thread.odin) and come back as WM_NV_FETCHED to the main window.

import "base:runtime"
import win "core:sys/windows"

foreign import shlwapi "system:Shlwapi.lib"
foreign import wininet "system:Wininet.lib"

@(private) WM_NV_FETCHED :: win.WM_APP + 2 // lparam: the ^Fetch

@(private) HINTERNET :: rawptr
@(private) INTERNET_OPEN_TYPE_PRECONFIG :: 0
@(private) INTERNET_FLAG_NO_UI          :: 0x0000_0200

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
	(^win.IUnknown)(b.extra)->Release()
}

@(private)
_draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	GdipSetInterpolationMode(p.native, GP_INTERPOLATION_HIGH_QUALITY_BICUBIC)
	GdipSetPixelOffsetMode(p.native, GP_PIXEL_OFFSET_HIGH_QUALITY) // no half-pixel seam at the edges
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
	bmp := win.CreateCompatibleBitmap(dc, rc.right, rc.bottom)
	defer win.DeleteObject(win.HGDIOBJ(bmp))
	old := win.SelectObject(mem, win.HGDIOBJ(bmp))
	defer win.SelectObject(mem, old)
	win.FillRect(mem, &rc, background_brush_of(win.GetParent(hwnd))) // the letterbox shows the background

	if h.bitmap != nil {
		g: GpGraphics
		GdipCreateFromHDC(mem, &g)
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

// Runs on the worker thread, with its own context: allocates on the heap only.
@(private)
_http_get :: proc(url: string) -> []u8 {
	heap := runtime.heap_allocator()
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
