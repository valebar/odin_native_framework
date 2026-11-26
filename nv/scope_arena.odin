#+build !js
package nv

// A scope's arena (see Scope): growing, in address space reserved up front; or, once the app set
// its allocator (set_allocator), in blocks from that, as on the web.

import "base:runtime"
import "core:mem"
import "core:mem/virtual"

@(private) Scope_Arena :: struct {
	reserved:  virtual.Arena,
	blocks:    runtime.Arena, // with the app's allocator
	in_blocks: bool,
}

@(private) SCOPE_BLOCK :: 16 * 1024 - 48 // with runtime.Arena's block header, 16 KiB

@(private)
scope_arena_init :: proc(a: ^Scope_Arena) {
	if g_heap.procedure != nil {
		a.in_blocks = true
		a.blocks = {backing_allocator = g_heap, minimum_block_size = SCOPE_BLOCK}
		return
	}
	if err := virtual.arena_init_growing(&a.reserved); err != nil do panic("nv: arena reservation failed")
}

@(private)
scope_arena_allocator :: proc(a: ^Scope_Arena) -> mem.Allocator {
	return a.in_blocks ? runtime.arena_allocator(&a.blocks) : virtual.arena_allocator(&a.reserved)
}

@(private)
scope_arena_destroy :: proc(a: ^Scope_Arena) {
	if a.in_blocks do runtime.arena_destroy(&a.blocks)
	else do virtual.arena_destroy(&a.reserved)
}
