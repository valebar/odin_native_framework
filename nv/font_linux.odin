#+build linux:default
#+private
package nv

// Linux font backend. Fontconfig only takes fonts from files, so the bytes go to a temp file
// (created exclusively under a random name, so a planted file can't be overwritten) that
// FcConfigAppFontAddFile adds to the current config as an application font; Pango's default
// font map is then told the config changed (what GTK does when the system fonts change), so
// widgets created afterwards resolve the family (CSS font-family in the style's class,
// theme_linux.odin), and cairo-ft finds it for the canvas. Nothing
// unregisters a single application font and FreeType opens the file lazily, so the file stays
// for the life of the process: _font_free leaves it behind. A fontconfig reload triggered by a
// system font change drops application fonts.

import "core:os"
import "core:strings"

@(private)
_font_load :: proc(f: ^Font, data: []u8) -> bool {
	file, err := os.create_temp_file("", "nv-font-*.ttf")
	if err != nil do return false
	path := strings.clone(os.name(file), context.temp_allocator) // the name lives as long as the handle
	_, werr := os.write(file, data)
	os.close(file)
	if werr != nil || FcConfigAppFontAddFile(FcConfigGetCurrent(), strings.clone_to_cstring(path, context.temp_allocator)) == 0 {
		os.remove(path)
		return false
	}
	pango_fc_font_map_config_changed(pango_cairo_font_map_get_default())
	// The bytes stay for a gpu canvas's fontstash (canvas_gl_linux.odin).
	bytes := new([]u8)
	bytes^ = make([]u8, len(data))
	copy(bytes^, data)
	f.extra = bytes
	append(&g_gl_font_list, f)
	return true
}

@(private)
_font_free :: proc(f: ^Font) {
	for o, i in g_gl_font_list do if o == f {
		unordered_remove(&g_gl_font_list, i)
		break
	}
	if bytes := (^[]u8)(f.extra); bytes != nil {
		delete(bytes^)
		free(bytes)
		f.extra = nil
	}
}
