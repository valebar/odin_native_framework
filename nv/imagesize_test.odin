#+build-project-name nv
#+build !js
package nv

// image_size (imagesize.odin) against minimal headers of every format it reads, and truncated ones.

import "core:testing"

@(test)
test_image_size :: proc(t: ^testing.T) {
	Case :: struct {
		name:   string,
		data:   []u8,
		w, h:   int,
	}
	png := []u8{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n', 0, 0, 0, 13, 'I', 'H', 'D', 'R', 0, 0, 0x02, 0x58, 0, 0, 0x01, 0x90}
	gif := []u8{'G', 'I', 'F', '8', '9', 'a', 0x40, 0x01, 0xf0, 0x00}
	bmp := []u8{'B', 'M', 0, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, 0x20, 0, 0, 0, 0xf0, 0xff, 0xff, 0xff} // 32 × -16 (top-down)
	bmp_core := []u8{'B', 'M', 0, 0, 0, 0, 0, 0, 0, 0, 26, 0, 0, 0, 12, 0, 0, 0, 7, 0, 9, 0, 1, 0, 24, 0}
	riff :: proc(kind: string, chunk: []u8) -> []u8 {
		out := make([dynamic]u8, context.temp_allocator)
		append(&out, "RIFF")
		append(&out, 0, 0, 0, 0)
		append(&out, "WEBP")
		append(&out, kind)
		append(&out, 0, 0, 0, 0)
		append(&out, ..chunk)
		return out[:]
	}
	vp8 := riff("VP8 ", {0, 0, 0, 0x9d, 0x01, 0x2a, 0x40, 0x01, 0xf0, 0x00})          // 320 × 240
	vp8l := riff("VP8L", {0x2f, 0x3f, 0x40, 0x3c, 0x00, 0, 0, 0, 0, 0})               // 64 × 242
	vp8x := riff("VP8X", {0, 0, 0, 0, 0xff, 0x03, 0x00, 0x7f, 0x02, 0x00})            // 1024 × 640
	// SOI, an APP0 segment (length 4), a fill byte, then SOF0: length, precision, height 480, width 640.
	jpeg := []u8{0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x00, 0x00, 0xff, 0xff, 0xc0, 0x00, 0x11, 0x08, 0x01, 0xe0, 0x02, 0x80}

	cases := []Case{
		{"png", png, 600, 400},
		{"gif", gif, 320, 240},
		{"bmp", bmp, 32, 16},
		{"bmp core", bmp_core, 7, 9},
		{"webp lossy", vp8, 320, 240},
		{"webp lossless", vp8l, 64, 242},
		{"webp extended", vp8x, 1024, 640},
		{"jpeg", jpeg, 640, 480},
	}
	for c in cases {
		w, h, ok := image_size(c.data)
		testing.expectf(t, ok && w == c.w && h == c.h, "%s: got %d × %d (ok %v), want %d × %d", c.name, w, h, ok, c.w, c.h)
		for cut in ([]int{1, len(c.data) / 2, len(c.data) - 1}) {
			_, _, short_ok := image_size(c.data[:cut])
			testing.expectf(t, !short_ok, "%s cut at %d: read a size", c.name, cut)
		}
	}
	_, _, ok := image_size(TUFFY_BOLD) // a font is not an image
	testing.expect(t, !ok)
	_, _, ok = image_size(#load("../app/assets/sample.png"))
	testing.expect(t, ok)
	free_all(context.temp_allocator)
}
