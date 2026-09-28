package jnigen

// Generates nv/jni_api_android.odin, typed Odin wrappers for the Java members listed in
// nv/android/jni_api.txt, with every descriptor taken from `javap -s` over android.jar and the
// compiled nv shims rather than written by hand. A member the spec names that javap does not
// list is an error, so the Android build fails instead of the app crashing on a bad descriptor.
//
// Usage: odin run android/jnigen -- -jar:<android.jar> -classes:<dir> -spec:<file> -out:<file> [-javap:<exe>]
//
// Spec lines (`#` comments, blank lines ignored; `= name` overrides the Odin name):
//   android.view.View                  setPadding(int left, int top, int right, int bottom)
//   android.view.View                  <init>(android.content.Context context)
//   android.widget.EditText            android.text.Editable getText()   # return type disambiguates
//   android.util.DisplayMetrics        .density                          # a field
//   android.widget.LinearLayout$LayoutParams <init>(int w, int h, float weight) = linear_lp_new
// Parameter names are optional (a0, a1, .. otherwise); types are Java, fully qualified, `$` for
// inner classes. Static is taken from javap. Odin names default to <class>_<member> in snake case.
//
// Type mapping: int → int, long → i64, float → f32, double → f64, boolean → bool,
// java.lang.String / CharSequence → string (the wrapper makes a temporary jstring; such wrappers
// need a context), byte[] → []u8, any other object or array → jobject. Returns are void, jint,
// bool, f32, or jobject (a local ref the caller frees; a String or byte[] comes back as jobject too).

import "core:fmt"
import "core:os"
import "core:strings"

Param :: struct {
	type: string, // Java type from the spec ("int", "android.content.Context")
	name: string, // "" = a<index>
}

Spec :: struct {
	line:      int,
	class:     string,  // Java name, "android.view.View"
	name:      string,  // member name; "<init>" for a constructor
	ret:       string,  // optional Java return type from the spec, "" = any
	params:    [dynamic]Param,
	is_field:  bool,
	odin_name: string,  // "" = derived
	// Resolved from javap:
	sig:       string,
	static:    bool,
}

// One member as javap -s prints it.
Javap_Member :: struct {
	name:     string,
	ret:      string,   // Java return type ("" for a constructor)
	params:   []string, // Java types
	sig:      string,   // descriptor
	static:   bool,
	is_field: bool,
}

main :: proc() {
	jar, classes, spec_path, out_path, javap := "", "", "", "", "javap"
	for a in os.args[1:] {
		switch {
		case strings.has_prefix(a, "-jar:"):     jar = a[5:]
		case strings.has_prefix(a, "-classes:"): classes = a[9:]
		case strings.has_prefix(a, "-spec:"):    spec_path = a[6:]
		case strings.has_prefix(a, "-out:"):     out_path = a[5:]
		case strings.has_prefix(a, "-javap:"):   javap = a[7:]
		case:
			fail("unknown argument %q", a)
		}
	}
	if spec_path == "" || out_path == "" || jar == "" do fail("usage: jnigen -jar:<android.jar> -classes:<dir> -spec:<file> -out:<file> [-javap:<exe>]")

	specs := parse_spec(spec_path)
	classes_used := make([dynamic]string)
	for s in specs {
		if !contains(classes_used[:], s.class) do append(&classes_used, s.class)
	}

	members := run_javap(javap, jar, classes, classes_used[:])
	errors := 0
	names := make(map[string]int) // Odin name → spec line, for duplicates
	for &s in specs {
		if !resolve(&s, members[s.class], spec_path) do errors += 1
		if s.odin_name == "" do s.odin_name = derive_name(s)
		if prev, dup := names[s.odin_name]; dup {
			fmt.eprintfln("%s:%d: Odin name %s already used on line %d; add `= name`", spec_path, s.line, s.odin_name, prev)
			errors += 1
		}
		names[s.odin_name] = s.line
	}
	if errors > 0 do os.exit(1)

	code := emit(specs[:], classes_used[:], spec_path)
	if err := os.write_entire_file(out_path, transmute([]byte)code); err != nil do fail("cannot write %s: %v", out_path, err)
	fmt.printfln("jnigen: %d members in %d classes → %s", len(specs), len(classes_used), out_path)
}

fail :: proc(format: string, args: ..any) -> ! {
	fmt.eprint("jnigen: ")
	fmt.eprintfln(format, ..args)
	os.exit(1)
}

contains :: proc(list: []string, s: string) -> bool {
	for x in list do if x == s do return true
	return false
}

// ---- spec ----

parse_spec :: proc(path: string) -> [dynamic]Spec {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil do fail("cannot read %s: %v", path, err)
	specs := make([dynamic]Spec)
	for line, i in strings.split_lines(string(data)) {
		text := line
		if hash := strings.index_byte(text, '#'); hash >= 0 do text = text[:hash]
		text = strings.trim_space(text)
		if text == "" do continue
		s := Spec{line = i + 1}
		if eq := strings.index_byte(text, '='); eq >= 0 {
			s.odin_name = strings.trim_space(text[eq + 1:])
			text = strings.trim_space(text[:eq])
		}
		sp := strings.index_any(text, " \t")
		if sp < 0 do fail("%s:%d: expected `class member`", path, s.line)
		s.class = text[:sp]
		member := strings.trim_space(text[sp:])
		if strings.has_prefix(member, ".") { // field
			s.is_field = true
			s.name = member[1:]
		} else {
			open := strings.index_byte(member, '(')
			close := strings.last_index_byte(member, ')')
			if open < 0 || close < open do fail("%s:%d: expected `name(params)` or `.field`", path, s.line)
			head := strings.fields(member[:open])
			switch len(head) {
			case 1: s.name = head[0]
			case 2: s.ret, s.name = head[0], head[1]
			case:   fail("%s:%d: expected `[return] name(params)`", path, s.line)
			}
			for p in strings.split(member[open + 1:close], ",") {
				words := strings.fields(p)
				switch len(words) {
				case 0: // "()"
				case 1: append(&s.params, Param{type = words[0]})
				case 2: append(&s.params, Param{type = words[0], name = words[1]})
				case:   fail("%s:%d: bad parameter %q", path, s.line, p)
				}
			}
		}
		append(&specs, s)
	}
	return specs
}

// ---- javap ----

run_javap :: proc(javap, jar, classes: string, class_names: []string) -> map[string][dynamic]Javap_Member {
	cp := classes == "" ? jar : fmt.tprintf("%s:%s", jar, classes)
	cmd := make([dynamic]string)
	append(&cmd, javap, "-s", "-p", "-cp", cp)
	for c in class_names do append(&cmd, c)
	state, stdout, stderr, err := os.process_exec({command = cmd[:]}, context.allocator)
	if err != nil do fail("cannot run %s: %v", javap, err)
	if len(stderr) > 0 do fmt.eprint(string(stderr))
	if !state.success && len(stdout) == 0 do fail("%s failed (exit %d)", javap, state.exit_code)
	return parse_javap(string(stdout))
}

// javap -s prints each member as a declaration line followed by `    descriptor: ...`, under a
// class header line ending in `{`.
parse_javap :: proc(text: string) -> map[string][dynamic]Javap_Member {
	out := make(map[string][dynamic]Javap_Member)
	class := ""
	lines := strings.split_lines(text)
	for i := 0; i < len(lines); i += 1 {
		line := lines[i]
		trimmed := strings.trim_space(line)
		if trimmed == "" || trimmed == "}" || strings.has_prefix(trimmed, "Compiled from") do continue
		if !strings.has_prefix(line, " ") && strings.has_suffix(trimmed, "{") {
			class = header_class_name(trimmed)
			if _, ok := out[class]; !ok do out[class] = make([dynamic]Javap_Member)
			continue
		}
		if i + 1 >= len(lines) do break
		desc := strings.trim_space(lines[i + 1])
		if !strings.has_prefix(desc, "descriptor: ") do continue
		i += 1
		m, ok := parse_declaration(strings.trim_suffix(trimmed, ";"), class)
		if !ok do continue
		m.sig = desc[len("descriptor: "):]
		list := &out[class]
		append(list, m)
	}
	return out
}

// `public final class android.graphics.Paint$Style extends java.lang.Enum<...> {`
header_class_name :: proc(line: string) -> string {
	words := strings.fields(strip_generics(line))
	for w, i in words {
		if (w == "class" || w == "interface" || w == "enum") && i + 1 < len(words) do return words[i + 1]
	}
	return ""
}

// `public static android.graphics.Paint$Style valueOf(java.lang.String)`,
// `public final <T extends android.view.View> T findViewById(int)`, `public int widthPixels`.
parse_declaration :: proc(decl: string, class: string) -> (m: Javap_Member, ok: bool) {
	text := decl
	if t := strings.index(text, " throws "); t >= 0 do text = text[:t]
	open := strings.index_byte(text, '(')
	if open < 0 {
		words := strings.fields(strip_generics(text))
		if len(words) < 2 do return
		m.is_field = true
		m.name = words[len(words) - 1]
		m.ret = words[len(words) - 2]
		m.static = contains(words[:len(words) - 2], "static")
		return m, true
	}
	close := strings.last_index_byte(text, ')')
	if close < open do return
	head := strings.fields(strip_generics(text[:open]))
	if len(head) == 0 do return
	m.name = head[len(head) - 1]
	if m.name == class { // constructor
		m.name = "<init>"
	} else if len(head) >= 2 && !is_modifier(head[len(head) - 2]) {
		m.ret = head[len(head) - 2]
	}
	m.static = contains(head, "static")
	params := make([dynamic]string)
	for p in strings.split(strip_generics(text[open + 1:close]), ",") {
		t := strings.trim_space(p)
		if t == "" do continue
		if strings.has_suffix(t, "...") do t = strings.concatenate({t[:len(t) - 3], "[]"})
		append(&params, t)
	}
	m.params = params[:]
	return m, true
}

is_modifier :: proc(w: string) -> bool {
	switch w {
	case "public", "private", "protected", "static", "final", "abstract", "native", "synchronized", "default", "transient", "volatile", "strictfp":
		return true
	}
	return false
}

// Removes `<...>` groups (type parameters and generic arguments), which may nest.
strip_generics :: proc(s: string) -> string {
	b := strings.builder_make()
	depth := 0
	for c in s {
		switch {
		case c == '<': depth += 1
		case c == '>': depth -= 1
		case depth == 0: strings.write_rune(&b, c)
		}
	}
	return strings.to_string(b)
}

// ---- resolve ----

resolve :: proc(s: ^Spec, members: [dynamic]Javap_Member, spec_path: string) -> bool {
	if members == nil {
		fmt.eprintfln("%s:%d: class %s not found by javap", spec_path, s.line, s.class)
		return false
	}
	found := make([dynamic]Javap_Member, context.temp_allocator)
	for m in members {
		if m.name != s.name || m.is_field != s.is_field do continue
		if !s.is_field {
			if len(m.params) != len(s.params) do continue
			same := true
			for p, i in s.params do if p.type != m.params[i] { same = false; break }
			if !same do continue
			if s.ret != "" && s.ret != m.ret do continue
		}
		append(&found, m)
	}
	switch len(found) {
	case 1:
		s.sig = found[0].sig
		s.static = found[0].static
		return true
	case 0:
		fmt.eprintfln("%s:%d: %s.%s%s not found", spec_path, s.line, s.class, s.name, s.is_field ? "" : "(..)")
		listed := false
		for m in members do if m.name == s.name {
			if !listed do fmt.eprintln("    javap lists:")
			listed = true
			fmt.eprintfln("    %s %s(%s)", m.ret, m.name, strings.join(m.params, ", "))
		}
		return false
	case:
		fmt.eprintfln("%s:%d: %s.%s is ambiguous; give the return type:", spec_path, s.line, s.class, s.name)
		for m in found do fmt.eprintfln("    %s %s(%s)", m.ret, m.name, strings.join(m.params, ", "))
		return false
	}
}

// ---- naming ----

// "android.widget.LinearLayout$LayoutParams" → "linear_layout_layout_params"
class_snake :: proc(class: string) -> string {
	simple := class
	if dot := strings.last_index_byte(simple, '.'); dot >= 0 do simple = simple[dot + 1:]
	parts := strings.split(simple, "$")
	for &p in parts do p = snake(p)
	return strings.join(parts, "_")
}

// "setDisplayHomeAsUpEnabled" → "set_display_home_as_up_enabled", "RectF" → "rect_f"
snake :: proc(s: string) -> string {
	b := strings.builder_make()
	runes := make([dynamic]rune, context.temp_allocator)
	for c in s do append(&runes, c)
	for c, i in runes {
		upper := c >= 'A' && c <= 'Z'
		if upper && i > 0 {
			prev := runes[i - 1]
			prev_lower := (prev >= 'a' && prev <= 'z') || (prev >= '0' && prev <= '9')
			next_lower := i + 1 < len(runes) && runes[i + 1] >= 'a' && runes[i + 1] <= 'z'
			if prev_lower || (next_lower && prev != '_') do strings.write_byte(&b, '_')
		}
		strings.write_rune(&b, upper ? c + ('a' - 'A') : c)
	}
	return strings.to_string(b)
}

derive_name :: proc(s: Spec) -> string {
	member := s.name == "<init>" ? "new" : snake(s.name)
	return fmt.aprintf("%s_%s", class_snake(s.class), member)
}

// ---- emit ----

// One descriptor type, mapped to Odin.
Arg :: struct {
	odin:   string, // Odin parameter type
	jv:     string, // jv_* constructor
	temp:   enum { None, String, Bytes }, // needs a temporary Java object
}

arg_of :: proc(desc: string) -> (Arg, bool) {
	switch desc {
	case "I": return {"int", "jv_int", .None}, true
	case "J": return {"i64", "jv_long", .None}, true
	case "F": return {"f32", "jv_float", .None}, true
	case "D": return {"f64", "jv_double", .None}, true
	case "Z": return {"bool", "jv_bool", .None}, true
	case "Ljava/lang/String;", "Ljava/lang/CharSequence;": return {"string", "jv_obj", .String}, true
	case "[B": return {"[]u8", "jv_obj", .Bytes}, true
	}
	if desc[0] == 'L' || desc[0] == '[' do return {"jobject", "jv_obj", .None}, true
	return {}, false
}

// Splits "(ILjava/lang/String;[B)V" into its parameter descriptors and the return descriptor.
split_descriptor :: proc(sig: string) -> (params: [dynamic]string, ret: string) {
	i := 1
	for sig[i] != ')' {
		start := i
		for sig[i] == '[' do i += 1
		if sig[i] == 'L' {
			for sig[i] != ';' do i += 1
		}
		i += 1
		append(&params, sig[start:i])
	}
	return params, sig[i + 1:]
}

emit :: proc(specs: []Spec, classes: []string, spec_path: string) -> string {
	b := strings.builder_make()
	w :: fmt.sbprintfln

	body := strings.builder_make()
	needs_strings := false
	for s in specs {
		java_params := make([dynamic]string, context.temp_allocator)
		for p in s.params do append(&java_params, p.type)
		if s.is_field {
			w(&body, "// %s.%s", s.class, s.name)
		} else {
			w(&body, "// %s%s.%s(%s)", s.static ? "static " : "", s.class, s.name, strings.join(java_params[:], ", ", context.temp_allocator))
		}
		var := fmt.tprintf("%s_%s", s.is_field ? "jf" : "jm", s.odin_name)
		cls := fmt.tprintf("jc_%s", class_snake(s.class))
		if s.is_field {
			w(&body, "@(private) %s := Jni_Field{{cls = &%s, name = %q, sig = %q}}", var, cls, s.name, s.sig)
			get, ret := "", ""
			switch s.sig {
			case "I": get, ret = "jni_get_int_field", "jint"
			case "F": get, ret = "jni_get_float_field", "f32"
			case: fail("%s:%d: field type %s is not supported (int and float are)", spec_path, s.line, s.sig)
			}
			w(&body, "%s :: proc \"contextless\" (env: JNI_Env, self: jobject) -> %s {{", s.odin_name, ret)
			w(&body, "\treturn %s(env, self, &%s)", get, var)
			w(&body, "}\n")
			continue
		}
		w(&body, "@(private) %s := Jni_Method{{cls = &%s, name = %q, sig = %q%s}}", var, cls, s.name, s.sig, s.static ? ", static = true" : "")

		params, ret := split_descriptor(s.sig)
		args := make([dynamic]Arg, context.temp_allocator)
		contextless := true
		for p in params {
			a, ok := arg_of(p)
			if !ok do fail("%s:%d: parameter type %s is not supported", spec_path, s.line, p)
			if a.temp != .None do contextless = false
			append(&args, a)
		}
		call, ret_type := "", ""
		switch ret {
		case "V": call = "jni_call_void"
		case "I": call, ret_type = "jni_call_int", "jint"
		case "Z": call, ret_type = "jni_call_bool", "bool"
		case "F": call, ret_type = "jni_call_float", "f32"
		case:
			if ret[0] == 'L' || ret[0] == '[' {
				call, ret_type = "jni_call_object", "jobject"
			} else {
				fail("%s:%d: return type %s is not supported", spec_path, s.line, ret)
			}
		}
		if s.name == "<init>" do call, ret_type = "jni_new_object", "jobject"

		// Signature.
		sig := strings.builder_make(context.temp_allocator)
		fmt.sbprint(&sig, "env: JNI_Env")
		if s.name != "<init>" && !s.static do fmt.sbprint(&sig, ", self: jobject")
		names := make([dynamic]string, context.temp_allocator)
		for a, i in args {
			name := s.params[i].name
			if name == "" do name = fmt.tprintf("a%d", i)
			append(&names, name)
			fmt.sbprintf(&sig, ", %s: %s", name, a.odin)
		}
		w(&body, "%s :: proc%s (%s)%s", s.odin_name, contextless ? " \"contextless\"" : "", strings.to_string(sig), ret_type == "" ? " {" : fmt.tprintf(" -> %s {{", ret_type))

		// Temporaries for strings and byte arrays.
		call_args := make([dynamic]string, context.temp_allocator)
		for a, i in args {
			switch a.temp {
			case .None:
				append(&call_args, fmt.tprintf("%s(%s)", a.jv, names[i]))
			case .String:
				needs_strings = true
				w(&body, "\t%s_ := jni_string(env, strings.clone_to_cstring(%s, context.temp_allocator))", names[i], names[i])
				w(&body, "\tdefer jni_delete_local_ref(env, %s_)", names[i])
				append(&call_args, fmt.tprintf("jv_obj(%s_)", names[i]))
			case .Bytes:
				w(&body, "\t%s_ := jni_byte_array(env, %s)", names[i], names[i])
				w(&body, "\tdefer jni_delete_local_ref(env, %s_)", names[i])
				append(&call_args, fmt.tprintf("jv_obj(%s_)", names[i]))
			}
		}
		receiver := s.name == "<init>" ? "" : (s.static ? "nil, " : "self, ")
		rest := len(call_args) > 0 ? fmt.tprintf(", %s", strings.join(call_args[:], ", ", context.temp_allocator)) : ""
		w(&body, "\t%s%s(env, %s&%s%s)", ret_type == "" ? "" : "return ", call, receiver, var, rest)
		w(&body, "}}\n")
	}

	w(&b, "#+build linux:android")
	w(&b, "package nv")
	w(&b, "")
	w(&b, "// Generated by android/jnigen from %s; do not edit. Every descriptor was checked against", spec_path)
	w(&b, "// android.jar and the nv shims with javap. See jni.odin for the call helpers.")
	w(&b, "")
	if needs_strings {
		w(&b, "import \"core:strings\"")
		w(&b, "")
	}
	for c in classes {
		jni_name, _ := strings.replace_all(c, ".", "/", context.temp_allocator)
		w(&b, "@(private) jc_%s := Jni_Class{{name = %q}}", class_snake(c), jni_name)
	}
	w(&b, "")
	strings.write_string(&b, strings.to_string(body))
	return strings.to_string(b)
}
