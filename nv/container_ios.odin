#+build darwin:ios
#+private
package nv

// iOS container backend: like macOS, a UIView subclass (NVContainerView) for the intrinsic size
// with a plain UIView box inside it, whose CALayer gives the corner radius and the border and clips
// the child to the corners (masksToBounds).

import NS "core:sys/darwin/Foundation"
import OBJC "core:sys/darwin/ObjectiveC"

@(private) container_class: NS.Class

@(private)
_container_init :: proc(h: ^Container_Handle) {
	cls := objc_class(&container_class, "NVContainerView", "UIView", {
		{"intrinsicContentSize", auto_cast container_intrinsic_size, "{CGSize=dd}@:"},
	})
	obj := objc_alloc_with_handle(cls, h)
	root := objc_own(send(^UI_View, (^UI_View)(obj), "initWithFrame:", NS.Rect{}))
	c := &h.container

	box := ui_view_new()
	if c.color.a > 0 do ui_view_set_background_color(box, (^UI_Color)(canvas_color(c.color)))
	ui_view_set_corner_radius(box, NS.Float(c.radius))
	if c.border_width > 0 do ui_view_set_layer_border(box, (^UI_Color)(canvas_color(c.border_color)), NS.Float(c.border_width))
	ui_view_set_masks_to_bounds(box, true)
	ui_view_set_translates_autoresizing_mask(box, false)
	ui_view_add_subview(root, box)
	box->release() // the root owns it
	h.box = box
	layout_pin_insets(box, root, NS.Float(c.margin.top), NS.Float(c.margin.left), NS.Float(c.margin.bottom), NS.Float(c.margin.right))

	if c.child != nil {
		child := (^UI_View)(c.child)
		ui_view_set_translates_autoresizing_mask(child, false)
		ui_view_add_subview(box, child) // retains it; the child's +1 belongs to its creator's scope
		b := c.border_width // the layer's border is drawn inside the bounds
		layout_pin_insets(child, box, NS.Float(c.padding.top + b), NS.Float(c.padding.left + b), NS.Float(c.padding.bottom + b), NS.Float(c.padding.right + b))
	}
	if c.width > 0 do ui_view_set_content_compression_resistance_priority(root, LAYOUT_PRIORITY_FIXED, NS.Integer(Axis.Horizontal)) // see container_macos.odin
	if c.height > 0 do ui_view_set_content_compression_resistance_priority(root, LAYOUT_PRIORITY_FIXED, NS.Integer(Axis.Vertical))
	h.root = View(root)
}

@(private)
_container_set_color :: proc(h: ^Container_Handle) {
	c := h.container.color
	ui_view_set_background_color((^UI_View)(h.box), (^UI_Color)(canvas_color(c.a > 0 ? c : {0, 0, 0, 0})))
}

// See container_macos.odin.
@(private)
container_forward_hugging :: proc "c" (v: ^UI_View, priority: f32, axis: Axis) {
	if layout_forward_hugging(v, priority, axis) do return
	if container_class == nil || OBJC.object_getClass(NS.id(v)) != container_class do return
	h := objc_handle(NS.id(v), Container_Handle)
	if h.container.child == nil do return
	if (axis == .Horizontal ? h.container.width : h.container.height) > 0 do return
	child := (^UI_View)(h.container.child)
	ui_view_set_content_hugging_priority(child, priority, NS.Integer(axis))
	container_forward_hugging(child, priority, axis)
}

@(private)
container_intrinsic_size :: proc "c" (self: NS.id, _: NS.SEL) -> NS.Size {
	h := objc_handle(self, Container_Handle)
	return container_intrinsic(h)
}

// See container_macos.odin.
@(private)
_container_set_size :: proc(h: ^Container_Handle) {
	root := (^UI_View)(h.root)
	c := &h.container
	for axis in Axis {
		fixed := (axis == .Horizontal ? c.width : c.height) > 0
		ui_view_set_content_compression_resistance_priority(root, fixed ? LAYOUT_PRIORITY_FIXED : 750, NS.Integer(axis))
		if c.child == nil do continue
		child := (^UI_View)(c.child)
		if fixed do ui_view_set_content_hugging_priority(child, 250, NS.Integer(axis))
		else do container_forward_hugging(child, send(f32, root, "contentHuggingPriorityForAxis:", NS.Integer(axis)), axis)
	}
	send(nil, root, "invalidateIntrinsicContentSize")
}
