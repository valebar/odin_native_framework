#+build darwin
package nv

// iOS dialog backend: the card is a UIView (system background, rounded layer) added to the
// navigation controller's view, which puts it over the navigation bar too, and placed by Auto
// Layout (layout_dialog_card in appkit.odin); a modal dialog first adds a translucent black view
// pinned to the host's edges. A UIView takes the touches that land on it, so the scrim blocks
// the page and the bar by existing; the swipe-back gesture is turned off while a modal dialog is
// visible. The card and the scrim are retained and autoreleased before removal, since the close
// often runs from one of the card's own buttons' actions.

import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private)
_dialog_show :: proc(h: ^Dialog_Handle) {
	host := ui_view_controller_view(g_app.nav)
	if h.dialog.modal {
		scrim := ui_view_new()
		ui_view_set_background_color(scrim, ui_color_with_white_alpha(0, 0.4))
		ui_view_set_translates_autoresizing_mask(scrim, false)
		ui_view_add_subview(host, scrim)
		scrim->release() // the host owns it
		layout_pin_edges(scrim, host)
		h.scrim = scrim
	}

	card := ui_view_new()
	ui_view_set_background_color(card, ui_color_system_background())
	ui_view_set_corner_radius(card, 14)
	ui_view_set_translates_autoresizing_mask(card, false)
	ui_view_add_subview(host, card) // after the scrim: above it
	card->release()
	h.card = card

	body := (^UI_View)(h.body)
	ui_view_set_translates_autoresizing_mask(body, false)
	ui_view_add_subview(card, body) // the body keeps its own +1 until _dialog_close
	layout_dialog_card(card, body, host, 320, 16)
	if h.dialog.modal do ui_view_end_editing(host) // the page's field gives up the keyboard
	ios_dialog_apply_modal()
}

// The body's own reference goes with the card's: autoreleased, since the close often runs from
// one of the body's buttons.
@(private)
_dialog_close :: proc(h: ^Dialog_Handle) {
	for v in ([]rawptr{h.card, h.scrim}) {
		if v == nil do continue
		send(nil, (^NS.Object)(v), "retain")
		send(nil, (^NS.Object)(v), "autorelease")
		ui_view_remove_from_superview((^UI_View)(v)) // also drops the constraints that mention it
	}
	send(nil, (^NS.Object)(h.body), "autorelease")
	ios_dialog_apply_modal()
}

// The navigation controller may raise its bar above later subviews during a transition, so a
// dialog coming back is brought to the front again.
@(private)
_dialog_set_hidden :: proc(h: ^Dialog_Handle, hidden: bool) {
	host := ui_view_controller_view(g_app.nav)
	for v in ([]rawptr{h.scrim, h.card}) {
		if v == nil do continue
		ui_view_set_hidden((^UI_View)(v), NS.BOOL(hidden))
		if !hidden do ui_view_bring_to_front(host, (^UI_View)(v))
	}
	ios_dialog_apply_modal()
}

// The swipe-back gesture follows the top page's modal state.
@(private)
ios_dialog_apply_modal :: proc() {
	ui_gesture_recognizer_set_enabled(ui_navigation_controller_pop_gesture(g_app.nav), NS.BOOL(dialog_top_modal() == nil))
}

}
