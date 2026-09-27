#+build linux:default
package nv

// Linux font backend. Fontconfig only takes fonts from files, so the bytes go to a temp file
// (created exclusively under a random name, so a planted file can't be overwritten) that
// FcConfigAppFontAddFile adds to the current config as an application font; Pango's default
// font map is then told the config changed (what GTK does when the system fonts change), so
// widgets created afterwards resolve the family, and cairo-ft finds it for the canvas. Nothing
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
	return true
}

@(private)
_font_free :: proc(f: ^Font) {
}

// The attributes for a widget's font and size: the family, weight and style when a font is set
// (the weight and style pin the loaded face when the family is installed too), the size in device
// units (the cairo unit, so it matches draw_text) when it isn't 0. nil when both are defaults.
@(private)
pango_font_attrs :: proc(font: ^Font, size: f64) -> ^PangoAttrList {
	if font == nil && size == 0 do return nil
	attrs := pango_attr_list_new()
	if font != nil {
		pango_attr_list_insert(attrs, pango_attr_family_new(strings.clone_to_cstring(font.family, context.temp_allocator)))
		pango_attr_list_insert(attrs, pango_attr_weight_new(i32(font.weight)))
		if font.italic do pango_attr_list_insert(attrs, pango_attr_style_new(PANGO_STYLE_ITALIC))
	}
	if size != 0 do pango_attr_list_insert(attrs, pango_attr_size_new_absolute(i32(size * PANGO_SCALE)))
	return attrs
}
