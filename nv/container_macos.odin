#+build darwin:default
#+private
package nv

// macOS container backend: the root is an NSView subclass, NVContainerView, registered at runtime
// only to report a fixed `width` / `height` as its intrinsicContentSize (-1, no metric, on the
// other axis, which Auto Layout then takes from the child). Inside it a custom NSBox (the fill,
// corner radius and border) is pinned by the margin, and the child is pinned inside the box by the
// padding plus the border width. NSBox does not clip its subviews to the corners.

import NS "core:sys/darwin/Foundation"
import AK "vendor:darwin/AppKit"
import OBJC "core:sys/darwin/ObjectiveC"

@(private) container_class: NS.Class

@(private)
_container_init :: proc(h: ^Container_Handle) {
	cls := objc_class(&container_class, "NVContainerView", "NSView", {
		{"intrinsicContentSize", auto_cast container_intrinsic_size, "{CGSize=dd}@:"},
	})
	obj := objc_alloc_with_handle(cls, h)
	root := objc_own(send(^AK.View, (^AK.View)(obj), "initWithFrame:", NS.Rect{}))
	c := &h.container

	box := box_new({})
	if c.color.a > 0 do box_set_fill_color(box, (^AK.Color)(canvas_color(c.color)))
	box_set_corner_radius(box, NS.Float(c.radius))
	if c.border_width > 0 do box_set_border(box, (^AK.Color)(canvas_color(c.border_color)), NS.Float(c.border_width))
	view_set_translates_autoresizing_mask(box, false)
	root->addSubview(box)
	box->release() // the root owns it
	h.box = box
	layout_pin_insets(box, root, NS.Float(c.margin.top), NS.Float(c.margin.left), NS.Float(c.margin.bottom), NS.Float(c.margin.right))

	if c.child != nil {
		child := (^AK.View)(c.child)
		view_set_translates_autoresizing_mask(child, false)
		box_content_view(box)->addSubview(child) // retains it; the child's +1 belongs to its creator's scope
		b := c.border_width
		layout_pin_insets(child, box, NS.Float(c.padding.top + b), NS.Float(c.padding.left + b), NS.Float(c.padding.bottom + b), NS.Float(c.padding.right + b))
	}
	// A fixed axis holds against the child's compression resistance (750 by default on both), but
	// not against the stack's required cross-axis stretch or fill, which would be a conflict.
	if c.width > 0 do view_set_content_compression_resistance_priority(root, LAYOUT_PRIORITY_FIXED, NS.Integer(Axis.Horizontal))
	if c.height > 0 do view_set_content_compression_resistance_priority(root, LAYOUT_PRIORITY_FIXED, NS.Integer(Axis.Vertical))
	h.root = View(root)
}

@(private)
_container_set_color :: proc(h: ^Container_Handle) {
	box := (^Box)(h.box)
	c := h.container.color
	box_set_fill_color(box, (^AK.Color)(canvas_color(c.a > 0 ? c : {0, 0, 0, 0})))
	send(nil, box, "setNeedsDisplay:", NS.BOOL(true))
}

// The stack view's hugging priority applies to the container's root, but stretching is decided
// against the child's own priority (a label's 250), so a flex-0 container would take the spare
// space. The priority is passed down to the child, except on an axis with a fixed size, where the
// root's intrinsic size decides and a required hugging on the child would conflict with it.
@(private)
container_forward_hugging :: proc "c" (v: ^AK.View, priority: f32, axis: Axis) {
	if layout_forward_hugging(v, priority, axis) do return
	if container_class == nil || OBJC.object_getClass(NS.id(v)) != container_class do return
	h := objc_handle(NS.id(v), Container_Handle)
	if h.container.child == nil do return
	if (axis == .Horizontal ? h.container.width : h.container.height) > 0 do return
	child := (^AK.View)(h.container.child)
	view_set_content_hugging_priority(child, priority, NS.Integer(axis))
	container_forward_hugging(child, priority, axis)
}

@(private)
container_intrinsic_size :: proc "c" (self: NS.id, _: NS.SEL) -> NS.Size {
	h := objc_handle(self, Container_Handle)
	return container_intrinsic(h)
}

// A fixed axis holds at LAYOUT_PRIORITY_FIXED and leaves the stretching to the root's intrinsic
// size; a free one passes the root's hugging on to the child again (container_forward_hugging).
@(private)
_container_set_size :: proc(h: ^Container_Handle) {
	root := (^AK.View)(h.root)
	c := &h.container
	for axis in Axis {
		fixed := (axis == .Horizontal ? c.width : c.height) > 0
		view_set_content_compression_resistance_priority(root, fixed ? LAYOUT_PRIORITY_FIXED : 750, NS.Integer(axis))
		if c.child == nil do continue
		child := (^AK.View)(c.child)
		if fixed do view_set_content_hugging_priority(child, 250, NS.Integer(axis))
		else do container_forward_hugging(child, send(f32, root, "contentHuggingPriorityForOrientation:", NS.Integer(axis)), axis)
	}
	send(nil, root, "invalidateIntrinsicContentSize")
}
