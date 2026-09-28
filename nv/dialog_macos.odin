#+build darwin
package nv

// macOS dialog backend: the card is a custom NSBox (window background fill, rounded corners)
// added to the window's content view over the pages and placed by Auto Layout
// (layout_dialog_card in appkit.odin); a modal dialog first adds a translucent black NSBox the
// size of the content view. AppKit hit-tests the topmost subview and sends an unhandled mouse
// event up the responder chain, never to a sibling, so the scrim blocks the page by existing.
// The title bar is outside the content view: its buttons check dialog_top_modal themselves.
// The card and the scrim are retained and autoreleased before removal, since the close often
// runs from one of the card's own buttons' actions.

import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private)
_dialog_show :: proc(h: ^Dialog_Handle) {
	host := g_macos.content
	if h.dialog.modal {
		scrim := box_new(host->bounds())
		box_set_fill_color(scrim, (^NS.Color)(canvas_color({0, 0, 0, 0.4})))
		view_set_autoresizing(scrim, RESIZE_WIDTH | RESIZE_HEIGHT)
		host->addSubview(scrim)
		scrim->release() // the container owns it
		h.scrim = scrim
	}

	card := box_new({})
	box_set_fill_color(card, color_window_background())
	box_set_corner_radius(card, 12)
	view_set_translates_autoresizing_mask(card, false)
	host->addSubview(card) // after the scrim: above it
	card->release()
	h.card = card

	body := (^NS.View)(h.body)
	view_set_translates_autoresizing_mask(body, false)
	box_content_view(card)->addSubview(body) // the body keeps its own +1 until _dialog_close
	layout_dialog_card(card, body, host, 320, 16)

	// The scrim takes the mouse, not the keyboard: the focus moves off the page's field.
	if h.dialog.modal {
		first := len(h.buttons) > 0 ? (^NS.Responder)(h.buttons[0].handle.control) : nil
		g_macos.window->makeFirstResponder(first)
	}
}

// The card and the scrim are autoreleased, since the close often runs from one of the body's
// buttons; the body's views go with the dialog's scope (autoreleased as well).
@(private)
_dialog_close :: proc(h: ^Dialog_Handle) {
	for v in ([]rawptr{h.card, h.scrim}) {
		if v == nil do continue
		send(nil, (^NS.Object)(v), "retain")
		send(nil, (^NS.Object)(v), "autorelease")
		view_remove_from_superview((^NS.View)(v)) // also drops the constraints that mention it
	}
	scope_retire(h.scope) // the body's views, autoreleased
}

@(private)
_dialog_set_hidden :: proc(h: ^Dialog_Handle, hidden: bool) {
	view_set_hidden((^NS.View)(h.card), NS.BOOL(hidden))
	if h.scrim != nil do view_set_hidden((^NS.View)(h.scrim), NS.BOOL(hidden))
}

}
