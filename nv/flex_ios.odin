#+build darwin
package nv

// iOS Row / Column backend: UIStackView. Distribution and alignment already default to Fill;
// flex children get a low hugging priority and are tied together by flex_link_sizes.

import NS "core:sys/darwin/Foundation"

when IS_IOS {

@(private)
_flex_create :: proc(f: Flex) -> View {
	stack := ui_stack_view_new()
	ui_stack_view_set_axis(stack, NS.Integer(f.axis))
	ui_stack_view_set_spacing(stack, NS.Float(f.spacing))

	for c in f.children {
		child := (^UI_View)(c.view)
		ui_stack_view_add_arranged_subview(stack, child)
		priority := c.flex > 0 ? LAYOUT_PRIORITY_FLEX : LAYOUT_PRIORITY_REQUIRED
		ui_view_set_content_hugging_priority(child, priority, NS.Integer(f.axis))
		container_forward_hugging(child, priority, f.axis)
	}
	flex_link_sizes(f.children, f.axis)
	return View(stack)
}

}
