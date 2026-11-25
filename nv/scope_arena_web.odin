#+build js
package nv

// A scope's arena (see Scope) on the web: wasm has no virtual memory (core:mem/virtual's reserve
// does nothing there), so the arena grows from heap blocks; the first one comes with the first
// allocation.

import "base:runtime"
import "core:mem"

@(private) Scope_Arena :: runtime.Arena

@(private) SCOPE_BLOCK :: 16 * 1024

@(private)
scope_arena_init :: proc(a: ^Scope_Arena) {
	a^ = {backing_allocator = nv_heap(), minimum_block_size = SCOPE_BLOCK}
}

@(private)
scope_arena_allocator :: proc(a: ^Scope_Arena) -> mem.Allocator {
	return runtime.arena_allocator(a)
}

@(private)
scope_arena_destroy :: proc(a: ^Scope_Arena) {
	runtime.arena_destroy(a)
}
