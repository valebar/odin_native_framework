#+build js
package nv

// Web theme backend. The palette is a set of CSS custom properties on :root (--nv-bg, --nv-text,
// .., nv.css) and `color-scheme`, which the browser's own controls and scroll bars follow; System
// reads `prefers-color-scheme`, whose changes nv.js reports (nv_web_event .Theme). The accent is
// the CSS AccentColor where the browser has it.

@(private)
_theme_system_dark :: proc() -> bool {
	return bool(js_system_dark())
}

@(private)
_theme_system_accent :: proc() -> Color {
	a := js_system_accent()
	if a == 0 do return {}
	f :: proc "contextless" (v: u32) -> f32 { return f32(v & 0xff) / 255 }
	return {f(a >> 16), f(a >> 8), f(a), f(a >> 24)}
}

// The palette for `dark` (theme_palette, before g_dark follows: theme_set_mode applies first).
@(private)
_theme_apply_mode :: proc() {
	web_theme_vars(theme_resolve_dark())
}

@(private)
_theme_recolor :: proc() {
	web_theme_vars(g_dark)
}

@(private)
web_theme_vars :: proc(dark: bool) {
	p := dark ? PALETTE_DARK : PALETTE_LIGHT
	if g_theme.accent.a > 0 {
		p.accent = g_theme.accent
	} else if a := _theme_system_accent(); a.a > 0 {
		p.accent = a
	}
	js_root_style("--nv-bg", web_color(p.background))
	js_root_style("--nv-surface", web_color(p.surface))
	js_root_style("--nv-text", web_color(p.text))
	js_root_style("--nv-text2", web_color(p.secondary_text))
	js_root_style("--nv-sep", web_color(p.separator))
	js_root_style("--nv-accent", web_color(p.accent))
	js_color_scheme(b32(dark))
}
