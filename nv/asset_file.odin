#+build !js
#+private
package nv

// The file system side of the assets, for every backend that has one (not the web, whose assets
// nv.js fetched up front; core:os does not build for js).

import "core:os"

// Reads a file for bitmap_from_file / font_from_file; a relative path resolves against the
// `assets` directory next to the executable (inside the .app on iOS). Android overrides this with
// the APK's assets.
@(private)
asset_read_file :: proc(path: string, allocator := context.allocator) -> []u8 {
	full := path
	if !os.is_absolute_path(path) {
		dir, err := os.get_executable_directory(context.temp_allocator)
		if err != nil do return nil
		full, _ = os.join_path({dir, "assets", path}, context.temp_allocator)
	}
	data, err := os.read_entire_file(full, allocator)
	if err != nil do return nil
	return data
}
