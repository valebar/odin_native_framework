package nv

import "base:intrinsics"
import "base:runtime"
import "core:mem"

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
//
// A scope is detached as its page leaves the stack (before on_pop) or its dialog closes (before
// on_close): the app may then free what its widgets' callbacks reach, while the platform still
// shows the views (GTK's and iOS's slide, a queued layout). From then on the core delivers none of
// their callbacks (scope_live): no taps, edits, draws, list rows or tab switches.
@(private) Scope :: struct {
	arena:     Scope_Arena, // scope_arena.odin / scope_arena_web.odin
	disposers: ^Disposer, // most recent first: disposers run in reverse order, like `defer`
	detached:  bool,
}

// Whether the widgets of `s` may still call the app.
@(private)
scope_live :: proc "contextless" (s: ^Scope) -> bool {
	return s == nil || !s.detached
}

@(private) Disposer :: struct {
	next: ^Disposer,
	fn:   proc(data: rawptr),
	data: rawptr,
}

// The allocator the core keeps what outlives a callback in (handles' strings, downloads, timers,
// the scopes themselves), whatever the app's context.allocator is: the app's (set_allocator), else
// the heap, or on the web, where base:runtime has no heap_alloc, the wasm allocator.
@(private)
nv_heap :: proc() -> runtime.Allocator {
	if g_heap.procedure != nil do return g_heap
	when ODIN_OS == .JS do return runtime.default_wasm_allocator()
	else do return runtime.heap_allocator()
}

@(private) g_heap: runtime.Allocator

// Makes nv take all of its own memory from `allocator` instead of the heap: what outlives a
// callback (nv_heap), the blocks of the pages' and dialogs' arenas, downloads, timers. Call it
// before `run` and before loading fonts or bitmaps. Download threads and post_main allocate from
// other threads, so it must be thread-safe; nv frees into it as before, so an arena that ignores
// frees will do.
set_allocator :: proc(allocator: runtime.Allocator) {
	assert(len(g_nav) == 0, "nv.set_allocator before nv.run")
	g_heap = allocator
}

// Set while `dialog_present` builds a dialog's body, which belongs to the dialog, not the page.
@(private) g_scope_override: ^Scope

// Retired inside a callback; destroyed by the outermost `callback_exit`.
@(private) g_scopes_retired: [dynamic]^Scope

@(private)
scope_new :: proc() -> ^Scope {
	s := new(Scope, nv_heap()) // not the app's allocator: any context may destroy it
	scope_arena_init(&s.arena)
	return s
}

@(private)
scope_allocator :: proc(s: ^Scope) -> mem.Allocator {
	return scope_arena_allocator(&s.arena)
}

@(private)
scope_current :: proc() -> ^Scope {
	if g_scope_override != nil do return g_scope_override
	assert(len(g_nav) > 0, "nv: widgets are created from inside nv.run")
	return g_nav[len(g_nav) - 1].scope
}

// Allocates a T in the current scope (and records the scope in a handle with a `scope` field).
@(private)
scope_new_in :: proc($T: typeid) -> ^T {
	s := scope_current()
	h := new(T, scope_allocator(s))
	when intrinsics.type_has_field(T, "scope") do h.scope = s
	return h
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
		if g_scopes_retired.allocator.procedure == nil do g_scopes_retired.allocator = nv_heap()
		append(&g_scopes_retired, s)
	} else {
		scope_destroy(s)
	}
}

@(private)
scope_destroy :: proc(s: ^Scope) {
	for d := s.disposers; d != nil; d = d.next do d.fn(d.data)
	s.disposers = nil
	scope_arena_destroy(&s.arena)
	free(s, nv_heap())
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
