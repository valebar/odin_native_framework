#+build darwin
package nv

// Objective-C helpers shared by the macOS and iOS backends: `send`, `ns_string`, runtime classes
// and ownership (objc_class, objc_own), the bar's action target and the Auto Layout helpers.
// The AppKit-only bindings are in appkit_macos.odin, the UIKit ones in uikit.odin.

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(private) send :: intrinsics.objc_send

// Copies bytes, so the Odin string may be freed afterwards. Autoreleased.
ns_string :: proc "c" (s: string) -> ^NS.String {
	str := send(^NS.String, NS.String, "alloc")
	str = send(^NS.String, str, "initWithBytes:length:encoding:", raw_data(s), NS.UInteger(len(s)), NS.StringEncoding.UTF8)
	send(nil, str, "autorelease")
	return str
}

// A method for objc_class: selector name, IMP (a `proc "c" (self: NS.id, _: NS.SEL, ..)`, passed
// through auto_cast) and its type encoding.
Objc_Method :: struct {
	sel:   cstring,
	imp:   NS.IMP,
	types: cstring,
}

// Registers `name` as a runtime subclass of `super` with `methods` (and `protocols`) the first time
// it is called with `cls^` nil, stores the class in `cls^` and returns it. Every backend delegate,
// target and view subclass goes through here; `cls` is the caller's package-level cache.
objc_class :: proc(cls: ^NS.Class, name, super: cstring, methods: []Objc_Method, protocols: []cstring = nil) -> NS.Class {
	if cls^ != nil do return cls^
	c := NS.objc_allocateClassPair(NS.objc_lookUpClass(super), name, 0)
	for m in methods do NS.class_addMethod(c, NS.sel_registerName(m.sel), m.imp, m.types)
	for p in protocols do NS.class_addProtocol(c, NS.objc_getProtocol(p))
	NS.objc_registerClassPair(c)
	cls^ = c
	return c
}

// class_createInstance with room for one pointer in the indexed ivars, set to `h`. Owned, like
// alloc; a view subclass still needs its initWithFrame:, a plain delegate needs no init.
objc_alloc_with_handle :: proc(cls: NS.Class, h: ^$T) -> NS.id {
	obj := NS.class_createInstance(cls, size_of(^T))
	(^^T)(NS.object_getIndexedIvars(obj))^ = h
	return obj
}

// The handle stored by objc_alloc_with_handle; contextless so an IMP can read it first and then
// set `context = h.ctx`.
objc_handle :: #force_inline proc "c" (self: NS.id, $T: typeid) -> ^T {
	return (^^T)(NS.object_getIndexedIvars(self))^
}

// Hands the creator's +1 on `obj` to the current scope (see Scope), which autoreleases it when
// the page or dialog body dies: autoreleased, not released, since that may happen right after a
// pop from the object's own action. Parents hold references of their own (addSubview,
// addArrangedSubview), so the views go once the tree is gone.
objc_own :: proc(obj: $T) -> T {
	scope_on_dispose(objc_autorelease, rawptr(obj))
	return obj
}

@(private)
objc_autorelease :: proc(data: rawptr) {
	send(nil, (^NS.Object)(data), "autorelease")
}

// Weak delegate / data source slots are cleared when the scope dies, so a view that outlives its
// delegate for a moment (the autorelease pool drains in any order) never calls a dead one.
objc_clear_delegate_on_dispose :: proc(obj: rawptr) {
	scope_on_dispose(proc(data: rawptr) { send(nil, (^NS.Object)(data), "setDelegate:", NS.id(nil)) }, obj)
}

objc_clear_data_source_on_dispose :: proc(obj: rawptr) {
	scope_on_dispose(proc(data: rawptr) { send(nil, (^NS.Object)(data), "setDataSource:", NS.id(nil)) }, obj)
}

// SF Symbol names by Icon (macOS 11+ / iOS 13+); "" shows the title as text.
@(private) sf_symbol_names := [Icon]string{
	.None     = "",
	.Add      = "plus",
	.Edit     = "pencil",
	.Delete   = "trash",
	.Search   = "magnifyingglass",
	.Share    = "square.and.arrow.up",
	.Settings = "gearshape",
	.Refresh  = "arrow.clockwise",
	.Done     = "checkmark",
	.Info     = "info.circle",
	.More     = "ellipsis",
	.Close    = "xmark",
}

// nvAction: for the bar's action buttons on both platforms. `sender` is the NSButton /
// UIBarButtonItem; its tag is the ^Action_Handle.
@(private)
nav_action_clicked :: proc "c" (self: NS.id, _: NS.SEL, sender: NS.id) {
	h := (^Action_Handle)(uintptr(object_tag((^NS.Object)(sender))))
	context = h.ctx
	action_notify(h)
}

// NSControl / UIBarItem tag: room for a pointer.
object_set_tag :: proc "c" (o: ^NS.Object, tag: NS.Integer) {
	send(nil, o, "setTag:", tag)
}

object_tag :: proc "c" (o: ^NS.Object) -> NS.Integer {
	return send(NS.Integer, o, "tag")
}

// Autoreleased array of the given objects (which it retains).
array_with_objects :: proc "c" (objects: [^]^NS.Object, count: int) -> ^NS.Array {
	return send(^NS.Array, NS.Array, "arrayWithObjects:count:", objects, NS.UInteger(count))
}

// NSLayoutConstraint exists in both AppKit and UIKit.
@(objc_class="NSLayoutConstraint")
Layout_Constraint :: struct { using _: NS.Object }

// NSLayoutAttribute / NSLayoutRelation
LAYOUT_ATTRIBUTE_WIDTH  :: NS.Integer(7)
LAYOUT_ATTRIBUTE_HEIGHT :: NS.Integer(8)
LAYOUT_RELATION_EQUAL   :: NS.Integer(0)

// NSLayoutPriority / UILayoutPriority
LAYOUT_PRIORITY_REQUIRED :: f32(1000)
LAYOUT_PRIORITY_FLEX     :: f32(1)
LAYOUT_PRIORITY_FIXED    :: f32(751) // a container's fixed size: above a child's default 750, below the stack's required stretch

// Activates `a.attr == b.attr * multiplier`.
layout_constraint_equal :: proc "c" (a: NS.id, b: NS.id, attr: NS.Integer, multiplier: NS.Float) {
	c := send(^Layout_Constraint, Layout_Constraint, "constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:constant:",
		a, attr, LAYOUT_RELATION_EQUAL, b, attr, multiplier, NS.Float(0))
	send(nil, c, "setActive:", NS.BOOL(true))
}

// NSLayoutAnchor exists in both AppKit and UIKit: the anchor API positions the dialog card on both.
@(objc_class="NSLayoutAnchor")
Layout_Anchor :: struct { using _: NS.Object }

anchor_top      :: proc "c" (v: ^NS.Object) -> ^Layout_Anchor { return send(^Layout_Anchor, v, "topAnchor") }
anchor_bottom   :: proc "c" (v: ^NS.Object) -> ^Layout_Anchor { return send(^Layout_Anchor, v, "bottomAnchor") }
anchor_leading  :: proc "c" (v: ^NS.Object) -> ^Layout_Anchor { return send(^Layout_Anchor, v, "leadingAnchor") }
anchor_trailing :: proc "c" (v: ^NS.Object) -> ^Layout_Anchor { return send(^Layout_Anchor, v, "trailingAnchor") }
anchor_center_x :: proc "c" (v: ^NS.Object) -> ^Layout_Anchor { return send(^Layout_Anchor, v, "centerXAnchor") }
anchor_center_y :: proc "c" (v: ^NS.Object) -> ^Layout_Anchor { return send(^Layout_Anchor, v, "centerYAnchor") }
anchor_width    :: proc "c" (v: ^NS.Object) -> ^Layout_Anchor { return send(^Layout_Anchor, v, "widthAnchor") }

// Activates `a == b`.
layout_anchor_equal :: proc "c" (a, b: ^Layout_Anchor) {
	c := send(^Layout_Constraint, a, "constraintEqualToAnchor:", b)
	send(nil, c, "setActive:", NS.BOOL(true))
}

// Activates `a == b + constant`.
layout_anchor_equal_offset :: proc "c" (a, b: ^Layout_Anchor, constant: NS.Float) {
	c := send(^Layout_Constraint, a, "constraintEqualToAnchor:constant:", b, constant)
	send(nil, c, "setActive:", NS.BOOL(true))
}

// Activates `a <= b + constant`.
layout_anchor_at_most :: proc "c" (a, b: ^Layout_Anchor, constant: NS.Float) {
	c := send(^Layout_Constraint, a, "constraintLessThanOrEqualToAnchor:constant:", b, constant)
	send(nil, c, "setActive:", NS.BOOL(true))
}

// Activates `a == constant` at the given priority (below Required it yields to other constraints).
layout_anchor_constant :: proc "c" (a: ^Layout_Anchor, constant: NS.Float, priority: f32) {
	c := send(^Layout_Constraint, a, "constraintEqualToConstant:", constant)
	send(nil, c, "setPriority:", priority)
	send(nil, c, "setActive:", NS.BOOL(true))
}

// Activates `a == b` at the given priority.
layout_anchor_equal_priority :: proc "c" (a, b: ^Layout_Anchor, priority: f32) {
	c := send(^Layout_Constraint, a, "constraintEqualToAnchor:", b)
	send(nil, c, "setPriority:", priority)
	send(nil, c, "setActive:", NS.BOOL(true))
}

// Pins a page to the top-left of `parent`, filling it at priority 499: below the window's
// size (500), so a page that can't stretch ends short instead of shrinking the window.
// The `<=` keeps a page larger than the window growing it.
layout_pin_page :: proc "c" (child, parent: ^NS.Object) {
	layout_anchor_equal(anchor_top(child), anchor_top(parent))
	layout_anchor_equal(anchor_leading(child), anchor_leading(parent))
	layout_anchor_at_most(anchor_bottom(child), anchor_bottom(parent), 0)
	layout_anchor_at_most(anchor_trailing(child), anchor_trailing(parent), 0)
	layout_anchor_equal_priority(anchor_bottom(child), anchor_bottom(parent), 499)
	layout_anchor_equal_priority(anchor_trailing(child), anchor_trailing(parent), 499)
}

// Pins every edge of `child` to `parent` (both already in the same hierarchy).
layout_pin_edges :: proc "c" (child, parent: ^NS.Object) {
	layout_anchor_equal(anchor_top(child), anchor_top(parent))
	layout_anchor_equal(anchor_bottom(child), anchor_bottom(parent))
	layout_anchor_equal(anchor_leading(child), anchor_leading(parent))
	layout_anchor_equal(anchor_trailing(child), anchor_trailing(parent))
}

// Pins `child` inside `parent` (both already in the same hierarchy) at the given distances from
// each edge.
layout_pin_insets :: proc "c" (child, parent: ^NS.Object, top, leading, bottom, trailing: NS.Float) {
	layout_anchor_equal_offset(anchor_top(child), anchor_top(parent), top)
	layout_anchor_equal_offset(anchor_leading(child), anchor_leading(parent), leading)
	layout_anchor_equal_offset(anchor_bottom(parent), anchor_bottom(child), bottom)
	layout_anchor_equal_offset(anchor_trailing(parent), anchor_trailing(child), trailing)
}

// Places the dialog card in `host` (both Auto Layout): centered, `width` wide unless the host is
// narrower than that plus the margins, with `body` inset by `pad` on every side. The card's height
// follows the body.
layout_dialog_card :: proc "c" (card, body, host: ^NS.Object, width, pad: NS.Float) {
	layout_anchor_equal(anchor_center_x(card), anchor_center_x(host))
	layout_anchor_equal(anchor_center_y(card), anchor_center_y(host))
	layout_anchor_constant(anchor_width(card), width, 999)
	layout_anchor_at_most(anchor_width(card), anchor_width(host), -2 * pad)
	layout_pin_insets(body, card, pad, pad, pad, pad)
}

// Ties the main-axis size of every flex child to the first flex child, in the ratio of their
// weights. Together with a low hugging priority this gives exact Flutter weights in a stack view.
flex_link_sizes :: proc(children: []Flex_Child, axis: Axis) {
	attr := axis == .Vertical ? LAYOUT_ATTRIBUTE_HEIGHT : LAYOUT_ATTRIBUTE_WIDTH
	first: Flex_Child
	for c in children {
		if c.flex <= 0 do continue
		if first.view == nil {
			first = c
			continue
		}
		layout_constraint_equal(NS.id(c.view), NS.id(first.view), attr, NS.Float(c.flex) / NS.Float(first.flex))
	}
}

// The root's intrinsic size: a fixed width / height plus the margin, or -1 (NSViewNoIntrinsicMetric,
// UIViewNoIntrinsicMetric) for an axis that follows the child.
@(private)
container_intrinsic :: proc "c" (h: ^Container_Handle) -> NS.Size {
	c := &h.container
	return {
		c.width > 0 ? NS.Float(c.width + c.margin.left + c.margin.right) : -1,
		c.height > 0 ? NS.Float(c.height + c.margin.top + c.margin.bottom) : -1,
	}
}
