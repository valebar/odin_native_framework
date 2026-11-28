#+build windows
#+private
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
	GetGestureInfo :: proc(hGestureInfo: win.HANDLE, pGestureInfo: ^GESTUREINFO) -> win.BOOL ---
	CloseGestureInfoHandle :: proc(hGestureInfo: win.HANDLE) -> win.BOOL ---
}

// winuser.h's GESTUREINFO (WM_GESTURE).
@(private) GESTUREINFO :: struct {
	cbSize:       win.UINT,
	dwFlags:      win.DWORD,
	dwID:         win.DWORD,
	hwndTarget:   win.HWND,
	ptsLocation:  [2]i16, // POINTS, screen pixels
	dwInstanceID: win.DWORD,
	dwSequenceID: win.DWORD,
	ullArguments: u64,    // GID_ZOOM: the fingers' distance
	cbExtraArgs:  win.UINT,
}
#assert(size_of(GESTUREINFO) == 56 || size_of(uintptr) == 4)
@(private) WM_GESTURE :: 0x0119
@(private) GID_ZOOM   :: 3
@(private) GF_BEGIN   :: 1
@(private) GF_END     :: 4

@(default_calling_convention="system")
foreign comctl32 {
	RemoveWindowSubclass :: proc(hWnd: win.HWND, pfnSubclass: win.SUBCLASSPROC, uIdSubclass: win.UINT_PTR) -> win.BOOL ---
}

@(default_calling_convention="system")
foreign gdi32 {
	GetTextFaceW :: proc(hdc: win.HDC, c: i32, lpName: win.LPWSTR) -> i32 ---
	RemoveFontMemResourceEx :: proc(h: win.HANDLE) -> win.BOOL ---
	CreateRoundRectRgn :: proc(x1, y1, x2, y2, w, h: i32) -> win.HRGN ---
	IntersectClipRect :: proc(hdc: win.HDC, left, top, right, bottom: i32) -> i32 ---
}

@(private) g_windows: struct {
	ctx:        runtime.Context,
	hinstance:  win.HINSTANCE,
	parking:    win.HWND, // main window; parent of every control until it is re-parented
	root:       win.HWND, // the NVNav host (nav_windows.odin), which holds the pages
	nav_back:   win.HWND, // the host's bar: a back button (pushed pages) and the page title
	nav_menu:   win.HWND, // the bar's menu button, on a root page with a drawer (nav_shows_menu)
	nav_title:  win.HWND,
	nav_actions: [dynamic]win.HWND, // the bar's action buttons for the top page
	nav_leading: win.HWND, // the top page's bar_leading, moved into the bar; nil for none
	nav_leading_home: win.HWND, // the root of the page it belongs to, where it is parked when not shown
	dpi:        u32,
	font:       win.HFONT, // message font (Segoe UI 9pt): list subtitles, inputs, buttons, plain labels
	bold:       win.HFONT, // bold message font: list titles
	title:      win.HFONT, // larger bold font: bold labels, the bar title
	icon_font:  win.HFONT, // Segoe MDL2 Assets at the message font size: action icons; nil if unavailable
	font_h:     i32,       // line heights of the fonts above, in px
	bold_h:     i32,
	title_h:    i32,
}

// Owner-drawn controls (WM_DRAWITEM): the bar's buttons (nav_windows.odin).
@(private) ODT_BUTTON      :: 4
@(private) ODS_SELECTED    :: 0x0001
@(private) ODS_DISABLED    :: 0x0004
@(private) ODS_FOCUS       :: 0x0010
@(private) ODS_NOFOCUSRECT :: 0x0200

@(private) DRAWITEMSTRUCT :: struct {
	CtlType:    win.UINT,
	CtlID:      win.UINT,
	itemID:     win.UINT,
	itemAction: win.UINT,
	itemState:  win.UINT,
	hwndItem:   win.HWND,
	hDC:        win.HDC,
	rcItem:     win.RECT,
	itemData:   win.ULONG_PTR,
}

@(private) CLASS_WINDOW :: "NVWindow"
@(private) CLASS_FLEX   :: "NVFlex"
@(private) CLASS_LIST   :: "NVList"
@(private) CLASS_INPUT  :: "NVInput"
@(private) CLASS_BUTTON :: "NVButton"
@(private) CLASS_CANVAS :: "NVCanvas"
@(private) CLASS_IMAGE  :: "NVImage"
@(private) CLASS_NAV    :: "NVNav"
@(private) CLASS_SCRIM  :: "NVScrim"
@(private) CLASS_DIALOG :: "NVDialog"
@(private) CLASS_CONTAINER :: "NVContainer"
@(private) CLASS_LAYOUT :: "NVLayout"

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
	// No class brush: a container erases with the palette (erase_background, theme_windows.odin).
	register :: proc(name: string, wndproc: win.WNDPROC, background: win.HBRUSH = nil) {
		wc := win.WNDCLASSEXW{
			cbSize        = size_of(win.WNDCLASSEXW),
			lpfnWndProc   = wndproc,
			hInstance     = g_windows.hinstance,
			hCursor       = win.LoadCursorW(nil, win.LPCWSTR(win._IDC_ARROW)),
			hbrBackground = background,
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
	register(CLASS_IMAGE, image_proc)
	register(CLASS_NAV, nav_proc)
	register(CLASS_SCRIM, scrim_proc, win.HBRUSH(win.GetStockObject(win.BLACK_BRUSH)))
	register(CLASS_DIALOG, dialog_proc)
	register(CLASS_CONTAINER, container_proc, nil) // paints every pixel itself
	register(CLASS_OVERLAY, overlay_proc)
	register(CLASS_FAB, fab_proc)
	register(CLASS_TABBAR, tabbar_proc)
	register(CLASS_LAYOUT, layout_proc)
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
	g_theme_windows.heights[g_windows.font] = g_windows.font_h
	g_theme_windows.heights[g_windows.bold] = g_windows.bold_h
	g_theme_windows.heights[g_windows.title] = g_windows.title_h

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

// Whether `hwnd` is of the window class `name` (ASCII), without allocating.
@(private)
class_is :: proc "contextless" (hwnd: win.HWND, name: string) -> bool {
	buf: [64]u16
	n := int(win.GetClassNameW(hwnd, &buf[0], len(buf)))
	if n != len(name) do return false
	for i in 0..<n do if buf[i] != u16(name[i]) do return false
	return true
}

// The brush a window's background is painted with: the fill of the nearest NVContainer around (or
// at) `hwnd` that has a color, else a light dialog's white, else the palette's page background
// (theme_windows.odin). Labels, Row / Column, buttons, images and the canvas all erase with it, so
// they don't punch holes into a colored container.
@(private)
background_brush_of :: proc "contextless" (hwnd: win.HWND) -> win.HBRUSH {
	for p := hwnd; p != nil; p = win.GetParent(p) {
		if class_is(p, CLASS_DIALOG) {
			d := (^Dialog_Handle)(uintptr(win.GetWindowLongPtrW(p, win.GWLP_USERDATA)))
			if d != nil && d.dialog.light do return g_theme_windows.light
			break
		}
		if !class_is(p, CLASS_CONTAINER) do continue
		h := (^Container_Handle)(uintptr(win.GetWindowLongPtrW(p, win.GWLP_USERDATA)))
		if h != nil && h.box != nil && h.container.color.a > 0 do return win.HBRUSH(h.box)
	}
	return g_theme_windows.bg
}

// Whether `hwnd` is inside a light dialog's card (Dialog.light), whose content stays light.
@(private)
in_light_dialog :: proc "contextless" (hwnd: win.HWND) -> bool {
	for p := hwnd; p != nil; p = win.GetParent(p) {
		if !class_is(p, CLASS_DIALOG) do continue
		d := (^Dialog_Handle)(uintptr(win.GetWindowLongPtrW(p, win.GWLP_USERDATA)))
		return d != nil && d.dialog.light
	}
	return false
}
