#+build windows, linux:default
#+private
package nv

// Image downloads on Windows and Linux (Android's libc can't host core:thread, so NvFetch.java
// runs its downloads; Apple uses a raw pthread, fetch_darwin.odin): a worker thread per download
// runs the blocking `_http_get` and hands the result to the UI thread with `_post_main`, which
// calls fetch_notify from the event loop. Assets are files next to the executable.

import "base:runtime"
import "core:thread"

@(private)
_asset_read :: proc(path: string, allocator := context.allocator) -> []u8 {
	return asset_read_file(path, allocator)
}

@(private)
_fetch_start :: proc(f: ^Fetch) {
	thread.create_and_start_with_data(f, fetch_worker, runtime.default_context(), self_cleanup = true)
}

// Only `url` and `data` are touched here; `_http_get` allocates `data` on the heap.
@(private)
fetch_worker :: proc(data: rawptr) {
	f := (^Fetch)(data)
	f.data = _http_get(f.url)
	_post_main(f)
}
