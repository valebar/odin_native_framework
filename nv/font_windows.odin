#+build windows
package nv

// Windows font backend. AddFontMemResourceEx installs the bytes as a process-private GDI font
// (GDI copies them) that a LOGFONT selects by family name; the weight and slant from the file
// pin the loaded face when the family is installed too. GDI substitutes another face silently
// for a name it doesn't know, which is why the name comes from the file, not the app, and names
// longer than 31 UTF-16 units can't be selected at all. Controls keep the HFONT they are given,
// so their sized HFONTs are cached: per Font in Font.extra, and in g_windows for the system font.
// The canvas makes and deletes its own per call (windows_logfont), since an app may draw text at
// any number of sizes.

import win "core:sys/windows"

@(private)
_font_load :: proc(f: ^Font, data: []u8) -> bool {
	n: win.DWORD
	h := win.AddFontMemResourceEx(rawptr(raw_data(data)), win.DWORD(len(data)), nil, &n)
	if h == nil do return false
	if n == 0 { // installed, but with no usable face
		RemoveFontMemResourceEx(h)
		return false
	}
	f.native = rawptr(h)
	f.extra = new([dynamic]Win_Font)
	return true
}

@(private)
_font_free :: proc(f: ^Font) {
	cache := (^[dynamic]Win_Font)(f.extra)
	for c in cache do win.DeleteObject(win.HGDIOBJ(c.hfont))
	delete(cache^)
	free(cache)
	RemoveFontMemResourceEx(win.HANDLE(f.native))
}

// The LOGFONT of `font` at `size` (dp), or of the message font (the title font when bold) at
// its own size or at `size`.
@(private)
windows_logfont :: proc(font: ^Font, size: f64, bold: bool) -> (lf: win.LOGFONTW) {
	win.GetObjectW(win.HANDLE(bold ? g_windows.title : g_windows.font), size_of(lf), &lf)
	if size != 0 do lf.lfHeight = -px(size)
	if font != nil {
		lf.lfWeight = i32(font.weight)
		lf.lfItalic = font.italic ? 1 : 0
		lf.lfCharSet = win.DEFAULT_CHARSET
		lf.lfFaceName = {}
		copy(lf.lfFaceName[:len(lf.lfFaceName) - 1], win.utf8_to_utf16(font.family, context.temp_allocator))
	}
	return
}

// The HFONT a control keeps, from windows_logfont. Cached: never delete the result.
@(private)
windows_font :: proc(font: ^Font, size: f64, bold: bool) -> win.HFONT {
	if font == nil && size == 0 do return bold ? g_windows.title : g_windows.font
	lf := windows_logfont(font, size, bold)
	cache := font != nil ? (^[dynamic]Win_Font)(font.extra) : &g_windows.sized_fonts
	for c in cache do if c.height == lf.lfHeight && c.weight == lf.lfWeight do return c.hfont
	hfont := win.CreateFontIndirectW(&lf)
	append(cache, Win_Font{lf.lfHeight, lf.lfWeight, hfont})
	return hfont
}
