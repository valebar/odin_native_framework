#+build windows
#+private
package nv

// Windows font backend. AddFontMemResourceEx installs the bytes as a process-private GDI font
// (GDI copies them) that a LOGFONT selects by family name; the weight and slant from the file
// pin the loaded face when the family is installed too. GDI substitutes another face silently
// for a name it doesn't know, which is why the name comes from the file, not the app, and names
// longer than 31 UTF-16 units can't be selected at all. Controls keep the HFONT they are given,
// so a Font's sized HFONTs are cached in Font.extra (style_font, theme_windows.odin) and deleted
// with it. The canvas draws with DirectWrite (canvas_windows.odin), which doesn't see GDI's
// private fonts: the bytes also go into an in-memory font file of a collection of their own
// (Windows 10 1703+), whose family name is the one DirectWrite gives the face.

import win "core:sys/windows"

// Font.extra on Windows.
@(private) Font_Windows :: struct {
	hfonts: map[Font_Key]win.HFONT,
	dwrite: Font_Dwrite,
}

@(private) Font_Dwrite :: struct {
	collection: ^IDWriteFontCollection, // nil where DirectWrite can't load it: the canvas falls back to the theme's font
	family:     []u16,                  // NUL-terminated
}

@(private)
font_hfonts :: proc(f: ^Font) -> ^map[Font_Key]win.HFONT {
	return &(^Font_Windows)(f.extra).hfonts
}

@(private)
font_dwrite :: proc(f: ^Font) -> ^Font_Dwrite {
	return &(^Font_Windows)(f.extra).dwrite
}

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
	fw := new(Font_Windows)
	f.extra = fw
	fw.dwrite = dwrite_font_load(data)
	return true
}

// The bytes as DirectWrite's (copied: no owner is given), in a collection of their own.
@(private)
dwrite_font_load :: proc(data: []u8) -> (out: Font_Dwrite) {
	if !dwrite_start() || !g_d2d.dwrite5 do return
	fac := g_d2d.dwrite
	if g_d2d.loader == nil {
		if fac->CreateInMemoryFontFileLoader(&g_d2d.loader) < 0 do return
		if fac->RegisterFontFileLoader(g_d2d.loader) < 0 {
			com_release(g_d2d.loader)
			g_d2d.loader = nil
			return
		}
	}
	file: ^IDWriteFontFile
	if g_d2d.loader->CreateInMemoryFontFileReference(fac, raw_data(data), u32(len(data)), nil, &file) < 0 do return
	defer com_release(file)
	builder: ^IDWriteFontSetBuilder1
	if fac->CreateFontSetBuilder1(&builder) < 0 do return
	defer com_release(builder)
	if builder->AddFontFile(file) < 0 do return
	set: ^IDWriteFontSet
	if builder->CreateFontSet(&set) < 0 do return
	defer com_release(set)
	coll: ^IDWriteFontCollection
	if fac->CreateFontCollectionFromFontSet(set, &coll) < 0 do return
	fam: ^IDWriteFontFamily
	names: ^IDWriteLocalizedStrings
	n: u32
	ok := coll->GetFontFamilyCount() > 0 && coll->GetFontFamily(0, &fam) >= 0 &&
		fam->GetFamilyNames(&names) >= 0 && names->GetStringLength(0, &n) >= 0
	if ok {
		out.family = make([]u16, n + 1)
		ok = names->GetString(0, raw_data(out.family), n + 1) >= 0
	}
	com_release(names)
	com_release(fam)
	if !ok {
		delete(out.family)
		com_release(coll)
		return {}
	}
	out.collection = coll
	return
}

@(private)
_font_free :: proc(f: ^Font) {
	fw := (^Font_Windows)(f.extra)
	for _, hfont in fw.hfonts {
		delete_key(&g_theme_windows.heights, hfont)
		win.DeleteObject(win.HGDIOBJ(hfont))
	}
	delete(fw.hfonts)
	text_formats_drop(f)
	com_release(fw.dwrite.collection)
	delete(fw.dwrite.family)
	free(fw)
	RemoveFontMemResourceEx(win.HANDLE(f.native))
}
