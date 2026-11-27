#+build darwin:ios
#+private
package nv

// iOS dialog backend: the card is a UIView (tertiary system background, or white with the light
// interface style for a light dialog, which its subviews inherit; rounded layer) added to the
// navigation controller's view, which puts it over the navigation bar too, and placed by Auto
// Layout (layout_dialog_card in appkit.odin); a modal dialog first adds a translucent black view
// pinned to the host's edges, with a UITapGestureRecognizer that reports a tap for a dismissible
// dialog (a tap on the card is the card's). A UIView takes the touches that land on it, so the
// scrim blocks the page and the bar by existing; the swipe-back gesture is turned off while a
// modal dialog is visible. The card and the scrim are retained and autoreleased before removal,
// since the close often runs from one of the card's own buttons' actions.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(private) dialog_scrim_target_class: NS.Class
@(private) g_dialog_scrim_target: ^NS.Object // the recognizers' target, kept for the app's life

@(private)
_dialog_show :: proc(h: ^Dialog_Handle) {
	host := ui_view_controller_view(g_app.nav)
	if h.dialog.modal {
		scrim := ui_view_new()
		ui_view_set_background_color(scrim, (^UI_Color)(canvas_color(dialog_scrim(h))))
		if g_dialog_scrim_target == nil {
			cls := objc_class(&dialog_scrim_target_class, "NVDialogScrimTarget", "NSObject", {
				{"nvScrim:", auto_cast dialog_scrim_tapped, "v@:@"},
			})
			g_dialog_scrim_target = send(^NS.Object, (^NS.Object)(rawptr(cls)), "new")
		}
		tap := send(^NS.Object, objc_class_object("UITapGestureRecognizer"), "alloc")
		tap = send(^NS.Object, tap, "initWithTarget:action:", g_dialog_scrim_target, intrinsics.objc_find_selector("nvScrim:"))
		send(nil, scrim, "addGestureRecognizer:", tap)
		tap->release() // the scrim owns it
		ui_view_set_translates_autoresizing_mask(scrim, false)
		ui_view_add_subview(host, scrim)
		scrim->release() // the host owns it
		layout_pin_edges(scrim, host)
		h.scrim = scrim
	}

	card := ui_view_new()
	if h.dialog.light {
		ui_view_set_background_color(card, (^UI_Color)(canvas_color(DIALOG_LIGHT)))
		send(nil, card, "setOverrideUserInterfaceStyle:", UI_USER_INTERFACE_STYLE_LIGHT)
	} else {
		ui_view_set_background_color(card, ui_color_tertiary_system_background())
	}
	ui_view_set_corner_radius(card, NS.Float(dialog_radius(h, 14)))
	ui_view_set_translates_autoresizing_mask(card, false)
	ui_view_add_subview(host, card) // after the scrim: above it
	card->release()
	h.card = card

	body := (^UI_View)(h.body)
	ui_view_set_translates_autoresizing_mask(body, false)
	ui_view_add_subview(card, body) // the body keeps its own +1 until _dialog_close
	layout_dialog_card(card, body, host, NS.Float(dialog_width(h)), 16)
	if h.dialog.modal do ui_view_end_editing(host) // the page's field gives up the keyboard
	ios_dialog_apply_modal()
}

// The card and the scrim are autoreleased, since the close often runs from one of the body's
// buttons; the body's views go with the dialog's scope.
@(private)
_dialog_close :: proc(h: ^Dialog_Handle) {
	for v in ([]rawptr{h.card, h.scrim}) {
		if v == nil do continue
		send(nil, (^NS.Object)(v), "retain")
		send(nil, (^NS.Object)(v), "autorelease")
		ui_view_remove_from_superview((^UI_View)(v)) // also drops the constraints that mention it
	}
	scope_retire(h.scope)
	ios_dialog_apply_modal()
}

@(private)
dialog_scrim_tapped :: proc "c" (_: NS.id, _: NS.SEL, tap: NS.id) {
	dialog_scrim_notify(rawptr(send(^NS.Object, (^NS.Object)(tap), "view")))
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
