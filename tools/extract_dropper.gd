extends SceneTree
# Cuts the four launcher-cat poses (idle, release, drop, celebration) out of the owner's Gemini ball-drop
# asset sheet (art_src/ball_drop_assets_sheet.jpg) into games/catdrop/art/dropper_anim.png: 4 cells of CELL,
# each pose centred in its cell and scaled by SCALE. Not needed at game time.
#   GODOT --headless --path . --script tools/extract_dropper.gd
# Frames: 0 idle / watching, 1 release (mouth open), 2 the drop (lunge with the ball and a poof), 3 celebration.

const SRC := "res://art_src/ball_drop_assets_sheet.jpg"
const OUT := "res://games/catdrop/art/dropper_anim.png"
const CELL := Vector2i(112, 96)
const SCALE := 0.55
# crop rectangles on the sheet, with a little margin around each pose, label text excluded
const RECTS := [Rect2i(36, 111, 150, 130), Rect2i(200, 111, 150, 130), Rect2i(338, 108, 160, 132), Rect2i(522, 106, 152, 134)]


func near(a: Color, b: Color, tol: float) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol


func _init() -> void:
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(SRC)) != OK:
		push_error("cannot load " + SRC)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var atlas := Image.create(CELL.x * RECTS.size(), CELL.y, false, Image.FORMAT_RGBA8)
	for n in RECTS.size():
		var cell := img.get_region(RECTS[n])
		var w := cell.get_width()
		var h := cell.get_height()
		var bg := Color("#20232c")
		# background: bg-coloured pixels connected to the crop border (the black outline walls the fur off)
		var outside := PackedByteArray()
		outside.resize(w * h)
		var stack: Array[Vector2i] = []
		for x in w:
			stack.append(Vector2i(x, 0))
			stack.append(Vector2i(x, h - 1))
		for y in h:
			stack.append(Vector2i(0, y))
			stack.append(Vector2i(w - 1, y))
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or outside[p.y * w + p.x] == 1 or not near(cell.get_pixelv(p), bg, 0.08):
				continue
			outside[p.y * w + p.x] = 1
			cell.set_pixelv(p, Color(0, 0, 0, 0))
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				stack.append(p + d)
		# keep only the biggest connected piece and its close neighbours (drops specks and stray label bits)
		var comp := PackedInt32Array()
		comp.resize(w * h)
		var sizes: Array[int] = [0]
		var rects: Array[Rect2i] = [Rect2i()]
		var count := 0
		for y in h:
			for x in w:
				if comp[y * w + x] != 0 or cell.get_pixel(x, y).a < 0.5:
					continue
				count += 1
				var st: Array[Vector2i] = [Vector2i(x, y)]
				comp[y * w + x] = count
				var size := 0
				var r := Rect2i(x, y, 1, 1)
				while not st.is_empty():
					var p: Vector2i = st.pop_back()
					size += 1
					r = r.expand(p)
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var q: Vector2i = p + d
						if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and comp[q.y * w + q.x] == 0 and cell.get_pixel(q.x, q.y).a >= 0.5:
							comp[q.y * w + q.x] = count
							st.append(q)
				sizes.append(size)
				rects.append(r)
		var main := 1
		for i in range(1, count + 1):
			if sizes[i] > sizes[main]:
				main = i
		var keep := rects[main].grow(24)
		var bounds := rects[main]
		var junk := {}   # thin tall pieces are the sheet's border lines, not part of a pose
		for i in range(1, count + 1):
			if i != main and rects[i].size.x <= 6 and rects[i].size.y >= 30:
				junk[i] = true
		for i in range(1, count + 1):
			if not junk.has(i) and (i == main or keep.intersects(rects[i])):
				bounds = bounds.merge(rects[i])
		for y in h:
			for x in w:
				var id := comp[y * w + x]
				if id != 0 and (junk.has(id) or not (id == main or keep.intersects(rects[id]))):
					cell.set_pixel(x, y, Color(0, 0, 0, 0))
		var pose := cell.get_region(Rect2i(bounds.position, bounds.size + Vector2i.ONE))
		pose.resize(int(round(pose.get_width() * SCALE)), int(round(pose.get_height() * SCALE)), Image.INTERPOLATE_LANCZOS)
		var dst := Vector2i(n * CELL.x, 0) + (CELL - pose.get_size()) / 2
		if pose.get_width() > CELL.x or pose.get_height() > CELL.y:
			print("WARNING pose ", n, " does not fit: ", pose.get_size())
		atlas.blend_rect(pose, Rect2i(Vector2i.ZERO, pose.get_size()), dst)
		print("pose ", n, " size ", pose.get_size())
	atlas.save_png(ProjectSettings.globalize_path(OUT))
	print("saved ", OUT, " ", atlas.get_size())
	quit()
