#+build linux:default
package nv

// Linux (GTK4) theme backend. The mode is the gtk-application-prefer-dark-theme setting. Plain
// GTK4 doesn't follow the desktop's light / dark preference by itself, so the System mode reads
// org.gnome.desktop.interface color-scheme from GSettings (when that schema is installed) and
// follows its "changed" signal. The widgets use the theme's colors and recolor themselves.
//
// Text styles and the accent are CSS on the one provider app_linux.odin loads: every distinct
// Text_Style becomes a class (.nv-s0, .nv-s1, ...) whose rule is added when first used (a loaded
// font is its family name, which fontconfig knows once _font_load added the file), and the
// accent colors the buttons, the entry focus and the list selection.

import "core:fmt"
import "core:strings"

// A style as a class key: the font by its family name (cloned; the Font may be freed first).
@(private) Style_Key :: struct {
	style:  Text_Style, // font nil
	family: string,
}

@(private) g_theme_linux: struct {
	css:       ^GtkCssProvider,
	styles:    map[Style_Key]int, // class index by style
	rules:     strings.Builder,    // the rules of those classes
	gsettings: gpointer,           // GSettings for org.gnome.desktop.interface; nil without the schema
}

@(private)
_theme_system_dark :: proc() -> bool {
	if g_theme_linux.gsettings == nil {
		src := g_settings_schema_source_get_default()
		schema := src != nil ? g_settings_schema_source_lookup(src, "org.gnome.desktop.interface", true) : nil
		if schema == nil do return false
		has_key := g_settings_schema_has_key(schema, "color-scheme")
		g_settings_schema_unref(schema)
		if !has_key do return false
		g_theme_linux.gsettings = g_settings_new("org.gnome.desktop.interface")
		g_signal_connect(g_theme_linux.gsettings, "changed::color-scheme", rawptr(on_color_scheme_changed), nil)
	}
	return g_settings_get_enum(g_theme_linux.gsettings, "color-scheme") == 1 // prefer-dark
}

@(private)
_theme_system_accent :: proc() -> Color {
	return {0x35 / 255.0, 0x84 / 255.0, 0xe4 / 255.0, 1} // Adwaita blue
}

@(private)
_theme_apply_mode :: proc() {
	dark := g_theme.mode == .Dark || (g_theme.mode == .System && _theme_system_dark())
	g_object_set(gtk_settings_get_default(), "gtk-application-prefer-dark-theme", gboolean(dark), nil)
}

@(private)
_theme_recolor :: proc() {}

@(private)
on_color_scheme_changed :: proc "c" (_: gpointer, _: cstring, _: gpointer) {
	context = g_linux.ctx
	if g_theme.mode != .System do return
	_theme_apply_mode()
	theme_notify()
}

// Adds the class for `s` to `w`; a style that sets nothing adds none. A loaded font's rule pins
// the face's weight and slant too, unless the style asks for others.
@(private)
style_widget :: proc(w: ^GtkWidget, s: Text_Style) {
	if s.font == nil && s.size <= 0 && s.weight == .Default && !s.italic && s.color.a == 0 do return
	key := Style_Key{s, s.font != nil ? s.font.family : ""}
	key.style.font = nil
	index, found := g_theme_linux.styles[key]
	if !found {
		index = len(g_theme_linux.styles)
		key.family = strings.clone(key.family)
		g_theme_linux.styles[key] = index
		b := &g_theme_linux.rules
		fmt.sbprintf(b, ".nv-s%d {{", index)
		if s.size > 0 do fmt.sbprintf(b, " font-size: %.2fpx;", s.size)
		weight, italic := s.weight, s.italic
		if f := s.font; f != nil {
			fmt.sbprintf(b, " font-family: \"%s\";", f.family)
			if weight == .Default do fmt.sbprintf(b, " font-weight: %d;", f.weight)
			italic ||= f.italic
		}
		switch weight {
		case .Default:
		case .Regular:  strings.write_string(b, " font-weight: 400;")
		case .Medium:   strings.write_string(b, " font-weight: 500;")
		case .Semibold: strings.write_string(b, " font-weight: 600;")
		case .Bold:     strings.write_string(b, " font-weight: 700;")
		}
		if italic do strings.write_string(b, " font-style: italic;")
		if s.color.a > 0 do fmt.sbprintf(b, " color: %s;", css_color(s.color))
		strings.write_string(b, " }\n")
		theme_css_reload()
	}
	gtk_widget_add_css_class(w, fmt.ctprintf("nv-s%d", index))
}

// NV_CSS (app_linux.odin), the accent and the style classes. The provider is replaced as a whole.
@(private)
theme_css_reload :: proc() {
	if g_theme_linux.css == nil do return
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	strings.write_string(&b, NV_CSS)
	if a := g_theme.accent; a.a > 0 {
		c := css_color(a)
		fmt.sbprintf(&b, "button.nv-accent {{ background-image: none; background-color: %s; color: white; }}\n", c)
		fmt.sbprintf(&b, "button.nv-accent:hover {{ background-color: mix(%s, white, 0.1); }}\n", c)
		fmt.sbprintf(&b, "button.nv-accent:active {{ background-color: shade(%s, 0.85); }}\n", c)
		fmt.sbprintf(&b, "entry:focus-within {{ outline-color: alpha(%s, 0.6); }}\n", c)
		fmt.sbprintf(&b, "listview > row:selected {{ background-color: alpha(%s, 0.25); }}\n", c)
		fmt.sbprintf(&b, "button.nv-fab {{ background-color: %s; }}\n", c)
		fmt.sbprintf(&b, "button.nv-fab:hover {{ background-color: mix(%s, white, 0.1); }}\n", c)
		fmt.sbprintf(&b, ".nv-tabbar button:checked {{ color: %s; }}\n", c)
	}
	strings.write_string(&b, strings.to_string(g_theme_linux.rules))
	gtk_css_provider_load_from_data(g_theme_linux.css, strings.to_cstring(&b), -1)
}

@(private)
css_color :: proc(c: Color) -> string {
	b :: proc(f: f32) -> int { return int(clamp(f, 0, 1) * 255 + 0.5) }
	return fmt.tprintf("rgba(%d, %d, %d, %.3f)", b(c.r), b(c.g), b(c.b), c.a)
}
