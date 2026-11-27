#+build darwin:default
#+private
package nv

// macOS dialog backend: the card is a custom NSBox (window background fill, or white in the Aqua
// appearance for a light dialog, which its subviews inherit; rounded corners)
// added to the window's content view over the pages and placed by Auto Layout
// (layout_dialog_card in appkit.odin); a modal dialog first adds a translucent black NSBox the
// size of the content view (NVDialogScrim, whose mouseDown: reports the click for a dismissible
// dialog). AppKit hands a mouseDown: that a view leaves unhandled on to the views under it, so the
// scrim and the card (NVDialogCard) end it: the page under the scrim gets nothing, nor does the
// scrim or the page under a card.
// The title bar is outside the content view: its buttons check dialog_top_modal themselves.
// The card and the scrim are retained and autoreleased before removal, since the close often
// runs from one of the card's own buttons' actions.

import NS "core:sys/darwin/Foundation"
import AK "vendor:darwin/AppKit"

@(private) dialog_scrim_class, dialog_card_class: NS.Class

@(private)
_dialog_show :: proc(h: ^Dialog_Handle) {
	host := g_macos.content
	if h.dialog.modal {
		cls := objc_class(&dialog_scrim_class, "NVDialogScrim", "NSBox", {
			{"mouseDown:", auto_cast dialog_scrim_mouse_down, "v@:@"},
		})
		scrim := box_new(host->bounds(), cls)
		box_set_fill_color(scrim, (^AK.Color)(canvas_color(dialog_scrim(h))))
		view_set_autoresizing(scrim, RESIZE_WIDTH | RESIZE_HEIGHT)
		host->addSubview(scrim)
		scrim->release() // the container owns it
		h.scrim = scrim
	}

	card_cls := objc_class(&dialog_card_class, "NVDialogCard", "NSBox", {
		{"mouseDown:", auto_cast dialog_card_mouse_down, "v@:@"},
	})
	card := box_new({}, card_cls)
	if h.dialog.light {
		box_set_fill_color(card, (^AK.Color)(canvas_color(DIALOG_LIGHT)))
		aqua := send(^NS.Object, objc_class_object("NSAppearance"), "appearanceNamed:", ns_string("NSAppearanceNameAqua"))
		send(nil, card, "setAppearance:", aqua)
	} else {
		box_set_fill_color(card, color_window_background())
	}
	box_set_corner_radius(card, NS.Float(dialog_radius(h, 12)))
	view_set_translates_autoresizing_mask(card, false)
	host->addSubview(card) // after the scrim: above it
	card->release()
	h.card = card

	body := (^AK.View)(h.body)
	view_set_translates_autoresizing_mask(body, false)
	box_content_view(card)->addSubview(body) // the body keeps its own +1 until _dialog_close
	layout_dialog_card(card, body, host, NS.Float(dialog_width(h)), 16)

	// The scrim takes the mouse, not the keyboard: the focus moves off the page's field.
	if h.dialog.modal {
		first := len(h.buttons) > 0 ? (^AK.Responder)(h.buttons[0].handle.control) : nil
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
		view_remove_from_superview((^AK.View)(v)) // also drops the constraints that mention it
	}
	scope_retire(h.scope) // the body's views, autoreleased
}

@(private)
dialog_scrim_mouse_down :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	dialog_scrim_notify(rawptr(self))
}

@(private)
dialog_card_mouse_down :: proc "c" (_: NS.id, _: NS.SEL, _: NS.id) {}

@(private)
_dialog_set_hidden :: proc(h: ^Dialog_Handle, hidden: bool) {
	ak_view_set_hidden((^AK.View)(h.card), NS.BOOL(hidden))
	if h.scrim != nil do ak_view_set_hidden((^AK.View)(h.scrim), NS.BOOL(hidden))
}
