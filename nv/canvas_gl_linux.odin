#+build linux:default
#+private
package nv

// Linux GPU canvas (Canvas.gpu): a GtkGLArea drawn with OpenGL through nanovg (vendor:nanovg, its
// GL3 backend), so a canvas that repaints often (a live chart) costs the GPU instead of a cairo
// raster of the whole widget per frame. The Painter calls map one to one onto nanovg paths;
// text uses fontstash with the bytes of the loaded fonts (font_linux.odin keeps them), and
// without a font the face fontconfig matches for sans-serif. A canvas that takes no pointer or
// wheel is not a pointer target, so an overlaid chart lets the page under it scroll and tap.
// Every GL area has its own context: its nanovg context is made at realize and goes at
// unrealize, with the fonts and images it uploaded.

import "core:encoding/endian"
import "core:math"
import "core:os"
import "core:strings"

import gl "vendor:OpenGL"
import egl "vendor:egl"
import nvg "vendor:nanovg"
import nvgl "vendor:nanovg/gl"

foreign import gtk_gl "system:gtk-4"
foreign import fc_gl "system:fontconfig"

GDK_GL_API_GL :: 1

@(default_calling_convention = "c")
foreign gtk_gl {
	gtk_gl_area_new                  :: proc() -> ^GtkWidget ---
	gtk_gl_area_set_allowed_apis     :: proc(area: ^GtkWidget, apis: u32) ---
	gtk_gl_area_set_required_version :: proc(area: ^GtkWidget, major, minor: i32) ---
	gtk_gl_area_set_has_stencil_buffer :: proc(area: ^GtkWidget, has: gboolean) ---
	gtk_gl_area_make_current         :: proc(area: ^GtkWidget) ---
	gtk_gl_area_get_error            :: proc(area: ^GtkWidget) -> rawptr ---
	gtk_widget_set_can_target        :: proc(widget: ^GtkWidget, can_target: gboolean) ---
}

Fc_Pattern :: struct {}

@(default_calling_convention = "c")
foreign fc_gl {
	FcNameParse          :: proc(name: cstring) -> ^Fc_Pattern ---
	FcConfigSubstitute   :: proc(config: ^FcConfig, p: ^Fc_Pattern, kind: i32) -> i32 ---
	FcDefaultSubstitute  :: proc(p: ^Fc_Pattern) ---
	FcFontMatch          :: proc(config: ^FcConfig, p: ^Fc_Pattern, result: ^i32) -> ^Fc_Pattern ---
	FcPatternGetString   :: proc(p: ^Fc_Pattern, object: cstring, n: i32, s: ^cstring) -> i32 ---
	FcPatternDestroy     :: proc(p: ^Fc_Pattern) ---
}

// Per-canvas GL state (Canvas_Handle.extra for a gpu canvas); Painter.native points at it.
Gl_Canvas :: struct {
	using base: Linux_Canvas,
	vg:         ^nvg.Context,
	fonts:      map[^Font]int,  // the context's fontstash ids of loaded fonts
	sys_fonts:  map[string]int, // and of fontconfig's faces, by "sans-serif:bold:italic"
	images:     map[rawptr]int, // the context's images of the bitmaps drawn (by their cairo surface)
	em:         map[int]f32,    // per fontstash id: its line height per em (fontstash sizes by line height)
	gen:        int,            // draws; an image not drawn in the last one is deleted
	image_gen:  map[rawptr]int,
}

@(private = "file") g_gl_loaded: bool

// The loaded fonts (font_linux.odin keeps their bytes in Font.extra), for the bold / italic face
// of a family that cairo's toy API would select by name.
g_gl_font_list: [dynamic]^Font

gl_canvas_init :: proc(h: ^Canvas_Handle) {
	area := gtk_gl_area_new()
	gtk_widget_set_hexpand(area, true)
	gtk_widget_set_vexpand(area, true)
	gtk_gl_area_set_allowed_apis(area, GDK_GL_API_GL)
	gtk_gl_area_set_required_version(area, 3, 2)
	gtk_gl_area_set_has_stencil_buffer(area, true)
	g_signal_connect(area, "realize", rawptr(on_gl_realize), h)
	g_signal_connect(area, "unrealize", rawptr(on_gl_unrealize), h)
	g_signal_connect(area, "render", rawptr(on_gl_render), h)
	if h.canvas.on_pointer == nil && h.canvas.on_scroll == nil {
		gtk_widget_set_can_target(area, false)
	} else {
		canvas_add_controllers(h, area)
	}
	g_object_ref_sink(area)
	h.extra = scope_new_in(Gl_Canvas)
	scope_on_dispose(gl_canvas_dispose, h)
	h.root = View(area)
	h.view = area
}

gl_canvas_dispose :: proc(data: rawptr) {
	h := (^Canvas_Handle)(data)
	c := (^Gl_Canvas)(h.extra)
	if c.tick != 0 do gtk_widget_remove_tick_callback((^GtkWidget)(h.view), c.tick)
	g_object_unref(h.view) // an area still realized unrealizes as it goes (gl_release)
}

@(private = "file")
on_gl_realize :: proc "c" (area: ^GtkWidget, user: gpointer) {
	h := (^Canvas_Handle)(user)
	context = h.ctx
	c := (^Gl_Canvas)(h.extra)
	gtk_gl_area_make_current(area)
	if gtk_gl_area_get_error(area) != nil do return
	if !g_gl_loaded {
		gl.load_up_to(3, 3, egl.gl_set_proc_address)
		g_gl_loaded = true
	}
	c.vg = nvgl.Create({.ANTI_ALIAS, .STENCIL_STROKES})
}

@(private = "file")
on_gl_unrealize :: proc "c" (area: ^GtkWidget, user: gpointer) {
	h := (^Canvas_Handle)(user)
	context = h.ctx
	gtk_gl_area_make_current(area)
	gl_release((^Gl_Canvas)(h.extra))
}

@(private = "file")
gl_release :: proc(c: ^Gl_Canvas) {
	if c.vg != nil {
		for _, id in c.images do nvg.DeleteImage(c.vg, id)
		nvgl.Destroy(c.vg)
		c.vg = nil
	}
	delete(c.fonts)
	for k in c.sys_fonts do delete(k)
	delete(c.sys_fonts)
	delete(c.images)
	delete(c.image_gen)
	delete(c.em)
	c.fonts, c.sys_fonts, c.images, c.image_gen, c.em = {}, {}, {}, {}, {}
}

@(private = "file")
on_gl_render :: proc "c" (area: ^GtkWidget, _: rawptr, user: gpointer) -> gboolean {
	h := (^Canvas_Handle)(user)
	context = h.ctx
	c := (^Gl_Canvas)(h.extra)
	gl.ClearColor(0, 0, 0, 0)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)
	if c.vg == nil do return true
	vp: [4]i32
	gl.GetIntegerv(gl.VIEWPORT, &vp[0])
	w, ht := gtk_widget_get_width(area), gtk_widget_get_height(area)
	if w <= 0 || ht <= 0 do return true
	nvg.BeginFrame(c.vg, f32(w), f32(ht), f32(vp[2]) / f32(w))
	c.drawing = true
	c.gen += 1
	canvas_draw_notify(h, c, f64(w), f64(ht))
	c.drawing = false
	nvg.EndFrame(c.vg)
	// Images not drawn this time go.
	for key, g in c.image_gen do if g != c.gen {
		nvg.DeleteImage(c.vg, c.images[key])
		delete_key(&c.images, key)
		delete_key(&c.image_gen, key)
	}
	return true
}

// ---- the Painter on nanovg (canvas_linux.odin's _ops come here for a gpu canvas) ----

gl_of :: #force_inline proc "contextless" (p: ^Painter) -> ^nvg.Context {
	return p.h.canvas.gpu ? (^Gl_Canvas)(p.native).vg : nil
}

gl_fill_rect :: proc(vg: ^nvg.Context, x, y, w, h: f64, color: Color) {
	nvg.BeginPath(vg)
	nvg.Rect(vg, f32(x), f32(y), f32(w), f32(h))
	nvg.FillColor(vg, color)
	nvg.Fill(vg)
}

nvg_fill :: proc(vg: ^nvg.Context, color: Color) {
	nvg.FillColor(vg, color)
	nvg.Fill(vg)
}

gl_stroke :: proc(vg: ^nvg.Context, color: Color, width: f64, cap: nvg.LineCapType = .BUTT, join: nvg.LineCapType = .MITER) {
	nvg.StrokeColor(vg, color)
	nvg.StrokeWidth(vg, f32(width))
	nvg.LineCap(vg, cap)
	nvg.LineJoin(vg, join)
	nvg.Stroke(vg)
}

gl_stroke_rect :: proc(vg: ^nvg.Context, x, y, w, h: f64, color: Color, width: f64) {
	nvg.BeginPath(vg)
	nvg.Rect(vg, f32(x), f32(y), f32(w), f32(h))
	gl_stroke(vg, color, width)
}

gl_draw_line :: proc(vg: ^nvg.Context, x0, y0, x1, y1: f64, color: Color, width: f64) {
	nvg.BeginPath(vg)
	nvg.MoveTo(vg, f32(x0), f32(y0))
	nvg.LineTo(vg, f32(x1), f32(y1))
	gl_stroke(vg, color, width, .ROUND)
}

gl_ellipse :: proc(vg: ^nvg.Context, x, y, w, h: f64) {
	nvg.BeginPath(vg)
	nvg.Ellipse(vg, f32(x + w / 2), f32(y + h / 2), f32(w / 2), f32(h / 2))
}

gl_stroke_arc :: proc(vg: ^nvg.Context, cx, cy, radius, start, sweep: f64, color: Color, width: f64) {
	a0 := start * math.PI / 180
	a1 := a0 + sweep * math.PI / 180
	nvg.BeginPath(vg)
	nvg.Arc(vg, f32(cx), f32(cy), f32(radius), f32(a0), f32(a1), sweep >= 0 ? .CW : .CCW)
	gl_stroke(vg, color, width)
}

gl_stroke_polyline :: proc(vg: ^nvg.Context, points: [][2]f64, color: Color, width: f64) {
	nvg.BeginPath(vg)
	nvg.MoveTo(vg, f32(points[0].x), f32(points[0].y))
	for pt in points[1:] do nvg.LineTo(vg, f32(pt.x), f32(pt.y))
	gl_stroke(vg, color, width, .BUTT, .ROUND)
}

// nanovg makes a single path's winding solid whichever way the points go.
gl_fill_polygon :: proc(vg: ^nvg.Context, points: [][2]f64, color: Color) {
	nvg.BeginPath(vg)
	nvg.MoveTo(vg, f32(points[0].x), f32(points[0].y))
	for pt in points[1:] do nvg.LineTo(vg, f32(pt.x), f32(pt.y))
	nvg.ClosePath(vg)
	nvg_fill(vg, color)
}

gl_clip_push :: proc(vg: ^nvg.Context, x, y, w, h: f64) {
	nvg.Save(vg)
	nvg.IntersectScissor(vg, f32(x), f32(y), f32(w), f32(h))
}

gl_clip_pop :: proc(vg: ^nvg.Context) {
	nvg.Restore(vg)
}

// Selects the style's face and size; false when there is none (the text is then not drawn).
@(private = "file")
gl_font :: proc(c: ^Gl_Canvas, style: Text_Style) -> bool {
	vg := c.vg
	bold, italic := style.weight >= .Semibold, style.italic
	id := -1
	if f := style.font; f != nil {
		italic ||= f.italic
		if style.weight == .Default do bold = f.weight >= 600
		// cairo selects the family's bold / italic face by name: so does this, among the loaded fonts.
		face := f
		if (f.weight >= 600) != bold || f.italic != italic {
			for o in g_gl_font_list do if o.family == f.family && (o.weight >= 600) == bold && o.italic == italic {
				face = o
				break
			}
		}
		id = gl_font_id(c, face)
	} else {
		id = gl_sys_font(c, bold, italic)
	}
	if id < 0 do return false
	nvg.FontFaceId(vg, id)
	// cairo's size is the em; fontstash's is ascent - descent (stbtt_ScaleForPixelHeight).
	nvg.FontSize(vg, f32(style.size) * c.em[id])
	nvg.TextAlign(vg, .LEFT, .BASELINE)
	return true
}

@(private = "file")
gl_font_id :: proc(c: ^Gl_Canvas, f: ^Font) -> int {
	if id, ok := c.fonts[f]; ok do return id
	bytes := (^[]u8)(f.extra)
	id := -1
	if bytes != nil {
		name := strings.concatenate({f.family, f.italic ? ":i" : "", f.weight >= 600 ? ":b" : ""}, context.temp_allocator)
		id = nvg.CreateFontMem(c.vg, name, bytes^, false)
		if id >= 0 do c.em[id] = font_em_factor(bytes^)
	}
	c.fonts[f] = id
	return id
}

// fontconfig's sans-serif face for the weight and slant, by file.
@(private = "file")
gl_sys_font :: proc(c: ^Gl_Canvas, bold, italic: bool) -> int {
	key := strings.concatenate({"sans-serif", bold ? ":bold" : "", italic ? ":italic" : ""}, context.temp_allocator)
	if id, ok := c.sys_fonts[key]; ok do return id
	id := -1
	pat := FcNameParse(strings.clone_to_cstring(key, context.temp_allocator))
	if pat != nil {
		FcConfigSubstitute(nil, pat, 0) // FcMatchPattern
		FcDefaultSubstitute(pat)
		res: i32
		if m := FcFontMatch(nil, pat, &res); m != nil {
			file: cstring
			if FcPatternGetString(m, "file", 0, &file) == 0 {
				id = nvg.CreateFont(c.vg, key, string(file))
				if data, err := os.read_entire_file(string(file), context.temp_allocator); id >= 0 && err == nil {
					c.em[id] = font_em_factor(data)
				}
			}
			FcPatternDestroy(m)
		}
		FcPatternDestroy(pat)
	}
	c.sys_fonts[strings.clone(key)] = id
	return id
}

gl_draw_text :: proc(p: ^Painter, text: string, x, y: f64, style: Text_Style) {
	c := (^Gl_Canvas)(p.native)
	if !gl_font(c, style) do return
	asc, _, _ := nvg.TextMetrics(c.vg)
	nvg.FillColor(c.vg, style.color)
	nvg.Text(c.vg, f32(x), f32(y) + asc, text)
}

gl_draw_text_rotated :: proc(p: ^Painter, text: string, x, y, angle: f64, style: Text_Style) {
	c := (^Gl_Canvas)(p.native)
	nvg.Save(c.vg)
	nvg.Translate(c.vg, f32(x), f32(y))
	nvg.Rotate(c.vg, f32(angle))
	gl_draw_text(p, text, 0, 0, style)
	nvg.Restore(c.vg)
}

gl_measure_text :: proc(p: ^Painter, text: string, style: Text_Style) -> (width, height: f64) {
	c := (^Gl_Canvas)(p.native)
	if !gl_font(c, style) do return 0, 0
	asc, desc, _ := nvg.TextMetrics(c.vg)
	return f64(nvg.TextBounds(c.vg, 0, 0, text)), f64(asc - desc)
}

// A bitmap is uploaded once per draw it is in (a video frame changes in place), as RGBA from the
// cairo surface's premultiplied BGRA.
gl_draw_image :: proc(p: ^Painter, b: ^Bitmap, x, y, w, h: f64) {
	c := (^Gl_Canvas)(p.native)
	surf := (^cairo_surface_t)(b.native)
	if surf == nil do return
	cairo_surface_flush(surf)
	stride := int(cairo_image_surface_get_stride(surf))
	src := cairo_image_surface_get_data(surf)
	if src == nil do return
	px := make([]u8, b.width * b.height * 4, context.temp_allocator)
	for row in 0 ..< b.height {
		for col in 0 ..< b.width {
			s := src[row * stride + col * 4:]
			d := px[(row * b.width + col) * 4:]
			d[0], d[1], d[2], d[3] = s[2], s[1], s[0], s[3]
		}
	}
	id, ok := c.images[surf]
	if ok && c.image_gen[surf] == c.gen {
		// drawn twice in one frame: the upload is there already
	} else if ok {
		nvg.UpdateImage(c.vg, id, px)
	} else {
		id = nvg.CreateImageRGBA(c.vg, b.width, b.height, {.PREMULTIPLIED}, px)
		c.images[surf] = id
	}
	c.image_gen[surf] = c.gen
	paint := nvg.ImagePattern(f32(x), f32(y), f32(w), f32(h), 0, id, 1)
	nvg.BeginPath(c.vg)
	nvg.Rect(c.vg, f32(x), f32(y), f32(w), f32(h))
	nvg.FillPaint(c.vg, paint)
	nvg.Fill(c.vg)
}

// (hhea ascender - descender) / head unitsPerEm of a TrueType / OpenType font (the first face of
// a collection); 1.2 when the tables can't be read.
@(private = "file")
font_em_factor :: proc(data: []u8) -> f32 {
	u16be :: proc(b: []u8, at: int) -> (int, bool) {
		v, ok := endian.get_u16(b[at:] if at < len(b) else nil, .Big)
		return int(v), ok
	}
	u32be :: proc(b: []u8, at: int) -> (int, bool) {
		v, ok := endian.get_u32(b[at:] if at < len(b) else nil, .Big)
		return int(v), ok
	}
	base := 0
	if len(data) >= 16 && string(data[:4]) == "ttcf" {
		first, ok := u32be(data, 12)
		if !ok do return 1.2
		base = first
	}
	n, ok := u16be(data, base + 4)
	if !ok do return 1.2
	upem, asc, desc := 0, 0, 0
	for i in 0 ..< n {
		rec := base + 12 + i * 16
		if rec + 16 > len(data) do break
		tag := string(data[rec:][:4])
		off, _ := u32be(data, rec + 8)
		switch tag {
		case "head":
			upem, _ = u16be(data, off + 18)
		case "hhea":
			a, _ := u16be(data, off + 4)
			d, _ := u16be(data, off + 6)
			asc, desc = int(i16(a)), int(i16(d))
		}
	}
	if upem <= 0 || asc - desc <= 0 do return 1.2
	return f32(asc - desc) / f32(upem)
}
