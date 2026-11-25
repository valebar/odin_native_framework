#+build js
package nv

// Web navigation backend: each page is an .nv-page in the page host holding the page's root; the
// pages below the top stay in the document with `content-visibility: hidden` (nv.css), which keeps
// their scroll positions. The bar shows the top page's title (also the document title), a back
// button on pushed pages and the page's actions. nv.js keeps the browser history one entry per
// depth (js_history), so the browser's Back button pops a page (nv_web_event .Back).

// The page's .nv-page element (Page_Handle.native).
@(private)
web_page :: #force_inline proc "contextless" (e: ^Page_Handle) -> Web_Id {
	return Web_Id(uintptr(e.native))
}

@(private)
_nav_push :: proc(e: ^Page_Handle) {
	page := js_create("div", "nv-page")
	js_append(page, web_id(e.root))
	js_append(g_web.pages, page)
	e.native = rawptr(uintptr(page))
	if len(g_nav) > 1 do js_class(web_page(g_nav[len(g_nav) - 2]), "nv-below", true)
	nav_update_chrome(e)
}

@(private)
_nav_pop :: proc(top, below: ^Page_Handle) -> bool {
	js_class(web_page(below), "nv-below", false)
	js_show_page()
	nav_update_chrome(below)
	return true
}

// Takes the page's tree out of the document; its elements are released by its scope.
@(private)
_nav_release :: proc(e: ^Page_Handle) {
	js_release(web_page(e))
	scope_retire(e.scope)
}

@(private)
_nav_title_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do nav_set_title(e)
}

@(private)
_nav_actions_changed :: proc(e: ^Page_Handle) {
	if e == g_nav[len(g_nav) - 1] do nav_rebuild_actions(e)
}

@(private)
nav_update_chrome :: proc(e: ^Page_Handle) {
	nav_set_title(e)
	js_hidden(g_web.back, len(g_nav) <= 1)
	js_hidden(g_web.menu, !nav_shows_menu(e))
	nav_rebuild_actions(e)
	js_history(i32(len(g_nav) - 1))
}

@(private)
nav_set_title :: proc(e: ^Page_Handle) {
	js_text(g_web.title, e.page.title)
	js_title(e.page.title)
}

// Removing a button from inside its own click is fine in the DOM.
@(private)
nav_rebuild_actions :: proc(e: ^Page_Handle) {
	for b in g_web.buttons do js_release(b)
	clear(&g_web.buttons)
	for h in e.actions {
		b: Web_Id
		if h.action.icon != .None {
			b = web_icon_button(i32(h.action.icon), h.action.title)
		} else {
			b = js_create("button", "nv-icon-btn")
			js_attr(b, "type", "button")
			js_text(b, h.action.title)
		}
		js_listen(b, .Action, h, 0)
		js_append(g_web.actions, b)
		append(&g_web.buttons, b)
	}
}
