#+build darwin
package nv

// Minimal hand-written AppKit bindings not covered by core:sys/darwin/Foundation.
// `send`, `ns_string` and the Auto Layout helpers are shared with the iOS backend.

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

when !IS_IOS {

// NSAutoresizingMaskOptions
RESIZE_MIN_X_MARGIN :: NS.UInteger(1)
RESIZE_WIDTH        :: NS.UInteger(2)
RESIZE_MAX_X_MARGIN :: NS.UInteger(4)
RESIZE_MIN_Y_MARGIN :: NS.UInteger(8)
RESIZE_HEIGHT       :: NS.UInteger(16)
RESIZE_MAX_Y_MARGIN :: NS.UInteger(32)

// NSLayoutAttributeLeading: a titlebar accessory next to the window buttons (macOS 11+);
// Trailing: at the far end of the title bar.
LAYOUT_ATTRIBUTE_LEADING  :: NS.Integer(5)
LAYOUT_ATTRIBUTE_TRAILING :: NS.Integer(6)

// NSBezelStyleTexturedRounded (NSBezelStyleToolbar): the look of a title bar button.
BEZEL_STYLE_TEXTURED_ROUNDED :: NS.Integer(11)

@(objc_class="NSTitlebarAccessoryViewController")
Titlebar_Accessory_View_Controller :: struct { using _: NS.Object }

Table_View_Style_Plain :: 4

@(objc_class="NSScrollView")
Scroll_View :: struct { using _: NS.View }

@(objc_class="NSStackView")
Stack_View :: struct { using _: NS.View }

// NSStackViewDistribution (GravityAreas is -1, so Fill is 0 like UIStackViewDistributionFill).
STACK_DISTRIBUTION_FILL :: NS.Integer(0)

@(objc_class="NSTableView")
Table_View :: struct { using _: NS.View }

@(objc_class="NSTableColumn")
Table_Column :: struct { using _: NS.Object }

@(objc_class="NSTextField")
Text_Field :: struct { using _: NS.View }

@(objc_class="NSButton")
Button_View :: struct { using _: NS.View }

@(objc_class="NSFont")
NS_Font :: struct { using _: NS.Object } // `Font` is the public loaded-font type

@(objc_class="NSGraphicsContext")
Graphics_Context :: struct { using _: NS.Object }

@(objc_class="NSBox")
Box :: struct { using _: NS.View }

// NSBoxCustom: no title, the fill and corner radius are the box's own.
BOX_TYPE_CUSTOM   :: NS.Integer(4)
BOX_TITLE_NONE    :: NS.Integer(0)

view_set_frame :: proc "c" (v: ^NS.View, frame: NS.Rect) {
	send(nil, v, "setFrame:", frame)
}

view_set_hidden :: proc "c" (v: ^NS.View, hidden: NS.BOOL) {
	send(nil, v, "setHidden:", hidden)
}

view_remove_from_superview :: proc "c" (v: ^NS.View) {
	send(nil, v, "removeFromSuperview")
}

// Returns an owned (+1) custom box: a plain filled rectangle with optional rounded corners.
box_new :: proc "c" (frame: NS.Rect) -> ^Box {
	b := send(^Box, Box, "alloc")
	b = send(^Box, b, "initWithFrame:", frame)
	send(nil, b, "setBoxType:", BOX_TYPE_CUSTOM)
	send(nil, b, "setTitlePosition:", BOX_TITLE_NONE)
	send(nil, b, "setBorderWidth:", NS.Float(0))
	send(nil, b, "setContentViewMargins:", NS.Size{0, 0})
	return b
}

box_set_fill_color :: proc "c" (b: ^Box, c: ^NS.Color) {
	send(nil, b, "setFillColor:", c)
}

box_set_corner_radius :: proc "c" (b: ^Box, r: NS.Float) {
	send(nil, b, "setCornerRadius:", r)
}

// The border of a custom box, drawn inside its bounds.
box_set_border :: proc "c" (b: ^Box, c: ^NS.Color, width: NS.Float) {
	send(nil, b, "setBorderColor:", c)
	send(nil, b, "setBorderWidth:", width)
}

// The box's inner view, which holds its subviews.
box_content_view :: proc "c" (b: ^Box) -> ^NS.View {
	return send(^NS.View, b, "contentView")
}

color_window_background :: proc "c" () -> ^NS.Color {
	return send(^NS.Color, NS.Color, "windowBackgroundColor")
}

view_set_autoresizing :: proc "c" (v: ^NS.View, mask: NS.UInteger) {
	send(nil, v, "setAutoresizingMask:", mask)
}

view_with_tag :: proc "c" (v: ^NS.View, tag: NS.Integer) -> ^NS.View {
	return send(^NS.View, v, "viewWithTag:", tag)
}

view_set_tool_tip :: proc "c" (v: ^NS.View, s: ^NS.String) {
	send(nil, v, "setToolTip:", s)
}

view_set_identifier :: proc "c" (v: ^NS.View, ident: ^NS.String) {
	send(nil, v, "setIdentifier:", ident)
}

view_set_translates_autoresizing_mask :: proc "c" (v: ^NS.View, translates: NS.BOOL) {
	send(nil, v, "setTranslatesAutoresizingMaskIntoConstraints:", translates)
}

// orientation: NSLayoutConstraintOrientation, same values as Axis.
view_set_content_hugging_priority :: proc "c" (v: ^NS.View, priority: f32, orientation: NS.Integer) {
	send(nil, v, "setContentHuggingPriority:forOrientation:", priority, orientation)
}

view_set_content_compression_resistance_priority :: proc "c" (v: ^NS.View, priority: f32, orientation: NS.Integer) {
	send(nil, v, "setContentCompressionResistancePriority:forOrientation:", priority, orientation)
}

// Returns an owned (+1) stack view.
stack_view_new :: proc "c" (frame: NS.Rect) -> ^Stack_View {
	sv := send(^Stack_View, Stack_View, "alloc")
	return send(^Stack_View, sv, "initWithFrame:", frame)
}

// NSUserInterfaceLayoutOrientation, same values as Axis.
stack_view_set_orientation :: proc "c" (sv: ^Stack_View, orientation: NS.Integer) {
	send(nil, sv, "setOrientation:", orientation)
}

stack_view_set_spacing :: proc "c" (sv: ^Stack_View, spacing: NS.Float) {
	send(nil, sv, "setSpacing:", spacing)
}

stack_view_set_distribution :: proc "c" (sv: ^Stack_View, distribution: NS.Integer) {
	send(nil, sv, "setDistribution:", distribution)
}

// NSLayoutAttribute; Width / Height stretch children across the cross axis.
stack_view_set_alignment :: proc "c" (sv: ^Stack_View, alignment: NS.Integer) {
	send(nil, sv, "setAlignment:", alignment)
}

stack_view_add_arranged_subview :: proc "c" (sv: ^Stack_View, v: ^NS.View) {
	send(nil, sv, "addArrangedSubview:", v)
}

scroll_view_new :: proc "c" (frame: NS.Rect) -> ^Scroll_View {
	sv := send(^Scroll_View, Scroll_View, "alloc")
	return send(^Scroll_View, sv, "initWithFrame:", frame)
}

scroll_view_set_document_view :: proc "c" (sv: ^Scroll_View, v: ^NS.View) {
	send(nil, sv, "setDocumentView:", v)
}

scroll_view_set_has_vertical_scroller :: proc "c" (sv: ^Scroll_View, has: NS.BOOL) {
	send(nil, sv, "setHasVerticalScroller:", has)
}

table_view_new :: proc "c" (frame: NS.Rect) -> ^Table_View {
	tv := send(^Table_View, Table_View, "alloc")
	return send(^Table_View, tv, "initWithFrame:", frame)
}

table_view_add_column :: proc "c" (tv: ^Table_View, col: ^Table_Column) {
	send(nil, tv, "addTableColumn:", col)
}

table_view_set_data_source :: proc "c" (tv: ^Table_View, ds: NS.id) {
	send(nil, tv, "setDataSource:", ds)
}

table_view_set_delegate :: proc "c" (tv: ^Table_View, d: NS.id) {
	send(nil, tv, "setDelegate:", d)
}

table_view_set_header_view :: proc "c" (tv: ^Table_View, v: ^NS.View) {
	send(nil, tv, "setHeaderView:", v)
}

table_view_set_style :: proc "c" (tv: ^Table_View, style: NS.Integer) {
	send(nil, tv, "setStyle:", style)
}

table_view_set_row_height :: proc "c" (tv: ^Table_View, h: NS.Float) {
	send(nil, tv, "setRowHeight:", h)
}

table_view_reload_data :: proc "c" (tv: ^Table_View) {
	send(nil, tv, "reloadData")
}

table_view_make_view :: proc "c" (tv: ^Table_View, ident: ^NS.String) -> ^NS.View {
	return send(^NS.View, tv, "makeViewWithIdentifier:owner:", ident, NS.id(nil))
}

table_view_selected_row :: proc "c" (tv: ^Table_View) -> NS.Integer {
	return send(NS.Integer, tv, "selectedRow")
}

table_view_size_last_column_to_fit :: proc "c" (tv: ^Table_View) {
	send(nil, tv, "sizeLastColumnToFit")
}

// Returns an owned (+1) column.
table_column_new :: proc "c" (ident: ^NS.String) -> ^Table_Column {
	col := send(^Table_Column, Table_Column, "alloc")
	return send(^Table_Column, col, "initWithIdentifier:", ident)
}

table_column_set_resizing_mask :: proc "c" (col: ^Table_Column, mask: NS.UInteger) {
	send(nil, col, "setResizingMask:", mask)
}

// Autoreleased.
text_field_label :: proc "c" (s: ^NS.String) -> ^Text_Field {
	return send(^Text_Field, Text_Field, "labelWithString:", s)
}

text_field_set_string :: proc "c" (tf: ^Text_Field, s: ^NS.String) {
	send(nil, tf, "setStringValue:", s)
}

text_field_set_font :: proc "c" (tf: ^Text_Field, f: ^NS_Font) {
	send(nil, tf, "setFont:", f)
}

text_field_set_text_color :: proc "c" (tf: ^Text_Field, c: ^NS.Color) {
	send(nil, tf, "setTextColor:", c)
}

text_field_set_tag :: proc "c" (tf: ^Text_Field, tag: NS.Integer) {
	send(nil, tf, "setTag:", tag)
}

// Autoreleased editable field: single line, non-wrapping, scrolls horizontally.
text_field_editable :: proc "c" (s: ^NS.String) -> ^Text_Field {
	return send(^Text_Field, Text_Field, "textFieldWithString:", s)
}

text_field_set_placeholder :: proc "c" (tf: ^Text_Field, s: ^NS.String) {
	send(nil, tf, "setPlaceholderString:", s)
}

text_field_set_delegate :: proc "c" (tf: ^Text_Field, d: NS.id) {
	send(nil, tf, "setDelegate:", d)
}

text_field_string :: proc "c" (tf: ^Text_Field) -> ^NS.String {
	return send(^NS.String, tf, "stringValue")
}

// Autoreleased bezel push button; `target` is weak.
button_push :: proc "c" (title: ^NS.String, target: NS.id, action: NS.SEL) -> ^Button_View {
	return send(^Button_View, Button_View, "buttonWithTitle:target:action:", title, target, action)
}

button_set_title_ns :: proc "c" (b: ^Button_View, title: ^NS.String) {
	send(nil, b, "setTitle:", title)
}

// Autoreleased image-only bezel button; `target` is weak.
button_with_image :: proc "c" (image: ^NS.Image, target: NS.id, action: NS.SEL) -> ^Button_View {
	return send(^Button_View, Button_View, "buttonWithImage:target:action:", image, target, action)
}

button_set_bezel_style :: proc "c" (b: ^Button_View, style: NS.Integer) {
	send(nil, b, "setBezelStyle:", style)
}

// Autoreleased SF Symbol (macOS 11+).
image_system_symbol :: proc "c" (name: ^NS.String, description: ^NS.String) -> ^NS.Image {
	return send(^NS.Image, NS.Image, "imageWithSystemSymbolName:accessibilityDescription:", name, description)
}

// Returns an owned (+1) controller.
titlebar_accessory_new :: proc "c" () -> ^Titlebar_Accessory_View_Controller {
	return send(^Titlebar_Accessory_View_Controller, Titlebar_Accessory_View_Controller, "new")
}

titlebar_accessory_set_view :: proc "c" (vc: ^Titlebar_Accessory_View_Controller, v: ^NS.View) {
	send(nil, vc, "setView:", v)
}

// NSLayoutAttribute: Leading / Trailing sit in the title bar, Bottom adds a strip below it.
titlebar_accessory_set_layout_attribute :: proc "c" (vc: ^Titlebar_Accessory_View_Controller, attr: NS.Integer) {
	send(nil, vc, "setLayoutAttribute:", attr)
}

titlebar_accessory_set_hidden :: proc "c" (vc: ^Titlebar_Accessory_View_Controller, hidden: NS.BOOL) {
	send(nil, vc, "setHidden:", hidden)
}

// The window retains the controller.
window_add_titlebar_accessory :: proc "c" (w: ^NS.Window, vc: ^Titlebar_Accessory_View_Controller) {
	send(nil, w, "addTitlebarAccessoryViewController:", vc)
}

// Removes `vc` from the window's titlebarAccessoryViewControllers, releasing it.
window_remove_titlebar_accessory :: proc "c" (w: ^NS.Window, vc: ^Titlebar_Accessory_View_Controller) {
	all := send(^NS.Array, w, "titlebarAccessoryViewControllers")
	index := send(NS.UInteger, all, "indexOfObject:", vc)
	if index == NS.UInteger(NS.NotFound) do return
	send(nil, w, "removeTitlebarAccessoryViewControllerAtIndex:", NS.Integer(index))
}

font_system :: proc "c" (size: NS.Float) -> ^NS_Font {
	return send(^NS_Font, NS_Font, "systemFontOfSize:", size)
}

font_bold_system :: proc "c" (size: NS.Float) -> ^NS_Font {
	return send(^NS_Font, NS_Font, "boldSystemFontOfSize:", size)
}

color_secondary_label :: proc "c" () -> ^NS.Color {
	return send(^NS.Color, NS.Color, "secondaryLabelColor")
}

}
