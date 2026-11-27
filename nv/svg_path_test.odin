#+build-project-name nv
#+build !js
package nv

// svg_path_replay (svg_path.odin): the commands it turns into moves, lines and cubics, and every
// Material icon replayed to its end.

import "core:fmt"
import "core:math"
import "core:strings"
import "core:testing"

@(private = "file")
Svg_Log :: struct {
	b:       strings.Builder,
	x, y:    f32, // the last point
	figures: int,
}

// To 3 decimals, without a negative zero.
@(private = "file")
r :: proc(v: f32) -> f32 {
	return math.round(v * 1000) / 1000 + 0
}

@(private = "file")
svg_log :: proc(l: ^Svg_Log, d: string) -> string {
	strings.builder_init(&l.b, context.temp_allocator)
	svg_path_replay(d, {
		user = l,
		move_to = proc(u: rawptr, x, y: f32) {
			l := (^Svg_Log)(u)
			fmt.sbprintf(&l.b, "M%v,%v ", r(x), r(y))
			l.x, l.y = x, y
			l.figures += 1
		},
		line_to = proc(u: rawptr, x, y: f32) {
			l := (^Svg_Log)(u)
			fmt.sbprintf(&l.b, "L%v,%v ", r(x), r(y))
			l.x, l.y = x, y
		},
		cubic_to = proc(u: rawptr, c1x, c1y, c2x, c2y, x, y: f32) {
			l := (^Svg_Log)(u)
			fmt.sbprintf(&l.b, "C%v,%v ", r(x), r(y))
			l.x, l.y = x, y
		},
		close = proc(u: rawptr) { strings.write_string(&(^Svg_Log)(u).b, "Z ") },
	})
	return strings.trim_space(strings.to_string(l.b))
}

@(test)
test_svg_path_commands :: proc(t: ^testing.T) {
	l: Svg_Log
	// Relative h / v, an implicit line after m, z back to the subpath's start.
	testing.expect_value(t, svg_log(&l, "M3 18h18v-2H3v2zm0-5h18"), "M3,18 L21,18 L21,16 L3,16 L3,18 Z M3,13 L21,13")
	l = {}
	// s reflects the last control point; numbers run together ("1.5-2", ".5.5").
	testing.expect_value(t, svg_log(&l, "M0 0c1 1 2 2 3 3s1.5-2 .5.5L1 1"), "M0,0 C3,3 C3.5,3.5 L1,1")
	l = {}
	// A half turn of an arc is two quarter-turn cubics ending on its end point; the flags may
	// touch the next number.
	testing.expect_value(t, svg_log(&l, "M0 0a5 5 0 1 0 10 0"), "M0,0 C5,5 C10,0")
	l = {}
	testing.expect_value(t, svg_log(&l, "M0 0a5 5 0 1010 0"), "M0,0 C5,5 C10,0")
}

// Each icon replays to its end: its last point is where its path data says, a close puts it back
// on the figure's start, so a stop half-way (an unread command) shows as a missing close.
@(test)
test_svg_material_icons :: proc(t: ^testing.T) {
	for d, icon in material_icon_paths {
		if d == "" do continue
		l: Svg_Log
		log := svg_log(&l, d)
		testing.expectf(t, l.figures > 0, "%v: no figure", icon)
		closes := strings.count(d, "z") + strings.count(d, "Z")
		testing.expectf(t, strings.count(log, "Z") == closes, "%v: %d of %d closes in %q", icon, strings.count(log, "Z"), closes, log)
		testing.expectf(t, !math.is_nan(l.x) && !math.is_nan(l.y), "%v: NaN", icon)
	}
}
