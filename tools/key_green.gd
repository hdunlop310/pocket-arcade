extends SceneTree
# Keys the flat #00FF00 background out of a Gemini cut-out and crops to the content.
# Usage: GODOT --headless --path . --script tools/key_green.gd -- <in> <out> [max_width]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0])
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var minx := w
	var miny := h
	var maxx := 0
	var maxy := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var green := c.g - maxf(c.r, c.b)
			if green > 0.35:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			if green > 0.12:
				# fringe: pull the green out and fade the edge
				var a := clampf(1.0 - (green - 0.12) / 0.23, 0.0, 1.0)
				img.set_pixel(x, y, Color(c.r, minf(c.g, maxf(c.r, c.b)), c.b, a))
			if img.get_pixel(x, y).a > 0.5:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	var out := img.get_region(Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1))
	if args.size() > 2 and out.get_width() > int(args[2]):
		var k := float(args[2]) / float(out.get_width())
		out.resize(int(args[2]), int(out.get_height() * k), Image.INTERPOLATE_LANCZOS)
	out.save_png(args[1])
	print("keyed ", args[0], " -> ", out.get_width(), "x", out.get_height())
	quit()
