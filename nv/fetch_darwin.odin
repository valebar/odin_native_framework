#+build darwin
#+private
package nv

// Image downloads on macOS / iOS: a detached raw pthread per download runs the blocking
// `_http_get` (cg.odin) and hands the result to the UI thread with `_post_main`, which calls
// fetch_notify from the main queue. Raw pthread rather than core:thread, whose Darwin file
// (thread_name_darwin.odin) links `System.framework`, which the iPhoneSimulator SDK lacks.
// Assets are files next to the executable (inside the .app on iOS).

import "base:runtime"
import "core:sys/posix"

@(private)
_asset_read :: proc(path: string, allocator := context.allocator) -> []u8 {
	return asset_read_file(path, allocator)
}

@(private)
_fetch_start :: proc(f: ^Fetch) {
	tid: posix.pthread_t
	if posix.pthread_create(&tid, nil, fetch_worker, f) != .NONE {
		_post_main(f) // no data: reported as a failed download
		return
	}
	posix.pthread_detach(tid)
}

// Only `url` and `data` are touched here; `_http_get` allocates `data` on the heap and uses no
// temp allocator, so the thread leaves nothing behind.
@(private)
fetch_worker :: proc "c" (arg: rawptr) -> rawptr {
	context = runtime.default_context()
	f := (^Fetch)(arg)
	f.data = _http_get(f.url)
	_post_main(f)
	return nil
}
