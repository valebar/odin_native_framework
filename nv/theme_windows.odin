#+build windows
#+private
package nv

// Windows theme backend. Win32 has no light / dark switch for an app, so the pieces are set one
// by one: the title bar through DWM, the common controls through their dark visual styles
// ("DarkMode_Explorer" for buttons and the ListView, "DarkMode_CFD" for edits), and everything
// our own windows paint (backgrounds, labels, edits, list rows, the dialog card, the canvas)
// from the palette's brushes. uxtheme's unnamed exports SetPreferredAppMode (ordinal 135) and
// AllowDarkModeForWindow (133) make the controls' scroll bars follow; they are optional. The OS
// setting is AppsUseLightTheme in the registry, and WM_SETTINGCHANGE "ImmersiveColorSet"
// reports a change.
//
// Fonts: a Text_Style becomes a font derived from the widget's default font (message font,
// bold, title), or from a loaded Font's face (font_windows.odin), cached by height, weight and
// italic and never deleted.

import win "core:sys/windows"

foreign import dwmapi "system:Dwmapi.lib"

@(default_calling_convention="system", private)
foreign dwmapi {
	DwmGetColorizationColor :: proc(pcrColorization: ^win.DWORD, pfOpaqueBlend: ^win.BOOL) -> win.HRESULT ---
}

@(private) LVM_SETBKCOLOR :: win.LVM_FIRST + 1

@(private) Font_Key :: struct {
	height: i32,
	weight: i32,
	italic: bool,
}

@(private) g_theme_windows: struct {
	fonts:        map[Font_Key]win.HFONT,
	heights:      map[win.HFONT]i32, // line height in px of every font we made, the base fonts included
	bg:           win.HBRUSH,        // palette.background
	surface:      win.HBRUSH,        // palette.surface: edits
	light:        win.HBRUSH,        // DIALOG_LIGHT: a light dialog's card and edits, whatever the theme
	allow_dark:   proc "system" (hwnd: win.HWND, allow: win.BOOL) -> win.BOOL, // uxtheme #133; may be nil
}

@(private)
_theme_system_dark :: proc() -> bool {
	value: win.DWORD = 1
	size := win.DWORD(size_of(value))
	key := wstr(`Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`)
	if win.RegGetValueW(win.HKEY_CURRENT_USER, key, wstr("AppsUseLightTheme"), win.RRF_RT_REG_DWORD, nil, &value, &size) != 0 do return false
	return value == 0
}

@(private)
_theme_system_accent :: proc() -> Color {
	c: win.DWORD
	opaque: win.BOOL
	if DwmGetColorizationColor(&c, &opaque) != 0 do return {}
	return {f32(c >> 16 & 0xff) / 255, f32(c >> 8 & 0xff) / 255, f32(c & 0xff) / 255, 1}
}

// Nothing to tell the system: every window reads g_dark when it paints or is created.
@(private)
_theme_apply_mode :: proc() {
	if g_theme_windows.allow_dark != nil do return
	uxtheme := win.LoadLibraryW(wstr("uxtheme.dll"))
	if uxtheme == nil do return
	ordinal :: proc(n: uintptr) -> cstring { return transmute(cstring)n } // MAKEINTRESOURCE
	set_preferred_app_mode := cast(proc "system" (mode: i32) -> i32)win.GetProcAddress(uxtheme, ordinal(135))
	if set_preferred_app_mode != nil do set_preferred_app_mode(1) // AllowDark
	g_theme_windows.allow_dark = cast(proc "system" (hwnd: win.HWND, allow: win.BOOL) -> win.BOOL)win.GetProcAddress(uxtheme, ordinal(133))
}

@(private)
_theme_recolor :: proc() {
	theme_windows_brushes()
	theme_window_frame(g_windows.parking)
	win.EnumChildWindows(g_windows.parking, proc "system" (hwnd: win.HWND, _: win.LPARAM) -> win.BOOL {
		context = g_windows.ctx
		theme_control(hwnd)
		return true
	}, 0)
	win.RedrawWindow(g_windows.parking, nil, nil, .RDW_ERASE | .RDW_INVALIDATE | .RDW_ALLCHILDREN | .RDW_FRAME)
}

// The palette's brushes, remade for the current light / dark.
@(private)
theme_windows_brushes :: proc() {
	p := theme_palette()
	for b in ([]win.HBRUSH{g_theme_windows.bg, g_theme_windows.surface}) {
		if b != nil do win.DeleteObject(win.HGDIOBJ(b))
	}
	g_theme_windows.bg = win.CreateSolidBrush(colorref(p.background))
	g_theme_windows.surface = win.CreateSolidBrush(colorref(p.surface))
	if g_theme_windows.light == nil do g_theme_windows.light = win.CreateSolidBrush(colorref(DIALOG_LIGHT))
}

// The main window's title bar, light or dark; its border stays the system's.
@(private)
theme_window_frame :: proc(wnd: win.HWND) {
	dark := win.BOOL(g_dark)
	win.DwmSetWindowAttribute(wnd, win.DWORD(win.DWMWINDOWATTRIBUTE.DWMWA_USE_IMMERSIVE_DARK_MODE), &dark, size_of(dark))
}

// The visual style of a common control for the current light / dark (light inside a light
// dialog); other windows are left alone (they paint from the palette).
@(private)
theme_control :: proc(hwnd: win.HWND) {
	dark := g_dark && !in_light_dialog(hwnd)
	theme: string
	switch class_name(hwnd) {
	case "Button":        theme = dark ? "DarkMode_Explorer" : ""
	case "Edit":          theme = dark ? "DarkMode_CFD" : ""
	case win.WC_LISTVIEW:
		theme = dark ? "DarkMode_Explorer" : "Explorer"
		bg := (dark ? PALETTE_DARK : PALETTE_LIGHT).background
		win.SendMessageW(hwnd, LVM_SETBKCOLOR, 0, win.LPARAM(colorref(bg)))
		win.ListView_SetTextBkColor(hwnd, colorref(bg))
	case:
		return
	}
	if g_theme_windows.allow_dark != nil do g_theme_windows.allow_dark(hwnd, win.BOOL(dark))
	win.SetWindowTheme(hwnd, theme == "" ? nil : wstr(theme), nil) // nil: back to the default style
}

@(private)
colorref :: proc "contextless" (c: Color) -> win.COLORREF {
	b :: proc "contextless" (f: f32) -> int { return int(clamp(f, 0, 1) * 255 + 0.5) }
	return win.RGB(b(c.r), b(c.g), b(c.b))
}

// Fills the client area with the background: the page's, or a container's fill
// (background_brush_of). WM_ERASEBKGND of our container windows; the classes have no brush, since
// a class brush can't follow the theme or the container.
@(private)
erase_background :: proc "contextless" (hwnd: win.HWND, dc: win.HDC) -> win.LRESULT {
	rc: win.RECT
	win.GetClientRect(hwnd, &rc)
	win.FillRect(dc, &rc, background_brush_of(hwnd))
	return 1
}

// WM_CTLCOLORSTATIC for every container: labels are drawn transparently on their background in
// their own color (a label's handle is in its GWLP_USERDATA) or the palette's text color.
@(private)
ctlcolor_static :: proc "contextless" (wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	dc := win.HDC(wparam)
	label := win.HWND(uintptr(lparam))
	color := g_dark && !in_light_dialog(label) ? PALETTE_DARK.text : PALETTE_LIGHT.text
	if h := (^Label_Handle)(uintptr(win.GetWindowLongPtrW(label, win.GWLP_USERDATA))); h != nil {
		if h.label.style.color.a > 0 do color = h.label.style.color
	}
	win.SetBkMode(dc, .TRANSPARENT)
	win.SetTextColor(dc, colorref(color))
	return win.LRESULT(uintptr(background_brush_of(label)))
}

// WM_CTLCOLORBTN: the corners around the themed push button in `lparam`, on its background.
@(private)
ctlcolor_button :: proc "contextless" (lparam: win.LPARAM) -> win.LRESULT {
	return win.LRESULT(uintptr(background_brush_of(win.HWND(uintptr(lparam)))))
}

// The font for `s` derived from `base`: zero fields keep the base's size and weight. A loaded
// font replaces the face (lfFaceName = its family; GDI substitutes silently for a name it doesn't
// know, which is why the name comes from the file) with its own weight and slant unless the
// style sets them; its HFONTs are cached in Font.extra, the system font's in g_theme_windows.
@(private)
style_font :: proc(s: Text_Style, base: win.HFONT) -> win.HFONT {
	if s.font == nil && s.size <= 0 && s.weight == .Default && !s.italic do return base
	lf: win.LOGFONTW
	win.GetObjectW(win.HANDLE(base), size_of(lf), &lf)
	if s.size > 0 do lf.lfHeight = -px(s.size)
	if f := s.font; f != nil {
		lf.lfWeight = i32(f.weight)
		lf.lfItalic = f.italic ? 1 : 0
		lf.lfCharSet = win.DEFAULT_CHARSET
		lf.lfFaceName = {}
		copy(lf.lfFaceName[:len(lf.lfFaceName) - 1], win.utf8_to_utf16(f.family, context.temp_allocator))
	}
	switch s.weight {
	case .Default:
	case .Regular:  lf.lfWeight = win.FW_NORMAL
	case .Medium:   lf.lfWeight = win.FW_MEDIUM
	case .Semibold: lf.lfWeight = win.FW_SEMIBOLD
	case .Bold:     lf.lfWeight = win.FW_BOLD
	}
	lf.lfItalic = s.italic ? 1 : lf.lfItalic
	key := Font_Key{lf.lfHeight, lf.lfWeight, lf.lfItalic != 0}
	cache := s.font != nil ? (^map[Font_Key]win.HFONT)(s.font.extra) : &g_theme_windows.fonts
	if f, ok := cache[key]; ok do return f
	f := win.CreateFontIndirectW(&lf)
	cache[key] = f
	font_remember_height(f)
	return f
}

@(private)
font_remember_height :: proc(f: win.HFONT) {
	dc := win.GetDC(nil)
	defer win.ReleaseDC(nil, dc)
	g_theme_windows.heights[f] = text_size(dc, f, "Ag").cy
}

// Line height in px of a font: remembered for the ones from create_fonts and style_font, else
// measured.
@(private)
font_height :: proc "contextless" (f: win.HFONT) -> i32 {
	if h, ok := g_theme_windows.heights[f]; ok do return h
	dc := win.GetDC(nil)
	defer win.ReleaseDC(nil, dc)
	old := win.SelectObject(dc, win.HGDIOBJ(f))
	defer win.SelectObject(dc, old)
	tm: win.TEXTMETRICW
	win.GetTextMetricsW(dc, &tm)
	return tm.tmHeight
}

// The font a control was given with WM_SETFONT.
@(private)
control_font :: proc "contextless" (hwnd: win.HWND) -> win.HFONT {
	return win.HFONT(uintptr(win.SendMessageW(hwnd, win.WM_GETFONT, 0, 0)))
}
