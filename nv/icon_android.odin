#+build linux:android
#+private
package nv

// Icons drawn from Material's 24-unit SVG paths (nv.js has every icon's) into a ShapeDrawable, where
// android.R.drawable has none or only Holo's: the hamburger (the closest drawable is a sort icon),
// the hub and the search magnifier.

import "core:math"
import "core:strconv"

@(private) android_icon_paths := #partial [Icon]string{
	.Search = MATERIAL_SEARCH_PATH,
	.Menu   = MATERIAL_MENU_PATH,
	.Hub    = MATERIAL_HUB_PATH,
}

// `icon` at 24 dp in `color`, a local ref; nil when it has no path (android_icon_res has the rest).
@(private)
android_icon_drawable :: proc(env: JNI_Env, icon: Icon, color: Color) -> jobject {
	d := android_icon_paths[icon]
	if d == "" do return nil
	path := path_new(env)
	defer jni_delete_local_ref(env, path)
	svg_path_replay(env, path, d)
	shape := path_shape_new(env, path, 24, 24)
	defer jni_delete_local_ref(env, shape)
	drawable := shape_drawable_new(env, shape)
	paint := shape_drawable_get_paint(env, drawable)
	paint_set_color(env, paint, android_argb(color))
	jni_delete_local_ref(env, paint)
	size := android_dp(24)
	shape_drawable_set_intrinsic_width(env, drawable, size)
	shape_drawable_set_intrinsic_height(env, drawable, size)
	return drawable
}

// Replays an SVG path's M, L, H, V, C, S, A and Z commands (absolute and relative, with implicit
// repeats) on an android.graphics.Path; stops at anything else (Q and T, which Material's icons
// don't use).
@(private)
svg_path_replay :: proc(env: JNI_Env, path: jobject, d: string) {
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
				path_close(env, path)
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
			path_move_to(env, path, x, y)
			sx, sy = x, y
			cmd = rel ? 'l' : 'L' // more pairs are lines
		case 'l':
			x, y = ox + n[0], oy + n[1]
			path_line_to(env, path, x, y)
		case 'h':
			x = ox + n[0]
			path_line_to(env, path, x, y)
		case 'v':
			y = oy + n[0]
			path_line_to(env, path, x, y)
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
			path_cubic_to(env, path, c1x, c1y, c2x, c2y, x, y)
		case 'a':
			ex, ey := ox + n[5], oy + n[6]
			svg_arc(env, path, x, y, n[0], n[1], n[2], n[3] != 0, n[4] != 0, ex, ey)
			x, y = ex, ey
		}
		prev = cmd &~ 0x20 // upper case
	}
}

// An elliptical arc from (x1, y1) to (x2, y2) as cubics of at most a quarter turn each, through
// its centre (SVG 1.1 appendix F.6.5 and F.6.6).
@(private = "file")
svg_arc :: proc(env: JNI_Env, path: jobject, x1, y1, rx_, ry_, rotation: f32, large, sweep: bool, x2, y2: f32) {
	if x1 == x2 && y1 == y2 do return
	rx, ry := math.abs(f64(rx_)), math.abs(f64(ry_))
	if rx == 0 || ry == 0 {
		path_line_to(env, path, x2, y2)
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
		path_cubic_to(env, path, ax, ay, bx, by, ex, ey)
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
