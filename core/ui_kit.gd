class_name UIKit
extends RefCounted
# Shared look for every screen: a deep plum arcade theme with gold currency, hot magenta highlights and cyan
# accents; thick ink outlines, gradient pill buttons that press down, layered shadows with inner strokes,
# heavy outlined text with a drop shadow, and a few drawn icons.
# Colours here are for the shared chrome; each game keeps its own accents on top.

const INK := Color("#0B0B0E")
const INK_SOFT := Color("#1A141F")           # near-black with a plum tint, for pills and panels
const PLUM := Color("#1E121F")                # the base background
const PLUM_LIGHT := Color("#35203A")
const CHARCOAL := Color("#2A1B2D")            # soft plum charcoal panels
const CHARCOAL_LIGHT := Color("#40294A")
const CRIMSON := Color("#6B1D3F")             # burgundy accent (portrait frames, cards)
const CRIMSON_DARK := Color("#1E121F")        # kept for old callers: the base plum
const CRIMSON_LIGHT := Color("#35203A")
const PINK := Color("#FF2E93")                # hot magenta highlights
const MAGENTA := Color("#FF2E93")
const GOLD := Color("#FFD700")                # currency
const AMBER := Color("#F2A81D")               # button base gold
const AMBER_DARK := Color("#B7770B")
const CYAN := Color("#27E1F2")
const CREAM := Color("#FFFFFF")               # crisp white headers
const MUTED := Color("#D0C2D3")                # secondary / body text
const GRAY := Color("#6B5C6E")                 # disabled grey
const PANEL_BORDER := Color("#412945")
const GREEN := Color("#5BD66B")
const GREEN_DARK := Color("#2E9A3E")

static var _heavy: Font
static var _body: Font
static var _boxes := {}
static var _pills := {}


# Heading and number font: Fredoka (SIL OFL, fonts/Fredoka.ttf) at bold weight; falls back to Godot's default
# font with extra weight if the file is missing.
static func heavy() -> Font:
	if _heavy == null:
		var fv := FontVariation.new()
		if ResourceLoader.exists("res://fonts/Fredoka.ttf"):
			fv.base_font = load("res://fonts/Fredoka.ttf")
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650}
		else:
			fv.base_font = ThemeDB.fallback_font
			fv.variation_embolden = 0.9
		_heavy = fv
	return _heavy


# Body text font: Inter (SIL OFL, fonts/Inter.ttf) at medium weight, with the same fallback.
static func body() -> Font:
	if _body == null:
		if ResourceLoader.exists("res://fonts/Inter.ttf"):
			var fv := FontVariation.new()
			fv.base_font = load("res://fonts/Inter.ttf")
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
			_body = fv
		else:
			_body = ThemeDB.fallback_font
	return _body


# A cached outlined rounded flat box. `lip` adds extra bottom border; `shadow` adds a soft drop shadow
# (useful for Panel nodes; draw-time panels use panel() which layers its own shadows).
static func box(fill: Color, border: Color = INK, bw: int = 4, radius: int = 14, lip: int = 0, shadow: int = 0) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d|%d|%d" % [fill.to_html(), border.to_html(), bw, radius, lip, shadow]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.border_width_bottom = bw + lip
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if shadow > 0:
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0.0, float(shadow) * 0.5)
	_boxes[key] = sb
	return sb


# A rounded 9-slice box with a vertical gradient fill, an outline, a bright top edge and a darker bottom
# lip, generated once per colour set. This is what gives buttons and cards their tactile arcade look.
static func pill(top: Color, bottom: Color, border: Color = INK, radius: int = 16, lip: int = 5) -> StyleBoxTexture:
	var key := "%s|%s|%s|%d|%d" % [top.to_html(), bottom.to_html(), border.to_html(), radius, lip]
	if _pills.has(key):
		return _pills[key]
	var size := radius * 2 + 8
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var body_h := float(size - lip)
	var bw := 3.5
	var lip_col := border.lerp(bottom, 0.35).darkened(0.25)
	for y in size:
		for x in size:
			var d_main := _rounded_dist(Vector2(float(x) + 0.5, float(y) + 0.5), Vector2(float(size), body_h), float(radius))
			var d_lip := _rounded_dist(Vector2(float(x) + 0.5, float(y) + 0.5 - float(lip)), Vector2(float(size), body_h), float(radius))
			var col := Color(0, 0, 0, 0)
			if d_lip < 0.5:
				col = Color(lip_col, clampf(0.5 - d_lip, 0.0, 1.0))
			if d_main < 0.5:
				var a := clampf(0.5 - d_main, 0.0, 1.0)
				var inner := -d_main                       # depth inside the shape
				var fill := top.lerp(bottom, clampf(float(y) / body_h, 0.0, 1.0))
				if inner < bw:
					fill = border
				elif inner < bw + 2.0 and float(y) < body_h * 0.45:
					fill = fill.lightened(0.28)           # bright inner edge along the top
				col = col.lerp(Color(fill, 1.0), a) if col.a > 0.0 else Color(fill, a)
				col.a = maxf(col.a, a)
			img.set_pixel(x, y, col)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_texture_margin(side, float(radius))
	sb.content_margin_left = float(radius) * 0.5
	sb.content_margin_right = float(radius) * 0.5
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = float(lip)
	_pills[key] = sb
	return sb


# Signed distance to a rounded rectangle at the origin (negative inside).
static func _rounded_dist(p: Vector2, rect_size: Vector2, r: float) -> float:
	var q := (p - rect_size * 0.5).abs() - (rect_size * 0.5 - Vector2(r, r))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


# Gradient pill button: heavy font, thick outline, raised lip, and it dips a few pixels when pressed.
static func style_button(btn: Button, fill: Color, text_col: Color, font_size: int, outline_text: bool = false) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", heavy())
	btn.add_theme_font_size_override("font_size", font_size)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(c, text_col)
	btn.add_theme_color_override("font_disabled_color", GRAY)
	if outline_text:
		btn.add_theme_color_override("font_outline_color", INK)
		btn.add_theme_constant_override("outline_size", 6)
	var r := 14
	if btn.size.y > 1.0:
		r = clampi(int(btn.size.y * 0.5), 8, 26)
	var lip := 5 if btn.size.y >= 34.0 else 3
	btn.add_theme_stylebox_override("normal", pill(fill.lightened(0.28), fill.darkened(0.12), INK, r, lip))
	btn.add_theme_stylebox_override("hover", pill(fill.lightened(0.38), fill.lightened(0.0), INK, r, lip))
	btn.add_theme_stylebox_override("pressed", pill(fill.darkened(0.05), fill.darkened(0.22), INK, r, 1))
	btn.add_theme_stylebox_override("disabled", pill(CHARCOAL_LIGHT, CHARCOAL, INK, r, 2))
	attach_press(btn)


# Pressing dips the button 2px and scales it to 95% over 80ms; releasing springs it back (back-out ease).
static func attach_press(btn: Button, depth: float = 2.0) -> void:
	if btn.has_meta("press_attached"):
		return
	btn.set_meta("press_attached", true)
	btn.button_down.connect(func():
		if btn.has_meta("pressed_by") or not btn.is_inside_tree():
			return
		btn.set_meta("pressed_by", depth)
		btn.pivot_offset = btn.size * 0.5
		btn.position.y += depth
		btn.create_tween().tween_property(btn, "scale", Vector2(0.95, 0.95), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
	btn.button_up.connect(func():
		if not btn.has_meta("pressed_by"):
			return
		btn.position.y -= float(btn.get_meta("pressed_by"))
		btn.remove_meta("pressed_by")
		if btn.is_inside_tree():
			btn.create_tween().tween_property(btn, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


# A panel pops in: scale from `from_scale` to 1 with a back-out overshoot while fading in (250ms).
static func pop_in(n: Control, from_scale: float = 0.0, dur: float = 0.25) -> void:
	if not n.is_inside_tree():
		return
	n.pivot_offset = n.size * 0.5
	n.scale = Vector2.ONE * from_scale
	n.modulate.a = 0.0
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "modulate:a", 1.0, dur * 0.6)


# Elastic ease-out for t in 0..1 (overshoots and settles).
static func elastic_out(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	return pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * (TAU / 3.0)) + 1.0


# Heavy outlined text with a soft drop shadow, drawn on any CanvasItem.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, fill: Color = CREAM, outline: Color = INK, outline_w: int = 6, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := heavy()
	if outline_w > 0:
		var sh := Color(0.0, 0.0, 0.0, 0.40 * fill.a)
		ci.draw_string_outline(f, pos + Vector2(0.0, 3.0), s, align as HorizontalAlignment, width, size, outline_w, sh)
		ci.draw_string_outline(f, pos, s, align as HorizontalAlignment, width, size, outline_w, outline)
	ci.draw_string(f, pos, s, align as HorizontalAlignment, width, size, fill)


# Heavy outlined text centred vertically in `rect` by cap height, so capitals and digits look centred in
# their box (align: HORIZONTAL_ALIGNMENT_LEFT / CENTER / RIGHT within rect.size.x).
static func text_in(ci: CanvasItem, rect: Rect2, s: String, size: int, fill: Color = CREAM, outline: Color = INK, outline_w: int = 6, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	text(ci, Vector2(rect.position.x, rect.get_center().y + float(size) * 0.36), s, size, fill, outline, outline_w, align, rect.size.x)


# Plain (regular weight) text centred vertically in `rect`.
static func body_in(ci: CanvasItem, rect: Rect2, s: String, size: int, col: Color = CREAM, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	ci.draw_string(body(), Vector2(rect.position.x, rect.get_center().y + float(size) * 0.36), s, align as HorizontalAlignment, rect.size.x, size, col)


# A Label with an explicit box: text is centred vertically in it (never positioned by eye).
static func label(parent: Node, rect: Rect2, s: String, size: int, col: Color = CREAM, align: int = HORIZONTAL_ALIGNMENT_LEFT, heavy_font: bool = true) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if not heavy_font:
		l.add_theme_font_override("font", body())
	if heavy_font:
		l.add_theme_font_override("font", heavy())
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", 5 if size >= 22 else 4)
	l.horizontal_alignment = align as HorizontalAlignment
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.position = rect.position
	l.size = rect.size
	return l


# A flat outlined rounded panel (kept for small chips and badges).
static func panel(ci: CanvasItem, rect: Rect2, fill: Color, border: Color = INK, bw: int = 4, radius: int = 14, lip: int = 0) -> void:
	ci.draw_style_box(box(fill, border, bw, radius, lip), rect)


# A floating card: layered soft shadows, a gradient body with an outline, and a faint inner stroke.
static func card(ci: CanvasItem, rect: Rect2, top: Color = CHARCOAL_LIGHT, bottom: Color = CHARCOAL, border: Color = INK, radius: int = 16, accent: Color = Color(1, 1, 1, 0.14)) -> void:
	for i in 3:
		var grow := float(3 - i) * 2.0
		ci.draw_style_box(box(Color(0, 0, 0, 0.10 + 0.07 * float(i)), Color(0, 0, 0, 0), 0, radius + int(grow)), Rect2(rect.position + Vector2(0.0, 4.0 - float(i)), rect.size).grow(grow))
	ci.draw_style_box(pill(top, bottom, border, radius, 4), rect)
	ci.draw_style_box(box(Color(0, 0, 0, 0), accent, 2, maxi(radius - 5, 4)), rect.grow(-6.0))


# A glowing neon outline (several translucent strokes, then a crisp one).
static func glow_rect(ci: CanvasItem, rect: Rect2, col: Color, radius: int = 12, strength: float = 1.0) -> void:
	for i in 4:
		var g := float(4 - i) * 2.5
		ci.draw_style_box(box(Color(0, 0, 0, 0), Color(col, 0.07 * strength * float(i + 1)), 3, radius + int(g)), rect.grow(g))
	ci.draw_style_box(box(Color(0, 0, 0, 0), col, 3, radius), rect)


# Small L-shaped brackets in each corner of a rect (tactical grid accents).
static func corner_accents(ci: CanvasItem, rect: Rect2, col: Color, len: float = 9.0, width: float = 2.5) -> void:
	var p := rect.position
	var e := rect.end
	for c in [[p, Vector2(1, 0), Vector2(0, 1)], [Vector2(e.x, p.y), Vector2(-1, 0), Vector2(0, 1)], [Vector2(p.x, e.y), Vector2(1, 0), Vector2(0, -1)], [e, Vector2(-1, 0), Vector2(0, -1)]]:
		var o: Vector2 = c[0]
		ci.draw_line(o, o + (c[1] as Vector2) * len, col, width)
		ci.draw_line(o, o + (c[2] as Vector2) * len, col, width)


# The play-field frame: soft shadow, a dark metallic bezel, a pulsing neon stroke, and a dark inner field.
static func board_frame(ci: CanvasItem, field: Rect2, glow_col: Color, t: float) -> void:
	var outer := field.grow(10.0)
	for i in 3:
		ci.draw_style_box(box(Color(0, 0, 0, 0.10 + 0.07 * float(i)), Color(0, 0, 0, 0), 0, 22), Rect2(outer.position + Vector2(0.0, 9.0 - 2.0 * float(i)), outer.size).grow(7.0 - 2.0 * float(i)))
	ci.draw_style_box(pill(Color("#5A506A"), Color("#1A141F"), INK, 20, 4), outer)
	glow_rect(ci, field.grow(3.0), glow_col, 12, 0.85 + 0.15 * sin(t * 2.2))
	ci.draw_style_box(box(Color("#1B1322"), Color(0, 0, 0, 0), 0, 10), field)
	ci.draw_style_box(box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.06), 2, 8), field.grow(-3.0))


# --- Icons (drawn, centred on c) ---------------------------------------------

static func star(ci: CanvasItem, c: Vector2, r: float, fill: Color = GOLD) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rad := r if i % 2 == 0 else r * 0.45
		var a := -PI / 2.0 + float(i) * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	ci.draw_colored_polygon(pts, fill)
	ci.draw_polyline(outline, INK, maxf(2.0, r * 0.18), true)


static func coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, INK)
	ci.draw_circle(c, r - 2.0, GOLD)
	ci.draw_circle(c, r * 0.62, Color("#E0A800"))
	ci.draw_circle(c, r * 0.5, Color("#FFE866"))
	ci.draw_circle(c + Vector2(-r * 0.2, -r * 0.25), r * 0.16, Color(1, 1, 1, 0.8))


static func arrow_up(ci: CanvasItem, c: Vector2, s: float, fill: Color = GREEN) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0.0, -s), c + Vector2(s, 0.0), c + Vector2(s * 0.45, 0.0), c + Vector2(s * 0.45, s),
		c + Vector2(-s * 0.45, s), c + Vector2(-s * 0.45, 0.0), c + Vector2(-s, 0.0),
	])
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	ci.draw_colored_polygon(pts, fill)
	ci.draw_polyline(outline, INK, 3.0, true)


# A polished padlock: metal shackle, two-tone body with a highlight, and a keyhole.
static func lock(ci: CanvasItem, c: Vector2, s: float, fill: Color = MUTED) -> void:
	ci.draw_arc(c + Vector2(0.0, -s * 0.1), s * 0.55, PI, TAU, 18, INK, s * 0.4)
	ci.draw_arc(c + Vector2(0.0, -s * 0.1), s * 0.55, PI, TAU, 18, Color("#D8D2E0"), s * 0.2)
	ci.draw_line(c + Vector2(-s * 0.55, -s * 0.1), c + Vector2(-s * 0.55, s * 0.15), INK, s * 0.4)
	ci.draw_line(c + Vector2(s * 0.55, -s * 0.1), c + Vector2(s * 0.55, s * 0.15), INK, s * 0.4)
	ci.draw_line(c + Vector2(-s * 0.55, -s * 0.1), c + Vector2(-s * 0.55, s * 0.15), Color("#D8D2E0"), s * 0.2)
	ci.draw_line(c + Vector2(s * 0.55, -s * 0.1), c + Vector2(s * 0.55, s * 0.15), Color("#D8D2E0"), s * 0.2)
	var body := Rect2(c + Vector2(-s * 0.85, -s * 0.05), Vector2(s * 1.7, s * 1.35))
	ci.draw_style_box(pill(fill.lightened(0.3), fill.darkened(0.25), INK, int(s * 0.3), 2), body)
	ci.draw_circle(c + Vector2(0.0, s * 0.5), s * 0.22, INK)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.08, s * 0.5), Vector2(s * 0.16, s * 0.4)), INK)


static func paw(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(0.0, s * 0.35), s * 0.55, col)
	for p in [Vector2(-0.75, -0.2), Vector2(-0.28, -0.7), Vector2(0.28, -0.7), Vector2(0.75, -0.2)]:
		ci.draw_circle(c + p * s, s * 0.26, col)


static func crown(ci: CanvasItem, c: Vector2, s: float, fill: Color = GOLD) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-s, s * 0.6), c + Vector2(-s, -s * 0.5), c + Vector2(-s * 0.5, 0.0), c + Vector2(0.0, -s * 0.8),
		c + Vector2(s * 0.5, 0.0), c + Vector2(s, -s * 0.5), c + Vector2(s, s * 0.6),
	])
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	ci.draw_colored_polygon(pts, fill)
	ci.draw_polyline(outline, INK, 3.0, true)


# A vertical two-colour gradient filling `rect`.
static func gradient(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	ci.draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))
