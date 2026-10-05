#+build-project-name nv
package nv

// The core's widgets, bitmaps, fonts and theme against the mock backend (mock_test.odin), and its
// pure helpers. Fixture tests start with mock_begin(t) and end with mock_end(t), as in nav_test.

import "core:testing"

// TrueType, family Tuffy, OS/2 weight 700, not italic.
TUFFY_BOLD :: #load("../app/assets/tuffy_bold.ttf")

@(test)
test_text_is_copied :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root := Mock_Page{name = "Root"}
	mock_launch(&root)
	buf := [5]u8{'h', 'e', 'l', 'l', 'o'}
	callback_enter()
	l := label_create({text = string(buf[:])})
	b := button_create({title = string(buf[:])})
	buf[0] = 'j'
	testing.expect_value(t, l.label.text, "hello")
	testing.expect_value(t, b.button.title, "hello")
	label_set_text(l, string(buf[:]))
	button_set_title(b, string(buf[:]))
	buf[0] = 'y'
	testing.expect_value(t, l.label.text, "jello")
	testing.expect_value(t, b.button.title, "jello")
	callback_exit()
	expect_log(t, "label_init hello", "button_init hello", "label_set_text jello", "button_set_title jello")
}

// Win32, GTK and Android report a programmatic set as a change (the mock does too); the core keeps
// it from the app.
@(test)
test_input_set_text_is_silent :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	on_change :: proc(_: rawptr, text: string) {
		mock_log("on_change %s", text)
	}
	on_submit :: proc(_: rawptr, text: string) {
		mock_log("on_submit %s", text)
	}
	root := Mock_Page{name = "Root"}
	mock_launch(&root)
	callback_enter()
	f := input_create({text = "a", on_change = on_change, on_submit = on_submit})
	input_set_text(f, "abc")
	callback_exit()
	mock_type(f, "abcd")
	mock_type(f, "abcd", submit = true)
	text := input_text(f)
	testing.expect_value(t, text, "abcd")
	delete(text)
	expect_log(t, "input_init a", "input_set_text abc", "on_change abcd", "on_submit abcd")
}

@(test)
test_bitmap_reference_counts :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root := Mock_Page{name = "Root"}
	mock_launch(&root)
	testing.expect(t, bitmap_from_bytes(nil) == nil) // nothing to decode: the backend is never asked
	mock.decode_ok = false
	testing.expect(t, bitmap_from_bytes({40, 20}) == nil) // refused: the Bitmap must not leak
	mock.decode_ok = true

	callback_enter()
	bm := bitmap_from_bytes({40, 20})
	img := image_create({bitmap = bm})
	testing.expect_value(t, bm.refs, 2)
	bitmap_free(bm) // the app's reference; the image keeps the bitmap
	testing.expect_value(t, bm.refs, 1)
	testing.expect_value(t, image_natural_size(img), [2]f64{40, 20})
	image_set_bitmap(img, nil)
	callback_exit()
	expect_log(t, "bitmap_decode 40x20", "image_init", "image_set_bitmap false", "bitmap_free 40x20")
}

@(test)
test_font_reference_counts :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b := Mock_Page{name = "Root"}, Mock_Page{name = "B"}
	mock_launch(&root)
	testing.expect(t, font_from_bytes({1, 2, 3}) == nil) // not a font: the backend is never asked
	mock.font_ok = false
	testing.expect(t, font_from_bytes(TUFFY_BOLD) == nil) // refused: the family string must not leak
	mock.font_ok = true
	mock_log_clear()

	callback_enter()
	f := font_from_bytes(TUFFY_BOLD)
	testing.expect(t, f != nil && f.family == "Tuffy" && f.weight == 700 && !f.italic && f.refs == 1)
	push(mock_page(&b))
	l := label_create({text = "x", style = {font = f}})
	testing.expect(t, l.label.style.font == f && f.refs == 2)
	font_free(f) // the app's reference; the label keeps the font
	testing.expect_value(t, f.refs, 1)
	pop()
	callback_exit() // B's scope dies: the label drops the last reference
	expect_log(t, "font_load Tuffy", "build B", "label_init B", "nav_push B", "label_init x", "nav_pop B -> Root",
		"nav_release B", "on_pop B", "release label x", "font_free Tuffy", "release label B")
}

// A download that lost the race to image_set_bitmap is dropped, and so is one that lands after its
// image's page is gone.
@(test)
test_image_drops_stale_downloads :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	root, b := Mock_Page{name = "Root"}, Mock_Page{name = "B"}
	mock_launch(&root)
	callback_enter()
	img := image_create({url = "u"})
	b2 := bitmap_from_bytes({2, 2})
	image_set_bitmap(img, b2)
	bitmap_free(b2)
	callback_exit()
	mock_fetch_finish(0, {8, 8})
	testing.expect(t, img.bitmap == b2 && img.fetch == nil)

	callback_enter()
	push(mock_page(&b))
	image_create({url = "v"})
	pop()
	callback_exit()
	mock_fetch_finish(1, {4, 4})
	expect_log(t, "image_init", "fetch_start u", "bitmap_decode 2x2", "image_set_bitmap true", "bitmap_decode 8x8", "bitmap_free 8x8",
		"build B", "label_init B", "nav_push B", "image_init", "fetch_start v", "nav_pop B -> Root", "nav_release B", "on_pop B",
		"release image", "release label B", "bitmap_decode 4x4", "bitmap_free 4x4")
}

@(test)
test_theme_change_only_on_flip :: proc(t: ^testing.T) {
	mock_begin(t)
	defer mock_end(t)
	on_change :: proc(_: rawptr) {
		mock_log("on_change")
	}
	theme_set({mode = .System, on_change = on_change})
	testing.expect(t, !theme_dark())
	root := Mock_Page{name = "Root"}
	mock_launch(&root)

	mock.system_dark = true
	theme_notify()
	expect_log(t, "theme_recolor true", "on_change")
	theme_notify()
	expect_log(t)
	theme_set_mode(.Dark) // already dark: the platform is told, the app is not
	expect_log(t, "theme_apply_mode Dark")
	theme_set_mode(.Light)
	expect_log(t, "theme_apply_mode Light", "theme_recolor false", "on_change")
	testing.expect(t, theme_palette().background == PALETTE_LIGHT.background)
	mock.system_accent = {1, 0, 0, 1}
	testing.expect(t, theme_palette().accent == Color{1, 0, 0, 1})
}

@(test)
test_text_style_merge :: proc(t: ^testing.T) {
	f := Font{family = "F"}
	base := Text_Style{size = 15, weight = .Bold, color = {1, 0, 0, 1}, font = &f}
	testing.expect(t, text_style_merge({}, base) == base)
	m := text_style_merge({size = 20, weight = .Medium, italic = true, color = {0, 1, 0, 1}}, base)
	testing.expect(t, m.size == 20 && m.weight == .Medium && m.italic && m.color == Color{0, 1, 0, 1} && m.font == &f)
	testing.expect(t, text_style_merge({}, {italic = true}).italic)
	testing.expect(t, text_style_merge({color = {1, 1, 1, 0}}, base).color == base.color) // alpha 0 is unset
}

@(test)
test_text_weight :: proc(t: ^testing.T) {
	testing.expect_value(t, text_weight(.Default, true), Weight.Bold)
	testing.expect_value(t, text_weight(.Default, false), Weight.Regular)
	testing.expect_value(t, text_weight(.Medium, true), Weight.Medium)
}

@(test)
test_image_fit_rect :: proc(t: ^testing.T) {
	b := Bitmap{width = 200, height = 100}
	testing.expect_value(t, image_fit_rect(.Fill, &b, 100, 100), [4]f64{0, 0, 100, 100})
	testing.expect_value(t, image_fit_rect(.Contain, &b, 100, 100), [4]f64{0, 25, 100, 50})
	testing.expect_value(t, image_fit_rect(.Cover, &b, 100, 100), [4]f64{-50, 0, 200, 100})
	empty := Bitmap{}
	testing.expect_value(t, image_fit_rect(.Contain, &empty, 30, 40), [4]f64{0, 0, 30, 40})
}

@(test)
test_image_natural_size :: proc(t: ^testing.T) {
	h := Image_Handle{image = {width = 30, height = 10}}
	testing.expect_value(t, image_natural_size(&h), [2]f64{30, 10}) // no bitmap: as given
	b := Bitmap{width = 40, height = 20}
	h.bitmap = &b
	h.image = {width = 10}
	testing.expect_value(t, image_natural_size(&h), [2]f64{10, 5})
	h.image = {height = 10}
	testing.expect_value(t, image_natural_size(&h), [2]f64{20, 10})
	h.image = {}
	testing.expect_value(t, image_natural_size(&h), [2]f64{40, 20})
	h.image = {width = 7, height = 9}
	testing.expect_value(t, image_natural_size(&h), [2]f64{7, 9})
}

@(test)
test_container_frame :: proc(t: ^testing.T) {
	h := Container_Handle{container = {margin = {1, 2, 3, 4}, border_width = 5, padding = {10, 20, 30, 40}}}
	testing.expect_value(t, container_frame(&h), Insets{16, 27, 38, 49})
}

@(test)
test_color_argb :: proc(t: ^testing.T) {
	testing.expect_value(t, color_argb({1, 0, 0, 1}), 0xFFFF0000)
	testing.expect_value(t, color_argb({}), 0)
	testing.expect_value(t, color_argb({2, -1, 0.5, 1}), 0xFFFF0080) // clamped; 0.5 rounds to 0x80
}

@(test)
test_opentype_info :: proc(t: ^testing.T) {
	data := TUFFY_BOLD
	family, weight, italic, ok := opentype_info(data)
	defer delete(family)
	testing.expect(t, ok && family == "Tuffy" && weight == 700 && !italic)
	_, _, _, ok_nil := opentype_info(nil)
	_, _, _, ok_cut := opentype_info(data[:64]) // the table directory points past the end
	_, _, _, ok_woff := opentype_info(transmute([]u8)string("wOFF........"))
	testing.expect(t, !ok_nil && !ok_cut && !ok_woff)
}
