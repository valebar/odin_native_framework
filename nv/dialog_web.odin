#+build js
package nv

// Web dialog backend: the card (.nv-dialog) and, for a modal dialog, a scrim under it are children
// of #nv-app, over the bar and the pages. The scrim takes the pointer; the keyboard is kept off the
// bar, the pages and the other dialogs by `inert` while the top page has a visible modal dialog.
// The card and the scrim are released at the close, which takes them out of the document; the
// body's elements go with the dialog's scope.

@(private)
_dialog_show :: proc(h: ^Dialog_Handle) {
	if h.dialog.modal {
		scrim := js_create("div", "nv-dscrim")
		js_append(g_web.app, scrim)
		h.scrim = rawptr(uintptr(scrim))
	}
	card := js_create("div", "nv-dialog")
	js_attr(card, "role", "dialog")
	if h.dialog.modal do js_attr(card, "aria-modal", "true")
	js_append(card, web_id(h.body))
	js_append(g_web.app, card)
	h.card = rawptr(uintptr(card))
	web_apply_modal()
	// A non-modal dialog leaves the focus where it is: the page stays in use.
	if h.dialog.modal && len(h.buttons) > 0 do js_focus(web_id(h.buttons[0].handle.root))
}

@(private)
_dialog_close :: proc(h: ^Dialog_Handle) {
	js_release(Web_Id(uintptr(h.card)))
	if h.scrim != nil do js_release(Web_Id(uintptr(h.scrim)))
	scope_retire(h.scope)
	web_apply_modal()
}

@(private)
_dialog_set_hidden :: proc(h: ^Dialog_Handle, hidden: bool) {
	js_hidden(Web_Id(uintptr(h.card)), b32(hidden))
	if h.scrim != nil do js_hidden(Web_Id(uintptr(h.scrim)), b32(hidden))
	web_apply_modal()
}

// Everything but the top modal dialog follows the top page's modal state.
@(private)
web_apply_modal :: proc() {
	top := dialog_top_modal()
	js_inert(g_web.bar, top != nil)
	js_inert(g_web.pages, top != nil)
	for d in g_dialogs do if d.card != nil {
		js_inert(Web_Id(uintptr(d.card)), top != nil && d != top)
	}
}
