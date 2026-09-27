#+build windows
package nv

// Shared Win32 state and helpers for the Windows backend. The bindings themselves come from
// core:sys/windows; the few it lacks are declared here with the C names.
//
// Every control is created as a child of `parking`, the main window, which exists before `build`
// runs. Row / Column then re-parents its children with SetParent, since Win32 has no way to
// create a WS_CHILD window without a parent.

import "base:runtime"
import win "core:sys/windows"

foreign import user32 "system:User32.lib"
foreign import comctl32 "system:Comctl32.lib"
foreign import gdi32 "system:Gdi32.lib"

@(default_calling_convention="system")
foreign user32 {
	SystemParametersInfoForDpi :: proc(uiAction, uiParam: win.UINT, pvParam: win.PVOID, fWinIni, dpi: win.UINT) -> win.BOOL ---
}

@(default_calling_convention="system")
foreign comctl32 {
	RemoveWindowSubclass :: proc(hWnd: win.HWND, pfnSubclass: win.SUBCLASSPROC, uIdSubclass: win.UINT_PTR) -> win.BOOL ---
}

@(default_calling_convention="system")
foreign gdi32 {
	GetTextFaceW :: proc(hdc: win.HDC, c: i32, lpName: win.LPWSTR) -> i32 ---
}

@(private) g_windows: struct {
	ctx:        runtime.Context,
	hinstance:  win.HINSTANCE,
	parking:    win.HWND, // main window; parent of every control until it is re-parented
	root:       win.HWND, // the NVNav host (nav_windows.odin), which holds the pages
	nav_back:   win.HWND, // the host's bar: a back button (pushed pages) and the page title
	nav_title:  win.HWND,
	nav_actions: [dynamic]win.HWND, // the bar's action buttons for the top page
	dpi:        u32,
	font:       win.HFONT, // message font (Segoe UI 9pt): list subtitles, inputs, buttons
	bold:       win.HFONT, // bold message font: list titles
	title:      win.HFONT, // larger bold font: labels, the bar title
	icon_font:  win.HFONT, // Segoe MDL2 Assets at the message font size: action icons; nil if unavailable
	font_h:     i32,       // line heights of the fonts above, in px
	bold_h:     i32,
	title_h:    i32,
}

@(private) CLASS_WINDOW :: "NVWindow"
@(private) CLASS_FLEX   :: "NVFlex"
@(private) CLASS_LIST   :: "NVList"
@(private) CLASS_INPUT  :: "NVInput"
@(private) CLASS_BUTTON :: "NVButton"
@(private) CLASS_CANVAS :: "NVCanvas"
@(private) CLASS_NAV    :: "NVNav"

@(private)
wstr :: proc(s: string) -> win.wstring {
	return win.utf8_to_wstring(s, context.temp_allocator)
}

// dp → px for the current DPI (the Android backend's android_dp).
@(private)
px :: proc "contextless" (dp: f64) -> i32 {
	return i32(dp * f64(g_windows.dpi) / 96 + 0.5)
}

@(private)
register_classes :: proc() {
	register :: proc(name: string, wndproc: win.WNDPROC) {
		wc := win.WNDCLASSEXW{
			cbSize        = size_of(win.WNDCLASSEXW),
			lpfnWndProc   = wndproc,
			hInstance     = g_windows.hinstance,
			hCursor       = win.LoadCursorW(nil, win.LPCWSTR(win._IDC_ARROW)),
			hbrBackground = win.HBRUSH(uintptr(win.COLOR_WINDOW + 1)),
			lpszClassName = wstr(name),
		}
		win.RegisterClassExW(&wc)
	}
	register(CLASS_WINDOW, window_proc)
	register(CLASS_FLEX, flex_proc)
	register(CLASS_LIST, list_proc)
	register(CLASS_INPUT, input_proc)
	register(CLASS_BUTTON, button_proc)
	register(CLASS_CANVAS, canvas_proc)
	register(CLASS_NAV, nav_proc)
}

// Fonts follow the user's message font (Settings > Accessibility > Text size included) at `dpi`.
@(private)
create_fonts :: proc() {
	ncm := win.NONCLIENTMETRICSW{cbSize = size_of(win.NONCLIENTMETRICSW)}
	SystemParametersInfoForDpi(win.SPI_GETNONCLIENTMETRICS, size_of(ncm), &ncm, 0, g_windows.dpi)
	lf := ncm.lfMessageFont
	g_windows.font = win.CreateFontIndirectW(&lf)
	lf.lfWeight = win.FW_BOLD
	g_windows.bold = win.CreateFontIndirectW(&lf)
	lf.lfHeight = lf.lfHeight * 5 / 4
	g_windows.title = win.CreateFontIndirectW(&lf)

	dc := win.GetDC(nil)
	defer win.ReleaseDC(nil, dc)
	g_windows.font_h = text_size(dc, g_windows.font, "Ag").cy
	g_windows.bold_h = text_size(dc, g_windows.bold, "Ag").cy
	g_windows.title_h = text_size(dc, g_windows.title, "Ag").cy

	// The icon font, if it is really installed: GDI silently substitutes a missing face, which
	// would show the glyphs as boxes, so the face that came out is checked.
	ICON_FACE :: "Segoe MDL2 Assets"
	lf = ncm.lfMessageFont
	lf.lfHeight = lf.lfHeight * 4 / 3
	lf.lfFaceName = {}
	copy(lf.lfFaceName[:len(lf.lfFaceName) - 1], win.utf8_to_utf16(ICON_FACE, context.temp_allocator))
	icon := win.CreateFontIndirectW(&lf)
	old := win.SelectObject(dc, win.HGDIOBJ(icon))
	got: [win.LF_FACESIZE]u16
	n := GetTextFaceW(dc, len(got), &got[0])
	win.SelectObject(dc, old)
	name, _ := win.utf16_to_utf8(got[:max(n - 1, 0)], context.temp_allocator)
	if name == ICON_FACE {
		g_windows.icon_font = icon
	} else {
		win.DeleteObject(win.HGDIOBJ(icon))
	}
}

@(private)
text_size :: proc(dc: win.HDC, font: win.HFONT, text: string) -> win.SIZE {
	w := wstr(text)
	old := win.SelectObject(dc, win.HGDIOBJ(font))
	defer win.SelectObject(dc, old)
	sz: win.SIZE
	win.GetTextExtentPoint32W(dc, w, i32(len(string16_of(w))), &sz)
	return sz
}

@(private)
string16_of :: proc(w: win.wstring) -> []u16 {
	p := ([^]u16)(w)
	n := 0
	for p[n] != 0 do n += 1
	return p[:n]
}

@(private)
class_name :: proc(hwnd: win.HWND) -> string {
	buf: [64]u16
	n := win.GetClassNameW(hwnd, &buf[0], len(buf))
	s, _ := win.utf16_to_utf8(buf[:n], context.temp_allocator)
	return s
}

// WM_CTLCOLORSTATIC for every container: labels are painted on the window background.
@(private)
ctlcolor_static :: proc "contextless" (wparam: win.WPARAM) -> win.LRESULT {
	win.SetBkMode(win.HDC(wparam), .TRANSPARENT)
	return win.LRESULT(uintptr(win.GetSysColorBrush(win.COLOR_WINDOW)))
}
