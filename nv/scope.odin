package nv

import "base:runtime"
import "core:mem"
import "core:mem/virtual"

// What a page (or a dialog's body) owns: an arena for the handles its widgets allocate, and the
// disposers that release what the handles hold outside it (native references, retained fonts and
// bitmaps, heap strings). Widgets belong to the scope that is current when they are created
// (`scope_current`): the top page's, which is the page being built during `build`, or a dialog's
// while its body is built.
//
// A scope dies after its native views: the backend calls `scope_retire` once the popped page's
// tree is really gone (after the slide on GTK and iOS, after DestroyWindow on Windows), and a
// retirement inside a callback waits until the outermost one returned, so a pop from a widget's own
// callback never frees the handle it is running on.
@(private) Scope :: struct {
	arena:     virtual.Arena,
	disposers: ^Disposer, // most recent first: disposers run in reverse order, like `defer`
}

@(private) Disposer :: struct {
	next: ^Disposer,
	fn:   proc(data: rawptr),
	data: rawptr,
}

// Set while `dialog_present` builds a dialog's body, which belongs to the dialog, not the page.
@(private) g_scope_override: ^Scope

// Retired inside a callback; destroyed by the outermost `callback_exit`.
@(private) g_scopes_retired: [dynamic]^Scope

@(private)
scope_new :: proc() -> ^Scope {
	s := new(Scope, runtime.heap_allocator()) // not the app's allocator: any context may destroy it
	if err := virtual.arena_init_growing(&s.arena); err != nil do panic("nv: arena reservation failed")
	return s
}

@(private)
scope_allocator :: proc(s: ^Scope) -> mem.Allocator {
	return virtual.arena_allocator(&s.arena)
}

@(private)
scope_current :: proc() -> ^Scope {
	if g_scope_override != nil do return g_scope_override
	assert(len(g_nav) > 0, "nv: widgets are created from inside nv.run")
	return g_nav[len(g_nav) - 1].scope
}

// Allocates a T in the current scope.
@(private)
scope_new_in :: proc($T: typeid) -> ^T {
	return new(T, scope_allocator(scope_current()))
}

// Runs `fn(data)` when the current scope dies.
@(private)
scope_on_dispose :: proc(fn: proc(data: rawptr), data: rawptr) {
	s := scope_current()
	d := new(Disposer, scope_allocator(s))
	d^ = {s.disposers, fn, data}
	s.disposers = d
}

// Called by the backends once the scope's native views are gone.
@(private)
scope_retire :: proc(s: ^Scope) {
	if s == nil do return
	if g_callback_depth > 0 {
		if g_scopes_retired.allocator.procedure == nil do g_scopes_retired.allocator = runtime.heap_allocator()
		append(&g_scopes_retired, s)
	} else {
		scope_destroy(s)
	}
}

@(private)
scope_destroy :: proc(s: ^Scope) {
	for d := s.disposers; d != nil; d = d.next do d.fn(d.data)
	s.disposers = nil
	virtual.arena_destroy(&s.arena)
	free(s, runtime.heap_allocator())
}

// Destroys the scopes retired while a callback was running; `callback_exit` calls it at depth 0.
// A disposer never calls back into the app, but it may retire more (nothing does today).
@(private)
scope_flush_retired :: proc() {
	for len(g_scopes_retired) > 0 {
		s := g_scopes_retired[0]
		ordered_remove(&g_scopes_retired, 0)
		scope_destroy(s)
	}
}
