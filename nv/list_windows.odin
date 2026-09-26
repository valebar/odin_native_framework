#+build windows
package nv

// Windows list backend: a SysListView32 in virtual mode (LVS_OWNERDATA). It only knows the row
// count and asks for nothing else; there are no per-row objects, so `cells_created` stays 0.
//
// The ListView sits inside an "NVList" container window that receives its WM_NOTIFY. ListView
// caches its parent for notifications at creation, so it needs a parent that never changes even
// when Row / Column re-parents the container (like the GtkScrolledWindow on Linux).
//
// Rows are two lines, which report view can't show, so the ListView paints each row with empty
// text (theme hover / selection included) and custom draw adds title and subtitle in post-paint.
// The row height comes from a 1×h image list, the usual trick for report view.

import win "core:sys/windows"

@(private)
_list_init :: proc(h: ^List_Handle) {
	container := win.CreateWindowExW(0, wstr(CLASS_LIST), nil, win.WS_CHILD | win.WS_VISIBLE | win.WS_CLIPCHILDREN,
		0, 0, 0, 0, g_windows.parking, nil, g_windows.hinstance, h)

	style := win.WS_CHILD | win.WS_VISIBLE | win.WS_TABSTOP | win.LVS_REPORT | win.LVS_OWNERDATA |
		win.LVS_SINGLESEL | win.LVS_NOCOLUMNHEADER | win.LVS_SHOWSELALWAYS
	lv := win.CreateWindowExW(0, wstr(win.WC_LISTVIEW), nil, style,
		0, 0, 0, 0, container, nil, g_windows.hinstance, nil)
	win.SetWindowTheme(lv, wstr("Explorer"), nil)
	win.ListView_SetExtendedListViewStyle(lv, win.LVS_EX_FULLROWSELECT | win.LVS_EX_DOUBLEBUFFER)
	win.SendMessageW(lv, win.WM_SETFONT, win.WPARAM(uintptr(g_windows.font)), 0)

	col := win.LVCOLUMNW{mask = win.LVCF_WIDTH}
	win.ListView_InsertColumn(lv, 0, &col)

	rows := win.ImageList_Create(1, px(h.list.row_height), win.ILC_COLOR32, 0, 0)
	win.SendMessageW(lv, win.LVM_SETIMAGELIST, win.LVSIL_SMALL, win.LPARAM(uintptr(rawptr(rows))))

	win.ListView_SetItemCountEx(lv, i32(h.list.count(h.list.user)), 0)

	h.root = View(container)
	h.table = rawptr(lv)
	free_all(context.temp_allocator)
}

@(private)
_list_reload :: proc(h: ^List_Handle) {
	win.ListView_SetItemCountEx(win.HWND(h.table), i32(h.list.count(h.list.user)), win.LVSICF_NOSCROLL)
}

@(private)
list_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if msg == win.WM_NCCREATE {
		cs := (^win.CREATESTRUCTW)(uintptr(lparam))
		win.SetWindowLongPtrW(hwnd, win.GWLP_USERDATA, win.LONG_PTR(uintptr(cs.lpCreateParams)))
	}
	h := (^List_Handle)(uintptr(win.GetWindowLongPtrW(hwnd, win.GWLP_USERDATA)))
	if h == nil || h.table == nil do return win.DefWindowProcW(hwnd, msg, wparam, lparam)
	context = h.ctx
	lv := win.HWND(h.table)

	switch msg {
	case win.WM_SIZE:
		rc: win.RECT
		win.GetClientRect(hwnd, &rc)
		win.MoveWindow(lv, 0, 0, rc.right, rc.bottom, true)
		win.ListView_SetColumnWidth(lv, 0, win.LVSCW_AUTOSIZE_USEHEADER) // last column fills the width
		return 0

	case win.WM_NOTIFY:
		hdr := (^win.NMHDR)(uintptr(lparam))
		if hdr.hwndFrom != lv do break
		switch hdr.code {
		case win.LVN_GETDISPINFOW:
			di := (^win.LVDISPINFOW)(uintptr(lparam))
			if di.item.mask & win.LVIF_TEXT != 0 && di.item.cchTextMax > 0 do di.item.pszText^ = 0
			return 0
		case win.LVN_ITEMCHANGED:
			nm := (^win.NMLISTVIEW)(uintptr(lparam))
			selected := nm.uNewState & win.LVIS_SELECTED != 0 && nm.uOldState & win.LVIS_SELECTED == 0
			if selected && nm.iItem >= 0 && h.list.on_select != nil do h.list.on_select(h.list.user, int(nm.iItem))
			return 0
		case NM_CUSTOMDRAW:
			return list_custom_draw(h, (^win.NMLVCUSTOMDRAW)(uintptr(lparam)))
		}
	}
	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@(private)
list_custom_draw :: proc(h: ^List_Handle, cd: ^win.NMLVCUSTOMDRAW) -> win.LRESULT {
	switch cd.nmcd.dwDrawStage {
	case win.CDDS_PREPAINT:
		return win.CDRF_NOTIFYITEMDRAW
	case win.CDDS_ITEMPREPAINT:
		return win.CDRF_NOTIFYPOSTPAINT
	case win.CDDS_ITEMPOSTPAINT:
		row := i32(cd.nmcd.dwItemSpec)
		rc: win.RECT
		win.ListView_GetItemRect(win.HWND(h.table), row, &rc, win.LVIR_BOUNDS)
		r := h.list.item(h.list.user, int(row))

		// Title above subtitle, the pair vertically centred, like the Linux cell.
		dc := cd.nmcd.hdc
		gap := px(2)
		top := rc.top + (rc.bottom - rc.top - g_windows.bold_h - gap - g_windows.font_h) / 2
		line := win.RECT{rc.left + px(12), top, rc.right - px(12), top + g_windows.bold_h}
		win.SetBkMode(dc, .TRANSPARENT)
		old := win.SelectObject(dc, win.HGDIOBJ(g_windows.bold))
		win.SetTextColor(dc, win.COLORREF(win.GetSysColor(win.COLOR_WINDOWTEXT)))
		win.DrawTextW(dc, wstr(r.title), -1, &line, DT_ROW)

		line.top = line.bottom + gap
		line.bottom = line.top + g_windows.font_h
		win.SelectObject(dc, win.HGDIOBJ(g_windows.font))
		win.SetTextColor(dc, win.COLORREF(win.GetSysColor(win.COLOR_GRAYTEXT)))
		win.DrawTextW(dc, wstr(r.subtitle), -1, &line, DT_ROW)
		win.SelectObject(dc, old)
		free_all(context.temp_allocator)
	}
	return win.CDRF_DODEFAULT
}

@(private)
DT_ROW :: win.DrawTextFormat(u32(win.DrawTextFormat.DT_SINGLELINE) | u32(win.DrawTextFormat.DT_NOPREFIX) | u32(win.DrawTextFormat.DT_END_ELLIPSIS))

// NM_CUSTOMDRAW is (0 - 12) as a UINT; core:sys/windows declares it as a uintptr.
@(private)
NM_CUSTOMDRAW :: win.UINT(0xFFFF_FFF4)
