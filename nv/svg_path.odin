#+private
package nv

// SVG path data (Material's 24-unit icons) replayed as moves, lines and cubics onto a backend's
// path through a Svg_Sink: M, L, H, V, C, S, A and Z, absolute and relative, with implicit
// repeats; an arc becomes cubics of at most a quarter turn. It stops at anything else (Q and T,
// which Material's icons don't use). Android draws its missing system icons with it
// (icon_android.odin), Windows its bar's icons (nav_windows.odin). Pure: svg_path_test.odin.

import "core:math"
import "core:strconv"

// Material's icons (Apache 2.0) on a 24-unit grid, by Icon: the set nv.js draws on the web.
@(private) material_icon_paths := [Icon]string{
	.None     = "",
	.Add      = "M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z",
	.Edit     = "M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z",
	.Delete   = "M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z",
	.Search   = MATERIAL_SEARCH_PATH,
	.Share    = "M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11A2.99 2.99 0 0 0 21 5a3 3 0 1 0-5.91.7L8.04 9.81A2.99 2.99 0 0 0 3 12a3 3 0 0 0 5.04 2.19l7.12 4.16c-.05.21-.08.43-.08.65a2.92 2.92 0 1 0 2.92-2.92z",
	.Settings = "M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84a.47.47 0 0 0-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.48.48 0 0 0-.59.22L2.74 8.87a.47.47 0 0 0 .12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32a.48.48 0 0 0-.12-.61l-2.01-1.58zM12 15.6a3.6 3.6 0 1 1 0-7.2 3.6 3.6 0 0 1 0 7.2z",
	.Refresh  = "M17.65 6.35A7.96 7.96 0 0 0 12 4a8 8 0 1 0 7.73 10h-2.08A6 6 0 1 1 12 6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z",
	.Done     = "M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z",
	.Info     = "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z",
	.More     = "M12 8a2 2 0 1 0 0-4 2 2 0 0 0 0 4zm0 2a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm0 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4z",
	.Close    = "M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z",
	.Menu     = MATERIAL_MENU_PATH,
	.Home     = "M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z",
	.Star     = "M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z",
	.Person   = "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z",
	.Hub      = MATERIAL_HUB_PATH,
}

// Material's arrow_back: the bar's back button (nv.js's ICONS[len(Icon)]).
@(private) MATERIAL_BACK_PATH :: "M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"

// Where svg_path_replay puts the path, in the path's own units.
@(private)
Svg_Sink :: struct {
	user:     rawptr,
	move_to:  proc(user: rawptr, x, y: f32),
	line_to:  proc(user: rawptr, x, y: f32),
	cubic_to: proc(user: rawptr, c1x, c1y, c2x, c2y, x, y: f32),
	close:    proc(user: rawptr),
}

@(private)
svg_path_replay :: proc(d: string, sink: Svg_Sink) {
	s := d
	cmd, prev: u8
	x, y, sx, sy, c2x, c2y: f32 // the current point, the subpath's start, the last cubic's 2nd control point
	for {
		svg_skip(&s)
		if len(s) == 0 do return
		if c := s[0]; c >= 'A' && c <= 'z' && !(c > 'Z' && c < 'a') {
			cmd = c
			s = s[1:]
			if cmd == 'Z' || cmd == 'z' {
				sink.close(sink.user)
				x, y = sx, sy
				prev = 'Z'
				continue
			}
		} else if cmd == 0 || cmd == 'Z' || cmd == 'z' {
			return // a number without a command
		}
		rel := cmd >= 'a'
		ox, oy := rel ? x : 0, rel ? y : 0
		n: [7]f32
		count := 0
		switch cmd | 0x20 { // lower case
		case 'm', 'l': count = 2
		case 'h', 'v': count = 1
		case 'c':      count = 6
		case 's':      count = 4
		case 'a':      count = 7
		case:          return
		}
		for i in 0 ..< count {
			ok: bool
			if cmd | 0x20 == 'a' && (i == 3 || i == 4) {
				n[i], ok = svg_flag(&s) // a flag may touch the next number: "011"
			} else {
				n[i], ok = svg_number(&s)
			}
			if !ok do return
		}
		switch cmd | 0x20 {
		case 'm':
			x, y = ox + n[0], oy + n[1]
			sink.move_to(sink.user, x, y)
			sx, sy = x, y
			cmd = rel ? 'l' : 'L' // more pairs are lines
		case 'l':
			x, y = ox + n[0], oy + n[1]
			sink.line_to(sink.user, x, y)
		case 'h':
			x = ox + n[0]
			sink.line_to(sink.user, x, y)
		case 'v':
			y = oy + n[0]
			sink.line_to(sink.user, x, y)
		case 'c', 's':
			c1x, c1y: f32
			k := 0
			if cmd | 0x20 == 'c' {
				c1x, c1y = ox + n[0], oy + n[1]
				k = 2
			} else if prev == 'C' || prev == 'S' {
				c1x, c1y = 2 * x - c2x, 2 * y - c2y // the reflection of the last control point
			} else {
				c1x, c1y = x, y
			}
			c2x, c2y = ox + n[k], oy + n[k + 1]
			x, y = ox + n[k + 2], oy + n[k + 3]
			sink.cubic_to(sink.user, c1x, c1y, c2x, c2y, x, y)
		case 'a':
			ex, ey := ox + n[5], oy + n[6]
			svg_arc(sink, x, y, n[0], n[1], n[2], n[3] != 0, n[4] != 0, ex, ey)
			x, y = ex, ey
		}
		prev = cmd &~ 0x20 // upper case
	}
}

// An elliptical arc from (x1, y1) to (x2, y2) as cubics of at most a quarter turn each, through
// its centre (SVG 1.1 appendix F.6.5 and F.6.6).
@(private = "file")
svg_arc :: proc(sink: Svg_Sink, x1, y1, rx_, ry_, rotation: f32, large, sweep: bool, x2, y2: f32) {
	if x1 == x2 && y1 == y2 do return
	rx, ry := math.abs(f64(rx_)), math.abs(f64(ry_))
	if rx == 0 || ry == 0 {
		sink.line_to(sink.user, x2, y2)
		return
	}
	sin, cos := math.sincos(f64(rotation) * math.PI / 180)
	dx, dy := f64(x1 - x2) / 2, f64(y1 - y2) / 2
	px, py := cos * dx + sin * dy, -sin * dx + cos * dy // the start, in the ellipse's frame
	if l := px * px / (rx * rx) + py * py / (ry * ry); l > 1 { // too small to reach: scale it up
		rx *= math.sqrt(l)
		ry *= math.sqrt(l)
	}
	num := rx * rx * ry * ry - rx * rx * py * py - ry * ry * px * px
	k := math.sqrt(max(0, num / (rx * rx * py * py + ry * ry * px * px)))
	if large == sweep do k = -k
	cpx, cpy := k * rx * py / ry, -k * ry * px / rx
	cx := cos * cpx - sin * cpy + f64(x1 + x2) / 2
	cy := sin * cpx + cos * cpy + f64(y1 + y2) / 2
	angle :: proc(ux, uy, vx, vy: f64) -> f64 { return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy) }
	a := angle(1, 0, (px - cpx) / rx, (py - cpy) / ry)
	da := angle((px - cpx) / rx, (py - cpy) / ry, (-px - cpx) / rx, (-py - cpy) / ry)
	if !sweep && da > 0 do da -= 2 * math.PI
	if sweep && da < 0 do da += 2 * math.PI

	segments := max(1, int(math.ceil(math.abs(da) / (math.PI / 2) - 1e-9)))
	step := da / f64(segments)
	t := 4.0 / 3 * math.tan(step / 4) // the control points' distance on a unit circle
	// A point of the unit circle, mapped onto the ellipse.
	at :: proc(ux, uy, rx, ry, sin, cos, cx, cy: f64) -> (f32, f32) {
		return f32(cx + rx * ux * cos - ry * uy * sin), f32(cy + rx * ux * sin + ry * uy * cos)
	}
	for _ in 0 ..< segments {
		s1, c1 := math.sincos(a)
		s2, c2 := math.sincos(a + step)
		ax, ay := at(c1 - t * s1, s1 + t * c1, rx, ry, sin, cos, cx, cy)
		bx, by := at(c2 + t * s2, s2 - t * c2, rx, ry, sin, cos, cx, cy)
		ex, ey := at(c2, s2, rx, ry, sin, cos, cx, cy)
		sink.cubic_to(sink.user, ax, ay, bx, by, ex, ey)
		a += step
	}
}

@(private = "file")
svg_skip :: proc(s: ^string) {
	for len(s^) > 0 && (s[0] == ' ' || s[0] == ',' || s[0] == '\n' || s[0] == '\t') do s^ = s[1:]
}

// An arc flag: one '0' or '1'.
@(private = "file")
svg_flag :: proc(s: ^string) -> (f32, bool) {
	svg_skip(s)
	if len(s^) == 0 || (s[0] != '0' && s[0] != '1') do return 0, false
	v := f32(s[0] - '0')
	s^ = s[1:]
	return v, true
}

// The next number: an optional sign, digits with at most one point, an optional exponent; a sign
// or a second point starts the next one ("1.5-2", ".5.6").
@(private = "file")
svg_number :: proc(s: ^string) -> (f32, bool) {
	svg_skip(s)
	t := s^
	i := 0
	if i < len(t) && (t[i] == '-' || t[i] == '+') do i += 1
	point := false
	for i < len(t) && ((t[i] >= '0' && t[i] <= '9') || (t[i] == '.' && !point)) {
		if t[i] == '.' do point = true
		i += 1
	}
	if i < len(t) && (t[i] == 'e' || t[i] == 'E') {
		i += 1
		if i < len(t) && (t[i] == '-' || t[i] == '+') do i += 1
		for i < len(t) && t[i] >= '0' && t[i] <= '9' do i += 1
	}
	v, ok := strconv.parse_f32(t[:i])
	if !ok do return 0, false
	s^ = t[i:]
	return v, true
}
