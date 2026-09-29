#+build windows
package nv

// Windows font backend. AddFontMemResourceEx installs the bytes as a process-private GDI font
// (GDI copies them) that a LOGFONT selects by family name; the weight and slant from the file
// pin the loaded face when the family is installed too. GDI substitutes another face silently
// for a name it doesn't know, which is why the name comes from the file, not the app, and names
// longer than 31 UTF-16 units can't be selected at all. Controls keep the HFONT they are given,
// so a Font's sized HFONTs are cached in Font.extra (style_font, theme_windows.odin) and deleted
// with it.

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
	f.extra = new(map[Font_Key]win.HFONT)
	return true
}

@(private)
_font_free :: proc(f: ^Font) {
	cache := (^map[Font_Key]win.HFONT)(f.extra)
	for _, hfont in cache^ {
		delete_key(&g_theme_windows.heights, hfont)
		win.DeleteObject(win.HGDIOBJ(hfont))
	}
	delete(cache^)
	free(cache)
	RemoveFontMemResourceEx(win.HANDLE(f.native))
}
