#+build js
package nv

// Web app backend. The page (index.html) has #nv-app; _run fills it with the bar (back button,
// menu button, title, the top page's actions) over the page host, then builds the root page at
// once, since the DOM exists before the wasm starts. `run` returns, and so does main: the app lives
// on events, like Android's (nv.js never calls the runtime's _end). Assets were all fetched by
// nv.js before the wasm started, so _asset_read is synchronous like everywhere else.

@(private)
_run :: proc() {
	g_web.ctx = context
	g_web.app = js_app()

	bar := js_create("header", "nv-bar")
	back := web_icon_button(WEB_ICON_BACK, "Back")
	js_listen(back, .Back, nil, 0)
	js_hidden(back, true)
	menu := web_icon_button(i32(Icon.Menu), "Menu")
	js_listen(menu, .Menu, nil, 0)
	js_hidden(menu, true)
	title := js_create("div", "nv-bar-title")
	actions := js_create("div", "nv-bar-actions")
	js_append(bar, back)
	js_append(bar, menu)
	js_append(bar, title)
	js_append(bar, actions)
	pages := js_create("main", "nv-pages")
	js_append(g_web.app, bar)
	js_append(g_web.app, pages)
	g_web.bar, g_web.back, g_web.menu, g_web.title, g_web.actions, g_web.pages = bar, back, menu, title, actions, pages

	callback_enter()
	defer callback_exit()
	theme_start()
	nav_show_root()
}

// A bar button with an icon and a tooltip; not scoped (the caller releases it).
@(private)
web_icon_button :: proc(icon: i32, label: string) -> Web_Id {
	b := js_create("button", "nv-icon-btn")
	js_attr(b, "type", "button")
	js_attr(b, "title", label)
	js_attr(b, "aria-label", label)
	js_icon(b, icon)
	return b
}

// A relative path names a file under app/assets; there is no file system to read anything else.
@(private)
_asset_read :: proc(path: string, allocator := context.allocator) -> []u8 {
	n := js_asset_size(path)
	if n < 0 do return nil
	buf := make([]u8, n, allocator)
	js_asset_copy(path, buf)
	return buf
}

// fetch() in nv.js; the bytes come back through nv_web_fetched. A cross-origin URL needs CORS
// headers (Access-Control-Allow-Origin) to be readable, as for any fetch.
@(private)
_fetch_start :: proc(f: ^Fetch) {
	js_fetch(f.url, f)
}
