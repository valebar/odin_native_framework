#+private
package nv

// Reads what the backends that select a loaded font by name (fontconfig on Linux, GDI on Windows)
// need out of a TrueType / OpenType font file: the family name and the face's weight and slant,
// so the loaded face is chosen even when the family is installed too. The family is nameID 1,
// the legacy family, which is what GDI matches (nameID 16, the typographic family, is ignored
// there). Every read is bounds-checked against the data, not the declared table lengths, which
// real fonts get wrong.

import "core:encoding/endian"
import "core:strings"
import "core:unicode/utf16"

@(private)
opentype_info :: proc(data: []u8, allocator := context.allocator) -> (family: string, weight: int, italic: bool, ok: bool) {
	u16at :: proc "contextless" (b: []u8, at: int) -> (u16, bool) {
		if at < 0 || at + 2 > len(b) do return 0, false
		return endian.get_u16(b[at:], .Big)
	}
	u32at :: proc "contextless" (b: []u8, at: int) -> (u32, bool) {
		if at < 0 || at + 4 > len(b) do return 0, false
		return endian.get_u32(b[at:], .Big)
	}

	// A collection ('ttcf') exposes its first face only.
	base := 0
	if len(data) >= 16 && string(data[:4]) == "ttcf" {
		base = int(u32at(data, 12) or_return)
	}
	if len(data) < base + 12 do return
	switch string(data[base:base + 4]) {
	case "\x00\x01\x00\x00", "OTTO", "true": // TrueType outlines, CFF outlines, Apple's tag
	case: return
	}

	// The table directory: 16-byte records after the 12-byte header.
	num_tables := int(u16at(data, base + 4) or_return)
	name, os2 := -1, -1
	for i in 0 ..< num_tables {
		rec := base + 12 + i * 16
		if rec + 16 > len(data) do return
		switch string(data[rec:rec + 4]) {
		case "name": name = int(u32at(data, rec + 8) or_return)
		case "OS/2": os2 = int(u32at(data, rec + 8) or_return)
		}
	}
	if name < 0 do return

	// OS/2: usWeightClass at 4 (100..900, 400 regular), fsSelection at 62 with bit 0 = italic.
	weight = 400
	if os2 >= 0 {
		if w, has := u16at(data, os2 + 4); has && w >= 100 && w <= 1000 do weight = int(w)
		if sel, has := u16at(data, os2 + 62); has do italic = sel & 1 != 0
	}

	// Name records: 12 bytes each after the 6-byte header; the strings follow at string_offset.
	count := int(u16at(data, name + 2) or_return)
	string_offset := int(u16at(data, name + 4) or_return)
	best, best_score := -1, 0
	for i in 0 ..< count {
		rec := name + 6 + i * 12
		platform := u16at(data, rec) or_return
		encoding := u16at(data, rec + 2) or_return
		language := u16at(data, rec + 4) or_return
		id := u16at(data, rec + 6) or_return
		if id != 1 do continue
		score: int
		switch {
		case platform == 3 && language == 0x409: score = 4 // Windows, US English
		case platform == 3:                       score = 3 // Windows, any language (UTF-16BE)
		case platform == 0:                       score = 2 // Unicode (UTF-16BE)
		case platform == 1 && encoding == 0:      score = 1 // Macintosh Roman; the ASCII subset only
		case: continue
		}
		if score > best_score do best, best_score = rec, score
	}
	if best < 0 do return

	platform := u16at(data, best) or_return
	length := int(u16at(data, best + 8) or_return)
	offset := int(u16at(data, best + 10) or_return)
	start := name + string_offset + offset
	if start < 0 || start + length > len(data) do return
	bytes := data[start:][:length]

	b := strings.builder_make(allocator)
	if platform == 1 {
		for c in bytes do strings.write_byte(&b, c < 0x80 ? c : '?')
	} else {
		units := make([]u16, length / 2, context.temp_allocator)
		for &u, i in units do u = u16(bytes[2 * i]) << 8 | u16(bytes[2 * i + 1])
		runes := make([]rune, len(units), context.temp_allocator)
		n := utf16.decode(runes, units)
		for r in runes[:n] do strings.write_rune(&b, r)
	}
	family = strings.to_string(b)
	if family == "" {
		strings.builder_destroy(&b)
		return "", 0, false, false
	}
	return family, weight, italic, true
}
