extends SceneTree
# Bakes the UI kit: buttons, panels and icons rendered from a height map with real lighting (bevel, soft gloss,
# ambient occlusion, rim light, one light direction) into 9-slice PNGs under art/ui/, plus manifest.json.
# Not needed at game time. Run: GODOT --headless --path . --script tools/bake_ui.gd
# `UIKit` loads these when present and falls back to its code-generated pills otherwise.

const OUT_DIR := "res://art/ui"
const INK := Color("#0B0B0E")
# light from the top-left, in front of the surface
const LIGHT := Vector3(-0.35, -0.75, 0.55)

# colour sets for buttons: face top, face bottom
const BUTTONS := {
	"gold": [Color("#FFE24D"), Color("#E0A800")],
	"cyan": [Color("#6AF7FF"), Color("#0AA6C9")],
	"green": [Color("#7BE06E"), Color("#2E9A3E")],
	"magenta": [Color("#FF5DB0"), Color("#C4146E")],
	"steel": [Color("#4A3F55"), Color("#241B2B")],
	"grey": [Color("#7A6E80"), Color("#463D4D")],
}
# size classes: texture size, corner radius, lip, bevel width
const SIZES := {
	"big": {"size": 84, "r": 26.0, "lip": 6.0, "bevel": 8.0},
	"small": {"size": 40, "r": 11.0, "lip": 3.0, "bevel": 4.0},
}

var manifest := {}


func rr_dist(p: Vector2, size: Vector2, r: float) -> float:
	var q := (p - size * 0.5).abs() - (size * 0.5 - Vector2(r, r))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


func smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# Height of the face surface at p: rises over `bevel` pixels from the face edge, then a flat plateau.
func face_height(p: Vector2, body: Vector2, r: float, bw: float, bevel: float) -> float:
	return smooth(0.0, bevel, -rr_dist(p, body, r) - bw)


func shade(p: Vector2, body: Vector2, r: float, bw: float, bevel: float, base: Color, fy: float, gloss: float, rim: float) -> Color:
	var e := 0.75
	var hx := face_height(p + Vector2(e, 0), body, r, bw, bevel) - face_height(p - Vector2(e, 0), body, r, bw, bevel)
	var hy := face_height(p + Vector2(0, e), body, r, bw, bevel) - face_height(p - Vector2(0, e), body, r, bw, bevel)
	var n := Vector3(-hx * bevel * 0.55, -hy * bevel * 0.55, 1.0).normalized()
	var l := LIGHT.normalized()
	var diffuse := maxf(n.dot(l), 0.0)
	var light := 0.66 + 0.5 * diffuse
	var col := Color(base.r * light, base.g * light, base.b * light, 1.0)
	var hv := (l + Vector3(0, 0, 1)).normalized()
	var spec := pow(maxf(n.dot(hv), 0.0), 26.0) * 0.30
	col = Color(col.r + spec, col.g + spec, col.b + spec, 1.0)
	var u := -rr_dist(p, body, r) - bw                  # distance inside the face edge
	# ambient occlusion: the face darkens a little where it meets the outline
	col = col.darkened(0.22 * (1.0 - smooth(0.0, 3.0, u)))
	# soft gloss on the upper part of the face (uniform across the stretchable middle)
	var band := pow(clampf(1.0 - fy / 0.46, 0.0, 1.0), 1.25) * smooth(2.0, 10.0, u) * gloss
	col = col.lerp(Color.WHITE, band)
	# a thin lighter rim along the bottom edge of the face
	if rim > 0.0:
		col = col.lerp(Color.WHITE, rim * smooth(0.65, 0.95, fy) * (1.0 - smooth(0.0, 3.5, u)))
	return col


func bake_button(size_name: String, top: Color, bottom: Color, pressed: bool, disabled: bool) -> Image:
	var cfg: Dictionary = SIZES[size_name]
	var s: int = cfg["size"]
	var r: float = cfg["r"]
	var lip: float = 1.0 if pressed else float(cfg["lip"])
	var bevel: float = cfg["bevel"]
	var bw := 3.5 if size_name == "big" else 2.5
	if pressed:
		top = top.darkened(0.06)
		bottom = bottom.darkened(0.2)
	var body := Vector2(float(s), float(s) - lip)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var lip_col := bottom.darkened(0.55)
	for y in s:
		for x in s:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d_body := rr_dist(p, body, r)
			var d_lip := rr_dist(p - Vector2(0.0, lip), body, r)
			var col := Color(0, 0, 0, 0)
			if d_lip < 0.5:
				var lc := lip_col.lerp(INK, 0.5)
				col = Color(lc, clampf(0.5 - d_lip, 0.0, 1.0))
			if d_body < 0.5:
				var a := clampf(0.5 - d_body, 0.0, 1.0)
				var depth := -d_body
				var c := INK
				if depth >= bw:
					var fy := clampf(p.y / body.y, 0.0, 1.0)
					c = shade(p, body, r, bw, bevel, top.lerp(bottom, fy), fy, 0.0 if pressed else 0.34, 0.35)
				col = col.lerp(Color(c, 1.0), a) if col.a > 0.0 else Color(c, a)
				col.a = maxf(col.a, a)
			img.set_pixel(x, y, col)
	return img


# A card or pill: no lip, a subtle bevel, an outline, a faint inner light stroke and a soft top sheen.
func bake_panel(size: int, r: float, top: Color, bottom: Color, border: Color) -> Image:
	var body := Vector2(float(size), float(size))
	var bw := 3.0
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d := rr_dist(p, body, r)
			if d >= 0.5:
				continue
			var a := clampf(0.5 - d, 0.0, 1.0)
			var depth := -d
			var c := border
			if depth >= bw:
				var fy := clampf(p.y / body.y, 0.0, 1.0)
				c = shade(p, body, r, bw, 5.0, top.lerp(bottom, fy), fy, 0.10, 0.0)
				# faint inner light stroke
				var u := depth - bw
				c = c.lerp(Color.WHITE, 0.16 * (1.0 - smooth(0.0, 1.6, absf(u - 2.5))))
			img.set_pixel(x, y, Color(c, a))
	return img


# A neon tile frame: an outer stroke, a dark gap and a thinner inner stroke, shaded cyan at the top to magenta
# at the bottom, with a transparent middle (drawn over a panel, modulated above 1.0 so it blooms).
func bake_neon_frame(size: int, r: float) -> Image:
	var body := Vector2(float(size), float(size))
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cyan := Color("#27E1F2")
	var magenta := Color("#E040FB")
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d := rr_dist(p, body, r)
			var depth := -d
			var a := 0.0
			if depth >= -0.5 and depth <= 4.5:
				a = clampf(minf(depth + 0.5, 4.5 - depth), 0.0, 1.0)
			elif depth >= 8.0 and depth <= 10.0:
				a = 0.75 * clampf(minf(depth - 7.5, 10.5 - depth), 0.0, 1.0)
			if a <= 0.0:
				continue
			var c := cyan.lerp(magenta, smooth(0.25, 0.8, float(y) / float(size)))
			img.set_pixel(x, y, Color(c, a))
	return img


# A lit gold coin: outline, a raised rim, a recessed face with a small inner ring.
func bake_coin(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(float(size) * 0.5, float(size) * 0.5)
	var rad := float(size) * 0.5 - 1.0
	var l := LIGHT.normalized()
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var dist := p.distance_to(c)
			if dist > rad + 0.5:
				continue
			var a := clampf(rad + 0.5 - dist, 0.0, 1.0)
			var col := INK
			if dist < rad - 2.5:
				# height: raised rim between 0.74r and r-2.5, recessed plate inside, small raised ring at 0.42r
				var t := dist / (rad - 2.5)
				var h := 0.0
				if t > 0.72:
					h = smooth(0.72, 0.8, t) * (1.0 - smooth(0.93, 1.0, t)) + 0.4 * smooth(0.93, 1.0, t)
				h += 0.55 * smooth(0.34, 0.4, t) * (1.0 - smooth(0.42, 0.48, t))
				var dir := (p - c).normalized() if dist > 0.01 else Vector2.ZERO
				var eps := 0.012
				var t2 := (dist + 1.0) / (rad - 2.5)
				var h2 := 0.0
				if t2 > 0.72:
					h2 = smooth(0.72, 0.8, t2) * (1.0 - smooth(0.93, 1.0, t2)) + 0.4 * smooth(0.93, 1.0, t2)
				h2 += 0.55 * smooth(0.34, 0.4, t2) * (1.0 - smooth(0.42, 0.48, t2))
				var slope := (h2 - h) * 10.0
				var n := Vector3(-dir.x * slope, -dir.y * slope, 1.0).normalized()
				var diffuse := maxf(n.dot(l), 0.0)
				var base := Color("#FFE15A").lerp(Color("#E39A00"), clampf((p.y - (c.y - rad)) / (rad * 2.0), 0.0, 1.0))
				var light := 0.62 + 0.55 * diffuse
				col = Color(base.r * light, base.g * light, base.b * light, 1.0)
				var hv := (l + Vector3(0, 0, 1)).normalized()
				col = col.lerp(Color.WHITE, pow(maxf(n.dot(hv), 0.0), 22.0) * 0.5)
				if t > 0.72:
					col = col.lerp(Color("#FFF3A0"), 0.18)
			img.set_pixel(x, y, Color(col, a))
	return img


func save(img: Image, name: String, margin: int) -> void:
	var path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(ProjectSettings.globalize_path(path))
	manifest[name] = {"margin": margin, "size": img.get_width()}
	print("baked ", name)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for key in BUTTONS:
		var cols: Array = BUTTONS[key]
		for size_name in SIZES:
			var m := int(SIZES[size_name]["r"])
			save(bake_button(size_name, cols[0], cols[1], false, false), "btn_%s_%s" % [key, size_name], m)
			save(bake_button(size_name, cols[0], cols[1], true, false), "btn_%s_%s_down" % [key, size_name], m)
	save(bake_panel(64, 18.0, Color("#3A2262"), Color("#22103F"), INK), "panel", 22)
	save(bake_panel(64, 28.0, Color("#40266A"), Color("#1D0F36"), INK), "pill", 28)
	save(bake_panel(64, 14.0, Color("#47296F"), Color("#2A1647"), INK), "card_small", 16)
	save(bake_neon_frame(64, 22.0), "neon_frame", 24)
	save(bake_coin(64), "coin", 0)
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()

	# a contact sheet so the kit can be judged at a glance
	var sheet := Image.create(520, 360, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#1E121F"))
	var x := 12
	for key in BUTTONS:
		var big := load_png("btn_%s_big" % key)
		var down := load_png("btn_%s_big_down" % key)
		sheet.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(x, 12))
		sheet.blend_rect(down, Rect2i(Vector2i.ZERO, down.get_size()), Vector2i(x, 110))
		var small := load_png("btn_%s_small" % key)
		sheet.blend_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(x + 20, 210))
		x += 100
	var panel := load_png("panel")
	sheet.blend_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(12, 280))
	var pill := load_png("pill")
	sheet.blend_rect(pill, Rect2i(Vector2i.ZERO, pill.get_size()), Vector2i(100, 280))
	var coin := load_png("coin")
	sheet.blend_rect(coin, Rect2i(Vector2i.ZERO, coin.get_size()), Vector2i(190, 280))
	sheet.save_png(ProjectSettings.globalize_path("res://art/ui/_contact_sheet.png"))
	quit()


func load_png(name: String) -> Image:
	var img := Image.new()
	img.load(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name]))
	return img
