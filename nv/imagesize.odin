#+private
package nv

// An image's dimensions from its header (PNG, JPEG, GIF, WebP, BMP), without decoding it. The web
// backend needs a Bitmap's size at once (image_natural_size, the layout), while the browser only
// decodes asynchronously. Shared and tag-free, so the host tests cover it.

@(private)
image_size :: proc "contextless" (data: []u8) -> (width, height: int, ok: bool) {
	be16 :: proc "contextless" (d: []u8, i: int) -> int { return int(d[i]) << 8 | int(d[i + 1]) }
	be32 :: proc "contextless" (d: []u8, i: int) -> int { return be16(d, i) << 16 | be16(d, i + 2) }
	le16 :: proc "contextless" (d: []u8, i: int) -> int { return int(d[i]) | int(d[i + 1]) << 8 }
	le24 :: proc "contextless" (d: []u8, i: int) -> int { return le16(d, i) | int(d[i + 2]) << 16 }
	le32 :: proc "contextless" (d: []u8, i: int) -> int { return int(i32(u32(le16(d, i)) | u32(le16(d, i + 2)) << 16)) }

	n := len(data)
	w, h := 0, 0
	switch {
	case n >= 24 && string(data[:8]) == "\x89PNG\r\n\x1a\n" && string(data[12:16]) == "IHDR":
		w, h = be32(data, 16), be32(data, 20)
	case n >= 10 && (string(data[:6]) == "GIF87a" || string(data[:6]) == "GIF89a"):
		w, h = le16(data, 6), le16(data, 8)
	case n >= 26 && string(data[:2]) == "BM":
		if le32(data, 14) == 12 { // BITMAPCOREHEADER: 16-bit sizes
			w, h = le16(data, 18), le16(data, 20)
		} else {
			w, h = le32(data, 18), abs(le32(data, 22)) // a negative height is a top-down bitmap
		}
	case n >= 30 && string(data[:4]) == "RIFF" && string(data[8:12]) == "WEBP":
		switch string(data[12:16]) {
		case "VP8 ": // lossy: a 3-byte frame tag, the start code, then 14-bit sizes
			if data[23] == 0x9d && data[24] == 0x01 && data[25] == 0x2a do w, h = le16(data, 26) & 0x3fff, le16(data, 28) & 0x3fff
		case "VP8L": // lossless: the signature, then 14-bit sizes minus one, packed
			if data[20] == 0x2f {
				b := le32(data, 21)
				w, h = (b & 0x3fff) + 1, (b >> 14 & 0x3fff) + 1
			}
		case "VP8X": // extended: 24-bit canvas sizes minus one
			w, h = le24(data, 24) + 1, le24(data, 27) + 1
		}
	case n >= 4 && data[0] == 0xff && data[1] == 0xd8:
		// JPEG: walk the segments to the first start-of-frame, which holds the height, then the width.
		for i := 2; i + 4 <= n; {
			if data[i] != 0xff do break
			marker := data[i + 1]
			i += 2
			switch {
			case marker == 0xff:                                   i -= 1 // fill byte
			case marker == 0x01 || (marker >= 0xd0 && marker <= 0xd8): // no length
			case marker >= 0xc0 && marker <= 0xcf && marker != 0xc4 && marker != 0xc8 && marker != 0xcc:
				if i + 7 <= n do w, h = be16(data, i + 5), be16(data, i + 3)
				return w, h, w > 0 && h > 0
			case:
				i += be16(data, i)
			}
		}
	}
	return w, h, w > 0 && h > 0
}
