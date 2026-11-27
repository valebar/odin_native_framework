#+build darwin:default
#+private
package nv

// macOS Row / Column backend: NSStackView with Fill distribution. A flex child gets a low
// hugging priority so the spare space goes to it, and flex_link_sizes ties the flex children's
// sizes together in the ratio of their weights. Alignment Width / Height stretches every child
// across the cross axis.

import NS "core:sys/darwin/Foundation"
import AK "vendor:darwin/AppKit"

@(private)
_flex_create :: proc(f: Flex) -> View {
	stack := objc_own(stack_view_new({{0, 0}, {400, 600}})) // arranged subviews are retained by the stack
	stack_view_set_orientation(stack, NS.Integer(f.axis))
	stack_view_set_spacing(stack, NS.Float(f.spacing))
	stack_view_set_distribution(stack, STACK_DISTRIBUTION_FILL)
	stack_view_set_alignment(stack, f.axis == .Vertical ? LAYOUT_ATTRIBUTE_WIDTH : LAYOUT_ATTRIBUTE_HEIGHT)

	for c in f.children {
		child := (^AK.View)(c.view)
		view_set_translates_autoresizing_mask(child, false)
		stack_view_add_arranged_subview(stack, child)
		priority := c.flex > 0 ? LAYOUT_PRIORITY_FLEX : LAYOUT_PRIORITY_REQUIRED
		view_set_content_hugging_priority(child, priority, NS.Integer(f.axis))
		container_forward_hugging(child, priority, f.axis)
		// The cross axis stretches every child (the stack's fill alignment ranks below a view's
		// default hugging, so a label or a fixed-size container would otherwise keep its width).
		cross := f.axis == .Vertical ? Axis.Horizontal : Axis.Vertical
		view_set_content_hugging_priority(child, LAYOUT_PRIORITY_FLEX, NS.Integer(cross))
		container_forward_hugging(child, LAYOUT_PRIORITY_FLEX, cross)
	}
	flex_link_sizes(f.children, f.axis)
	return View(stack)
}
