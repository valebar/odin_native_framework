#+build js
#+private
package nv

// Web Layout backend: a div.nv-layout the child fills (nv.css), watched by nv.js's layoutObserver,
// which reports its size through nv_web_layout after layout and before paint.

@(private)
_layout_init :: proc(h: ^Layout_Handle) {
	root := js_layout_create(h)
	scope_on_dispose(web_release, rawptr(uintptr(root)))
	js_append(root, web_id(h.layout.child))
	h.root = web_view(root)
}
