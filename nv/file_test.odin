#+build-project-name nv
#+build !js
package nv

import "core:fmt"
import "core:testing"

Mock_Files :: struct {
	log: [dynamic]string,
}

mock_files_open :: proc(f: ^Mock_Files) {
	file_open({extensions = {"json"}, user = f, on_done = proc(user: rawptr, status: File_Status, name: string, data: []u8) {
		f := (^Mock_Files)(user)
		append(&f.log, fmt.aprintf("open %v %s %s depth %d", status, name, string(data), g_callback_depth, allocator = mock_allocator()))
	}})
}

mock_files_page :: proc(f: ^Mock_Files) -> Page {
	return {title = "F", user = f, build = proc(user: rawptr, _: ^Page_Handle) -> View { return view(label_create({text = "f"})) },
		on_pop = proc(user: rawptr) { append(&(^Mock_Files)(user).log, "on_pop") }}
}

// The bytes arrive inside a callback bracket, with the chosen name only (no directory).
@(test)
test_file_open_delivers_bytes :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	f: Mock_Files
	defer delete(f.log)
	run(mock_files_page(&f))
	mock_log_clear()
	mock_files_open(&f)
	expect_log(t, "file_open json")
	testing.expect_value(t, len(f.log), 0)
	mock_file_finish(0, .Ok, "/tmp/dir/config.json", transmute([]u8)string("{}"))
	testing.expect_value(t, len(f.log), 1)
	testing.expect_value(t, f.log[0], "open Ok config.json {} depth 1")
	testing.expect(t, g_file_request == nil)
}

// The data is copied at the call: the app may change or free its slice right after.
@(test)
test_file_save_copies_data :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	f: Mock_Files
	defer delete(f.log)
	run(mock_files_page(&f))
	mock_log_clear()
	data := []u8{'a', 'b', 'c'}
	saved: string
	file_save({suggested_name = "dev.json", extensions = {"json"}, data = data, user = &saved, on_done = proc(user: rawptr, status: File_Status, name: string) {
		(^string)(user)^ = fmt.aprintf("%v %s", status, name, allocator = mock_allocator())
	}})
	data[0] = 'x'
	expect_log(t, "file_save dev.json 3")
	testing.expect_value(t, string(mock.files[0].data), "abc")
	mock_file_finish(0, .Ok, "chosen.json")
	testing.expect_value(t, saved, "Ok chosen.json")
}

// A second dialog cancels the first at once; the first's late answer reaches nobody.
@(test)
test_file_new_request_cancels_old :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	f: Mock_Files
	defer delete(f.log)
	run(mock_files_page(&f))
	mock_files_open(&f)
	mock_files_open(&f)
	testing.expect_value(t, len(f.log), 1)
	testing.expect_value(t, f.log[0], "open Cancelled   depth 1")
	mock_file_finish(0, .Ok, "late.json", transmute([]u8)string("x"))
	testing.expect_value(t, len(f.log), 1)
	mock_file_finish(1, .Failed)
	testing.expect_value(t, f.log[1], "open Failed   depth 1")
}

// A dialog of a page that pops is cancelled before the page's on_pop.
@(test)
test_file_page_pop_cancels_before_on_pop :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	f: Mock_Files
	defer delete(f.log)
	run({title = "Root", build = proc(user: rawptr, _: ^Page_Handle) -> View { return view(label_create({text = "root"})) }})
	push(mock_files_page(&f))
	mock_files_open(&f)
	pop()
	testing.expect_value(t, len(f.log), 2)
	testing.expect_value(t, f.log[0], "open Cancelled   depth 1")
	testing.expect_value(t, f.log[1], "on_pop")
	mock_file_finish(0, .Ok, "late.json")
	testing.expect_value(t, len(f.log), 2)
}
