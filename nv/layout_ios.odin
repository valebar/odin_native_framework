#+build darwin:ios
#+private
package nv

// iOS Layout backend: NVLayoutView, a UIView subclass with the child pinned to its edges. Its
// layoutSubviews reports the bounds before [super layoutSubviews] (which applies Auto Layout to the
// child), so what the app changes in on_layout shows in the same frame.

import NS "core:sys/darwin/Foundation"
import OBJC "core:sys/darwin/ObjectiveC"

@(private) layout_class: NS.Class

@(private)
_layout_init :: proc(h: ^Layout_Handle) {
	cls := objc_class(&layout_class, "NVLayoutView", "UIView", {
		{"layoutSubviews", auto_cast layout_layout_subviews, "v@:"},
	})
	obj := objc_alloc_with_handle(cls, h)
	root := objc_own(send(^UI_View, (^UI_View)(obj), "initWithFrame:", NS.Rect{}))
	child := (^UI_View)(h.layout.child)
	ui_view_set_translates_autoresizing_mask(child, false)
	ui_view_add_subview(root, child) // retains it; the child's +1 belongs to its creator's scope
	layout_pin_child(child, root)
	for axis in Axis do ui_view_set_content_hugging_priority(child, LAYOUT_PRIORITY_FLEX, NS.Integer(axis))
	h.root = View(root)
}

@(private)
layout_layout_subviews :: proc "c" (self: NS.id, cmd: NS.SEL) {
	h := objc_handle(self, Layout_Handle)
	context = h.ctx
	bounds := send(NS.Rect, (^NS.Object)(self), "bounds")
	layout_notify(h, f64(bounds.size.width), f64(bounds.size.height))
	objc_send_super(self, layout_class, cmd)
}

// See layout_macos.odin.
@(private)
layout_forward_hugging :: proc "c" (v: ^UI_View, priority: f32, axis: Axis) -> bool {
	if layout_class == nil || OBJC.object_getClass(NS.id(v)) != layout_class do return false
	h := objc_handle(NS.id(v), Layout_Handle)
	child := (^UI_View)(h.layout.child)
	ui_view_set_content_hugging_priority(child, priority, NS.Integer(axis))
	container_forward_hugging(child, priority, axis)
	return true
}
