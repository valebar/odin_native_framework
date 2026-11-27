#+build js
#+private
package nv

// Web list backend: a scrolling div whose rows are absolutely placed over a spacer as tall as all
// of them (nv.js renders only the rows in view and recycles the others, so `cells_created` stops
// growing once the view is full). Each row comes into view through nv_web_list_bind (web.odin),
// which asks the app for the item; a click selects the row and reports on_select.

@(private)
_list_init :: proc(h: ^List_Handle) {
	list := js_list_create(h, h.list.item_height)
	scope_on_dispose(web_release, rawptr(uintptr(list)))
	h.root = web_view(list)
	h.table = rawptr(uintptr(list))
	_list_reload(h)
}

@(private)
_list_reload :: proc(h: ^List_Handle) {
	js_list_count(Web_Id(uintptr(h.table)), i32(list_count(h)))
}
