#+build !js
package nv

// A scope's arena (see Scope): growing, in address space reserved up front.

import "core:mem"
import "core:mem/virtual"

@(private) Scope_Arena :: virtual.Arena

@(private)
scope_arena_init :: proc(a: ^Scope_Arena) {
	if err := virtual.arena_init_growing(a); err != nil do panic("nv: arena reservation failed")
}

@(private)
scope_arena_allocator :: proc(a: ^Scope_Arena) -> mem.Allocator {
	return virtual.arena_allocator(a)
}

@(private)
scope_arena_destroy :: proc(a: ^Scope_Arena) {
	virtual.arena_destroy(a)
}
