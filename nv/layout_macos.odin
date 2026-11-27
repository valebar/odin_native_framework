#+build darwin:default
#+private
package nv

// macOS Layout backend: NVLayoutView, an NSView subclass with the child pinned to its edges (the far
// ones just below required: the Layout takes its parent's size, layout_pin_child). Its
// `layout` reports the bounds before [super layout], so what the app changes in on_layout is solved
// in the same pass, before display; `setFrameSize:` asks for that pass when only the size changed.

import NS "core:sys/darwin/Foundation"
import AK "vendor:darwin/AppKit"
import OBJC "core:sys/darwin/ObjectiveC"

@(private) layout_class: NS.Class

@(private)
_layout_init :: proc(h: ^Layout_Handle) {
	cls := objc_class(&layout_class, "NVLayoutView", "NSView", {
		{"layout", auto_cast layout_layout, "v@:"},
		{"setFrameSize:", auto_cast layout_set_frame_size, "v@:{CGSize=dd}"},
	})
	obj := objc_alloc_with_handle(cls, h)
	root := objc_own(send(^AK.View, (^AK.View)(obj), "initWithFrame:", NS.Rect{}))
	child := (^AK.View)(h.layout.child)
	view_set_translates_autoresizing_mask(child, false)
	root->addSubview(child) // retains it; the child's +1 belongs to its creator's scope
	layout_pin_child(child, root)
	for axis in Axis do view_set_content_hugging_priority(child, LAYOUT_PRIORITY_FLEX, NS.Integer(axis))
	h.root = View(root)
}

@(private)
layout_layout :: proc "c" (self: NS.id, cmd: NS.SEL) {
	h := objc_handle(self, Layout_Handle)
	context = h.ctx
	bounds := send(NS.Rect, (^NS.Object)(self), "bounds")
	layout_notify(h, f64(bounds.size.width), f64(bounds.size.height))
	objc_send_super(self, layout_class, cmd)
}

@(private)
layout_set_frame_size :: proc "c" (self: NS.id, cmd: NS.SEL, size: NS.Size) {
	old := send(NS.Rect, (^NS.Object)(self), "frame").size
	sup := OBJC.objc_super{receiver = self, super_class = OBJC.class_getSuperclass(layout_class)}
	(proc "c" (^OBJC.objc_super, NS.SEL, NS.Size))(rawptr(OBJC.objc_msgSendSuper))(&sup, cmd, size)
	if old != size do send(nil, (^NS.Object)(self), "setNeedsLayout:", NS.BOOL(true))
}

// A Layout passes the hugging priority it gets on to its child (see container_forward_hugging).
@(private)
layout_forward_hugging :: proc "c" (v: ^AK.View, priority: f32, axis: Axis) -> bool {
	if layout_class == nil || OBJC.object_getClass(NS.id(v)) != layout_class do return false
	h := objc_handle(NS.id(v), Layout_Handle)
	child := (^AK.View)(h.layout.child)
	view_set_content_hugging_priority(child, priority, NS.Integer(axis))
	container_forward_hugging(child, priority, axis)
	return true
}
