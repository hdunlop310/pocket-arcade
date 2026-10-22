extends SceneTree
# Cuts an AI-generated 8-frame action sheet (2 columns x 4 rows, labels above each frame, flat grey
# background, yellow perch tile under the cat) into a game atlas. Not needed at game time.
#
#   GODOT --headless --path . --script tools/extract_sheet.gd -- macho
#   GODOT --headless --path . --script tools/extract_sheet.gd -- rosette
#
# Per frame: make the grey background transparent, delete the label text, keep the cat (and anything
# attached or close to it, like a muzzle flash), erase the perch tile, scale down, and place the
# frame in a fixed-size atlas cell so the spot where the perch was (the ground under the cat) lands on
# the same pixel in every frame. Output: games/catdrop/art/<name>_anim.png, 4 columns x 2 rows, in
# sheet order. Sources live in art_src/ (ignored by Godot's importer).
#   macho:   1 idle, 2 wind-up, 3 lunge, 4 claw swipe, 5 furious bite, 6 impact, 7 retreat, 8 landing
#   rosette: 1 idle, 2 aiming, 3 the shot, 4 recoil, 5 bolt pull, 6 bolt push, 7 target lock, 8 return to idle

const SHEETS := {
	"macho": "res://art_src/macho_attack_sheet.webp",
	"rosette": "res://art_src/rosette_attack_sheet.webp",
}
const CELL := Vector2i(160, 112)
const ANCHOR := Vector2i(80, 84)     # where the ground point sits in every cell
const SCALE := 0.32
const COLS := 4
# Label rows on the sheet (y ranges); art rows are split halfway between them.
const LABEL_BANDS := [Vector2i(20, 66), Vector2i(262, 308), Vector2i(508, 556), Vector2i(745, 795)]
const ROW_SPLITS := [264, 520, 762]
const COL_SPLIT := 343
# Frames where effects or the tail hide the perch: its centre by hand, in sheet pixels, per sheet.
const ANCHOR_OVERRIDES := {
	"macho": {3: Vector2(460.0, 467.0), 7: Vector2(503.0, 962.0)},
}


func lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


func is_bg(c: Color) -> bool:
	return absf(c.r - 0.23) < 0.05 and absf(c.g - 0.23) < 0.05 and absf(c.b - 0.23) < 0.05


# The perch outline colour: a warm yellow-orange, including its darker anti-aliased edge. Tuned by ratios
# so fur (more orange), eyes (more yellow), cream bellies and blood (red) do not match.
func is_perch(c: Color) -> bool:
	if c.a < 0.5 or c.r < 0.5:
		return false
	var gr := c.g / c.r
	return gr >= 0.70 and gr <= 0.90 and c.b / c.r < 0.5


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
	for s in ROW_SPLITS:
		if c.y >= s:
			row += 1
	return row * 2 + (0 if c.x < COL_SPLIT else 1)


func in_label_band(r: Rect2i) -> bool:
	for b in LABEL_BANDS:
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
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(SHEETS[name])) != OK:
		push_error("cannot load " + SHEETS[name])
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()

	# 1. everything that is not the flat grey background. Only grey connected to the border counts as
	# background: the cat's dark fur is nearly the same grey, but the black outline walls it off.
	var outside := PackedByteArray()
	outside.resize(w * h)
	var flood: Array[Vector2i] = []
	for x in w:
		flood.append(Vector2i(x, 0))
		flood.append(Vector2i(x, h - 1))
	for y in h:
		flood.append(Vector2i(0, y))
		flood.append(Vector2i(w - 1, y))
	while not flood.is_empty():
		var p: Vector2i = flood.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or outside[p.y * w + p.x] == 1 or not is_bg(img.get_pixelv(p)):
			continue
		outside[p.y * w + p.x] = 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			flood.append(p + d)
	var solid := PackedByteArray()
	solid.resize(w * h)
	for i in w * h:
		solid[i] = 1 - outside[i]

	# 2. pieces: drop label text, group the rest by cell
	var per_cell: Array = []
	for n in 8:
		per_cell.append([])
	for c in components(solid, w, h):
		if in_label_band(c["rect"]) or c["pixels"].size() < 12:
			continue
		per_cell[cell_of(c["rect"])].append(c)

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
		var keep_rect: Rect2i = (main["rect"] as Rect2i).grow(30)
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
			if c["pixels"].size() >= 150:
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
					if c.a < 0.5 or lum(c) > 0.12 or not Geometry2D.is_point_in_polygon(Vector2(x, y), hull):
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

		if ANCHOR_OVERRIDES.has(name) and ANCHOR_OVERRIDES[name].has(n):
			anchor = ANCHOR_OVERRIDES[name][n] - Vector2(bounds.position)

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
	var out := "res://games/catdrop/art/%s_anim.png" % name
	atlas.save_png(ProjectSettings.globalize_path(out))
	print("saved ", out, " ", atlas.get_size())
	quit()
