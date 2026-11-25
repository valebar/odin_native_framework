package nvbuild

// Web: app.wasm (-target:js_wasm32) next to nv/web's page, script and style sheet, the odin.js of
// the compiler that built it (its runtime imports must match the wasm), and app/assets with their
// list (assets.json, which nv.js fetches before the app starts). Unless --no-run, build/web is then
// served on 127.0.0.1 (--port, default 8000) and opened in the default browser (not with --no-open). A debug build's
// page also posts the app's stdout and uncaught errors to the server (POST /__nv/log), which prints
// them, so the console is attached as on the other platforms. Ctrl-C stops the server.

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:thread"
import "core:time"

PORT_DEFAULT :: 8000

build_web :: proc(opt: Options) {
	OUT :: "build/web"
	mkdir(OUT)
	odin_build(opt, OUT + "/app.wasm", "-target:js_wasm32")

	root, ok := capture("odin", "root")
	if !ok do fail("`odin root` failed: odin.js comes from the compiler's core/sys/wasm/js")
	copy_file(path(root, "core", "sys", "wasm", "js", "odin.js"), OUT + "/odin.js")
	copy_file("nv/web/nv.js", OUT + "/nv.js")
	copy_file("nv/web/nv.css", OUT + "/nv.css")
	html, err := os.read_entire_file("nv/web/index.html", context.allocator)
	if err != nil do fail("cannot read nv/web/index.html: %v", err)
	page, _ := strings.replace_all(string(html), "NV_DEV_LOG", opt.release ? "false" : "true")
	write(OUT + "/index.html", page)

	copy_assets(OUT)
	write(OUT + "/assets.json", assets_json(path(OUT, "assets")))

	if !opt.no_run do serve_web(OUT, opt.port > 0 ? opt.port : PORT_DEFAULT, !opt.no_open)
}

copy_file :: proc(src, dst: string) {
	fmt.printfln("+ copy %s %s", src, dst)
	if err := os.copy_file(dst, src); err != nil do fail("cannot copy %s to %s: %v", src, dst, err)
}

write :: proc(dst, data: string) {
	if err := os.write_entire_file(dst, data); err != nil do fail("cannot write %s: %v", dst, err)
}

// The files under `dir` as a JSON array of '/'-separated paths relative to it.
assets_json :: proc(dir: string) -> string {
	b := strings.builder_make()
	strings.write_byte(&b, '[')
	top := abs(dir)
	w := os.walker_create(top)
	defer os.walker_destroy(&w)
	n := 0
	for fi in os.walker_walk(&w) {
		if fi.type != .Regular || !strings.has_prefix(fi.fullpath, top) do continue
		rel, _ := strings.replace_all(strings.trim_left(fi.fullpath[len(top):], "/\\"), "\\", "/")
		if n > 0 do strings.write_byte(&b, ',')
		strings.write_quoted_string(&b, rel)
		n += 1
	}
	if p, err := os.walker_error(&w); err != nil do fail("cannot list %s: %v", p, err)
	strings.write_byte(&b, ']')
	return strings.to_string(b)
}

// ---- the dev server ----

serve_web :: proc(dir: string, port: int, open: bool) {
	sock, err := net.listen_tcp({address = net.IP4_Loopback, port = port})
	if err != nil do fail("cannot listen on 127.0.0.1:%d: %v (is a server already running? pass --port)", port, err)
	url := fmt.tprintf("http://127.0.0.1:%d/", port)
	fmt.printfln("nvbuild: serving %s at %s (Ctrl-C stops it)", dir, url)
	if open do #partial switch ODIN_OS {
	case .Darwin:  spawn("open", url)
	case .Windows: spawn("cmd", "/c", "start", "", url)
	case:          spawn("xdg-open", url)
	}
	root := abs(dir)
	for {
		client, _, aerr := net.accept_tcp(sock)
		if aerr != nil do continue
		// One thread per connection, so a browser's idle preconnect never holds up the others.
		thread.create_and_start_with_poly_data2(client, root, serve_connection, self_cleanup = true)
	}
}

serve_connection :: proc(client: net.TCP_Socket, root: string) {
	defer net.close(client)
	defer free_all(context.temp_allocator)
	net.set_option(client, .Receive_Timeout, 5 * time.Second)

	// The head, then as much of the body as Content-Length says.
	buf := make([dynamic]u8, context.temp_allocator)
	chunk: [8192]u8
	head_end := -1
	for head_end < 0 {
		n, rerr := net.recv_tcp(client, chunk[:])
		if rerr != nil || n == 0 do return
		append(&buf, ..chunk[:n])
		head_end = strings.index(string(buf[:]), "\r\n\r\n")
		if len(buf) > 64 * 1024 do return
	}
	head := string(buf[:head_end])
	lines := strings.split_lines(head, context.temp_allocator)
	parts := strings.fields(lines[0], context.temp_allocator)
	if len(parts) < 2 do return
	method, target := parts[0], parts[1]
	length := 0
	for line in lines[1:] {
		colon := strings.index_byte(line, ':')
		if colon > 0 && strings.equal_fold(strings.trim_space(line[:colon]), "content-length") {
			length, _ = strconv.parse_int(strings.trim_space(line[colon + 1:]))
		}
	}
	for len(buf) - (head_end + 4) < length {
		n, rerr := net.recv_tcp(client, chunk[:])
		if rerr != nil || n == 0 do break
		append(&buf, ..chunk[:n])
	}
	body := buf[head_end + 4:]

	if q := strings.index_byte(target, '?'); q >= 0 do target = target[:q]
	switch {
	case method == "POST" && target == "/__nv/log":
		os.write(os.stdout, body)
		respond(client, "204 No Content", "", nil)
	case method == "GET" || method == "HEAD":
		if target == "/" do target = "/index.html"
		if strings.contains(target, "..") || strings.contains_rune(target, '\\') {
			respond(client, "400 Bad Request", "text/plain", transmute([]u8)string("bad path\n"))
			return
		}
		data, rerr := os.read_entire_file(strings.concatenate({root, target}, context.temp_allocator), context.temp_allocator)
		if rerr != nil {
			respond(client, "404 Not Found", "text/plain", transmute([]u8)string("not found\n"))
			return
		}
		respond(client, "200 OK", content_type(target), method == "HEAD" ? nil : data, len(data))
	case:
		respond(client, "405 Method Not Allowed", "text/plain", nil)
	}
}

respond :: proc(client: net.TCP_Socket, status, type: string, body: []u8, length := -1) {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "HTTP/1.1 %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n", status, length >= 0 ? length : len(body))
	if type != "" do fmt.sbprintf(&b, "Content-Type: %s\r\n", type)
	strings.write_string(&b, "\r\n")
	send_all(client, b.buf[:])
	send_all(client, body)
}

send_all :: proc(client: net.TCP_Socket, data: []u8) {
	for sent := 0; sent < len(data); {
		n, err := net.send_tcp(client, data[sent:])
		if err != nil || n <= 0 do return
		sent += n
	}
}

content_type :: proc(p: string) -> string {
	switch {
	case strings.has_suffix(p, ".html"): return "text/html; charset=utf-8"
	case strings.has_suffix(p, ".js"):   return "text/javascript; charset=utf-8"
	case strings.has_suffix(p, ".css"):  return "text/css; charset=utf-8"
	case strings.has_suffix(p, ".json"): return "application/json"
	case strings.has_suffix(p, ".wasm"): return "application/wasm"
	case strings.has_suffix(p, ".png"):  return "image/png"
	case strings.has_suffix(p, ".jpg"), strings.has_suffix(p, ".jpeg"): return "image/jpeg"
	case strings.has_suffix(p, ".gif"):  return "image/gif"
	case strings.has_suffix(p, ".webp"): return "image/webp"
	case strings.has_suffix(p, ".svg"):  return "image/svg+xml"
	case strings.has_suffix(p, ".ttf"):  return "font/ttf"
	case strings.has_suffix(p, ".otf"):  return "font/otf"
	case strings.has_suffix(p, ".woff2"): return "font/woff2"
	}
	return "application/octet-stream"
}
