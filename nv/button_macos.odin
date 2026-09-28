#+build darwin
package nv

// macOS button backend: a bezel push button (NSButton buttonWithTitle:target:action:) whose
// action goes to an NVButtonTarget object. A custom font goes on the button (NSControl setFont:);
// the push bezel keeps its height, so a large size clips.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

when !IS_IOS {

@(private) button_class: NS.Class

@(private)
_button_init :: proc(h: ^Button_Handle) {
	t := objc_own(button_target_alloc(h)) // weak target; lives as long as the handle's scope
	button := button_push(ns_string(h.button.title), t, intrinsics.objc_find_selector("nvClick:")) // autoreleased
	objc_own(button)->retain()
	if h.button.font != nil || h.button.size != 0 { // else the button's own 13pt system font
		send(nil, button, "setFont:", text_font(h.button.font, h.button.size != 0 ? h.button.size : 13, false))
	}

	h.root = View(button)
	h.control = button
	h.target = t
}

@(private)
_button_set_title :: proc(h: ^Button_Handle, title: string) {
	button_set_title_ns((^Button_View)(h.control), ns_string(title))
}

@(private)
button_target_alloc :: proc(h: ^Button_Handle) -> NS.id {
	cls := objc_class(&button_class, "NVButtonTarget", "NSObject", {
		{"nvClick:", auto_cast button_clicked, "v@:@"},
	})
	return objc_alloc_with_handle(cls, h)
}

@(private)
button_clicked :: proc "c" (self: NS.id, _: NS.SEL, _: NS.id) {
	h := objc_handle(self, Button_Handle)
	context = h.ctx
	button_notify(h)
}

}
