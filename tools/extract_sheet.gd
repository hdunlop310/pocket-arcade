extends SceneTree
# Cuts an AI-generated 8-frame action sheet (2 columns x 4 rows, a label for each frame, a perch tile
# under the cat) into a game atlas. Not needed at game time.
#
#   GODOT --headless --path . --script tools/extract_sheet.gd -- macho
#   (names: macho, rosette, macho_run, adora)
#
# Per frame: make the background transparent, delete label text and any big panel art, keep the cat (and
# anything attached or close to it, like a muzzle flash), erase the perch tile, scale down, and place the
# frame in a fixed-size atlas cell so the spot where the perch was (the ground under the cat) lands on the
# same pixel in every frame. Output: games/catdrop/art/<out>.png, 4 columns x 2 rows, in sheet order.
# Sources live in art_src/ (ignored by Godot's importer).
#   macho:     1 idle, 2 wind-up, 3 lunge, 4 claw swipe, 5 furious bite, 6 impact, 7 retreat, 8 landing
#   rosette:   1 idle, 2 aiming, 3 the shot, 4 recoil, 5 bolt pull, 6 bolt push, 7 target lock, 8 return to idle
#   macho_run: 1 start, 2 front push, 3 extension, 4 front strike, 5 drive, 6 mid-stride, 7 high-speed leap, 8 landing
#   adora:     1 idle, 2 crouch and leap, 3 mid-air spin, 4 acrobatic slash, 5 aerial kick, 6 agile landing, 7 backflip, 8 return to idle
#
# bg "grey": a flat grey background that the black outline walls off from the fur (flood from the border).
# bg "red": a dark red grunge background; the flood also crosses the big panel's border line (erased by hand).

const SHEETS := {
	"macho": {
		"file": "res://art_src/macho_attack_sheet.webp", "out": "macho_anim", "bg": "grey",
		"label_bands": [Vector2i(16, 72), Vector2i(258, 314), Vector2i(502, 563), Vector2i(742, 802)],
		"row_splits": [264, 520, 762], "col_split": 343, "min_x": 0, "border_x": -1,
		# frames where effects or the tail hide the perch: its centre by hand, in sheet pixels, by frame index
		"anchors": {3: Vector2(460.0, 467.0), 7: Vector2(503.0, 962.0)},
	},
	"rosette": {
		"file": "res://art_src/rosette_attack_sheet.webp", "out": "rosette_anim", "bg": "grey",
		"label_bands": [Vector2i(16, 72), Vector2i(258, 314), Vector2i(502, 563), Vector2i(742, 802)],
		"row_splits": [264, 520, 762], "col_split": 343, "min_x": 0, "border_x": -1, "anchors": {},
	},
	"macho_run": {
		"file": "res://art_src/macho_run_sheet.webp", "out": "macho_run_anim", "bg": "red",
		"label_bands": [Vector2i(30, 94), Vector2i(236, 264), Vector2i(478, 508), Vector2i(714, 744), Vector2i(974, 1008)],
		"row_splits": [268, 508, 748], "col_split": 488, "min_x": 300, "max_x": 668, "border_x": 339, "anchors": {},
	},
	"adora": {
		"file": "res://art_src/adora_sheet.webp", "out": "adora_anim", "bg": "red",
		"label_bands": [Vector2i(236, 264), Vector2i(478, 508), Vector2i(714, 744), Vector2i(974, 1008)],
		"row_splits": [268, 508, 748], "col_split": 488, "min_x": 345, "max_x": 668, "border_x": 345, "anchors": {},
	},
}
const CELL := Vector2i(192, 112)
const ANCHOR := Vector2i(80, 84)     # where the ground point sits in every cell
const SCALE := 0.32
const COLS := 4

var cfg: Dictionary


func lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


func is_bg(c: Color) -> bool:
	if cfg["bg"] == "grey":
		return absf(c.r - 0.23) < 0.05 and absf(c.g - 0.23) < 0.05 and absf(c.b - 0.23) < 0.05
	# red grunge: strongly red and dark, never grey, white, black or yellow
	return c.r > 0.035 and c.r > 3.0 * c.g and c.r > 3.0 * c.b and c.r < 0.45


# The perch outline colour: a warm yellow-orange, including its darker anti-aliased edge. Tuned by ratios
# so fur (more orange), eyes (more yellow), cream bellies and blood (red) do not match.
func is_perch(c: Color) -> bool:
	if c.a < 0.5 or c.r < (0.5 if cfg["bg"] == "grey" else 0.25):
		return false
	var gr := c.g / c.r
	return gr >= 0.70 and gr <= 0.92 and c.b / c.r < 0.55


# A piece whose average colour is red is background grunge, not part of a cat (red sheets only).
func is_grunge(c: Dictionary, img: Image) -> bool:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	var px: Array = c["pixels"]
	for i in range(0, px.size(), 5):
		sum += img.get_pixelv(px[i])
		n += 1
	if n == 0:
		return false
	var m := sum / float(n)
	return m.r > 2.0 * m.g and m.r > 2.0 * m.b


func components(mask: PackedByteArray, w: int, h: int) -> Array:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var out: Array = []
	for y in h:
		for x in w:
			if mask[y * w + x] == 0 or seen[y * w + x] == 1:
				continue
			var px: Array[Vector2i] = []
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			seen[y * w + x] = 1
			var r := Rect2i(x, y, 1, 1)
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				px.append(p)
				r = r.expand(p)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = p + d
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and mask[q.y * w + q.x] == 1 and seen[q.y * w + q.x] == 0:
						seen[q.y * w + q.x] = 1
						stack.append(q)
			r.size += Vector2i.ONE
			out.append({"pixels": px, "rect": r})
	return out


func cell_of(r: Rect2i) -> int:
	var c := r.get_center()
	var row := 0
	for s in cfg["row_splits"]:
		if c.y >= s:
			row += 1
	return row * 2 + (0 if c.x < int(cfg["col_split"]) else 1)


func in_label_band(r: Rect2i) -> bool:
	for b in cfg["label_bands"]:
		if r.position.y >= b.x and r.end.y <= b.y:
			return true
	return false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var name: String = args[0] if args.size() > 0 else "macho"
	if not SHEETS.has(name):
		push_error("unknown sheet " + name)
		quit(1)
		return
	cfg = SHEETS[name]
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(cfg["file"])) != OK:
		push_error("cannot load " + str(cfg["file"]))
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()

	# 1. background = bg-coloured pixels connected to the border. Only those count: the cat's fur can be
	# nearly the same colour, but its outline walls it off.
	var outside := PackedByteArray()
	outside.resize(w * h)
	# a panel border line (a dark vertical stripe) is erased so the flood can cross it
	var border_cols := {}
	if int(cfg["border_x"]) >= 0:
		for x in range(int(cfg["border_x"]) - 14, int(cfg["border_x"]) + 14):
			var dark := 0
			for y in range(30, h - 30):
				if lum(img.get_pixel(x, y)) < 0.10:
					dark += 1
			if float(dark) > 0.6 * float(h - 60):
				border_cols[x] = true
	var flood: Array[Vector2i] = []
	for x in w:
		flood.append(Vector2i(x, 0))
		flood.append(Vector2i(x, h - 1))
	for y in h:
		flood.append(Vector2i(0, y))
		flood.append(Vector2i(w - 1, y))
	while not flood.is_empty():
		var p: Vector2i = flood.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or outside[p.y * w + p.x] == 1:
			continue
		if not (is_bg(img.get_pixelv(p)) or border_cols.has(p.x) or p.x >= int(cfg.get("max_x", 99999))):
			continue
		outside[p.y * w + p.x] = 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			flood.append(p + d)
	var solid := PackedByteArray()
	solid.resize(w * h)
	for i in w * h:
		solid[i] = 1 - outside[i]

	# 2. pieces: drop label text and panel art, group the rest by cell
	var per_cell: Array = []
	for n in 8:
		per_cell.append([])
	for c in components(solid, w, h):
		var r: Rect2i = c["rect"]
		if in_label_band(r) or c["pixels"].size() < 12 or r.get_center().x < int(cfg["min_x"]) or r.size.x > 260:
			continue
		if cfg["bg"] == "red" and is_grunge(c, img):
			continue
		# thin long pieces are panel border lines, not cats
		if maxi(r.size.x, r.size.y) >= 180 and float(c["pixels"].size()) < 0.12 * float(r.size.x * r.size.y):
			continue
		per_cell[cell_of(r)].append(c)

	var rows := 2
	var atlas := Image.create(CELL.x * COLS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	for n in 8:
		var comps: Array = per_cell[n]
		if comps.is_empty():
			push_error("frame %d has no pixels" % (n + 1))
			continue
		var main: Dictionary = comps[0]
		for c in comps:
			if c["pixels"].size() > main["pixels"].size():
				main = c
		var keep_rect: Rect2i = (main["rect"] as Rect2i).grow(30 if cfg["bg"] == "grey" else 8)
		var bounds: Rect2i = main["rect"]
		var kept: Array = []
		for c in comps:
			if c == main or keep_rect.intersects(c["rect"]):
				kept.append(c)
				bounds = bounds.merge(c["rect"])
		var fw := bounds.size.x
		var fh := bounds.size.y
		var frame := Image.create(fw, fh, false, Image.FORMAT_RGBA8)
		for c in kept:
			for p in c["pixels"]:
				frame.set_pixel(p.x - bounds.position.x, p.y - bounds.position.y, img.get_pixelv(p))

		# 3. the perch: find the outline, remember its centre, erase outline, fringe and dark fill
		var perch_mask := PackedByteArray()
		perch_mask.resize(fw * fh)
		for y in fh:
			for x in fw:
				perch_mask[y * fw + x] = 1 if is_perch(frame.get_pixel(x, y)) else 0
		var perch: Array[Vector2] = []
		var perch_px: Array[Vector2i] = []
		for c in components(perch_mask, fw, fh):
			# the perch is a wide shape at the bottom of the frame (a muzzle flash or fur patch is not)
			var cr: Rect2i = c["rect"]
			var cy := float(cr.get_center().y)
			if c["pixels"].size() >= 150 and float(cr.size.x) >= 0.3 * float(fw) and cy > 0.6 * float(fh):
				for p in c["pixels"]:
					perch.append(Vector2(p))
					perch_px.append(p)
		var anchor := Vector2(fw * 0.5, fh * 0.88)
		if not perch.is_empty():
			var hull := Geometry2D.convex_hull(PackedVector2Array(perch))
			# The centre of the perch's bounding box. (A centroid drifts when the cat or its tail hides part of it.)
			var hb := Rect2(hull[0], Vector2.ZERO)
			for hp in hull:
				hb = hb.expand(hp)
			anchor = Vector2(hb.get_center().x, hb.end.y - 0.22 * hb.size.x)
			# "cat" pixels: not very dark and not perch-coloured
			var cat := PackedByteArray()
			cat.resize(fw * fh)
			for y in fh:
				for x in fw:
					var c := frame.get_pixel(x, y)
					cat[y * fw + x] = 1 if c.a > 0.5 and lum(c) > 0.12 and not is_perch(c) else 0
			# erase the outline plus a 2px fringe of anti-aliased edge pixels around it
			for p in perch_px:
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var q := p + Vector2i(dx, dy)
						if q.x >= 0 and q.y >= 0 and q.x < fw and q.y < fh:
							frame.set_pixelv(q, Color(0, 0, 0, 0))
							cat[q.y * fw + q.x] = 0
			# erase the dark tile fill inside the outline, but keep dark outline pixels hugging the cat
			for y in fh:
				for x in fw:
					var c := frame.get_pixel(x, y)
					var reddish: bool = cfg["bg"] == "red" and c.r > 2.0 * c.g and c.r > 2.0 * c.b
					if c.a < 0.5 or (lum(c) > 0.12 and not reddish) or not Geometry2D.is_point_in_polygon(Vector2(x, y), hull):
						continue
					var near_cat := false
					for dy in range(-2, 3):
						for dx in range(-2, 3):
							var qx := x + dx
							var qy := y + dy
							if qx >= 0 and qy >= 0 and qx < fw and qy < fh and cat[qy * fw + qx] == 1:
								near_cat = true
					if not near_cat:
						frame.set_pixel(x, y, Color(0, 0, 0, 0))
		if cfg["anchors"].has(n):
			anchor = cfg["anchors"][n] - Vector2(bounds.position)

		# 4. scale and place so the perch centre lands on ANCHOR
		frame.resize(int(round(fw * SCALE)), int(round(fh * SCALE)), Image.INTERPOLATE_LANCZOS)
		var origin := Vector2i((n % COLS) * CELL.x, (n / COLS) * CELL.y)
		var dst := ANCHOR - Vector2i(anchor * SCALE)
		var placed := Rect2i(dst, frame.get_size())
		if not Rect2i(Vector2i.ZERO, CELL).encloses(placed):
			print("WARNING frame ", n + 1, " does not fit its cell: ", placed)
		var sub := Image.create(CELL.x, CELL.y, false, Image.FORMAT_RGBA8)
		sub.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), dst)
		atlas.blend_rect(sub, Rect2i(Vector2i.ZERO, CELL), origin)
		print("frame ", n + 1, " pieces ", kept.size(), " sheet anchor ", anchor + Vector2(bounds.position), " placed ", placed)
	var out := "res://games/catdrop/art/%s.png" % cfg["out"]
	atlas.save_png(ProjectSettings.globalize_path(out))
	print("saved ", out, " ", atlas.get_size())
	quit()
