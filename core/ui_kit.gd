class_name UIKit
extends RefCounted
# Shared look for every screen: thick ink outlines, chunky "lip" buttons, heavy outlined text and a few
# drawn icons. Edgy cartoon style: black outlines, flat fills, amber and pink-red accents.
# Colours here are for the shared chrome; each game keeps its own palette on top.

const INK := Color("#0B0B0E")
const INK_SOFT := Color("#16161C")
const CRIMSON := Color("#7E1236")
const CRIMSON_DARK := Color("#4E0A21")
const CRIMSON_LIGHT := Color("#A31A48")
const PINK := Color("#E0285E")
const AMBER := Color("#F2A81D")
const AMBER_DARK := Color("#B7770B")
const CREAM := Color("#F4F4F6")
const MUTED := Color("#A6A6B2")
const GRAY := Color("#33333D")
const GREEN := Color("#5BD66B")
const GREEN_DARK := Color("#2E9A3E")

static var _heavy: FontVariation
static var _boxes := {}


# The default font with extra weight, so headings and buttons read as chunky.
static func heavy() -> Font:
	if _heavy == null:
		_heavy = FontVariation.new()
		_heavy.base_font = ThemeDB.fallback_font
		_heavy.variation_embolden = 0.9
	return _heavy


# A cached outlined rounded box. `lip` adds extra bottom border for the raised-button look.
static func box(fill: Color, border: Color = INK, bw: int = 4, radius: int = 14, lip: int = 0) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d|%d" % [fill.to_html(), border.to_html(), bw, radius, lip]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.border_width_bottom = bw + lip
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	_boxes[key] = sb
	return sb


# Chunky button: heavy font, thick outline, raised lip that flattens when pressed.
static func style_button(btn: Button, fill: Color, text_col: Color, font_size: int, outline_text: bool = false) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", heavy())
	btn.add_theme_font_size_override("font_size", font_size)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(c, text_col)
	btn.add_theme_color_override("font_disabled_color", MUTED)
	if outline_text:
		btn.add_theme_color_override("font_outline_color", INK)
		btn.add_theme_constant_override("outline_size", 6)
	btn.add_theme_stylebox_override("normal", box(fill, INK, 4, 14, 5))
	btn.add_theme_stylebox_override("hover", box(fill.lightened(0.08), INK, 4, 14, 5))
	btn.add_theme_stylebox_override("pressed", box(fill.darkened(0.15), INK, 4, 14, 1))
	btn.add_theme_stylebox_override("disabled", box(GRAY, INK, 4, 14, 2))


# Heavy outlined text drawn on any CanvasItem.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, fill: Color = CREAM, outline: Color = INK, outline_w: int = 6, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := heavy()
	if outline_w > 0:
		ci.draw_string_outline(f, pos, s, align as HorizontalAlignment, width, size, outline_w, outline)
	ci.draw_string(f, pos, s, align as HorizontalAlignment, width, size, fill)


static func panel(ci: CanvasItem, rect: Rect2, fill: Color, border: Color = INK, bw: int = 4, radius: int = 14, lip: int = 0) -> void:
	ci.draw_style_box(box(fill, border, bw, radius, lip), rect)


# --- Icons (drawn, centred on c) ---------------------------------------------

static func star(ci: CanvasItem, c: Vector2, r: float, fill: Color = AMBER) -> void:
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
	ci.draw_circle(c, r - 2.0, AMBER)
	ci.draw_circle(c, r * 0.62, AMBER_DARK)
	ci.draw_circle(c, r * 0.5, Color("#FFD35A"))


static func arrow_up(ci: CanvasItem, c: Vector2, s: float, fill: Color = GREEN) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0.0, -s), c + Vector2(s, 0.0), c + Vector2(s * 0.45, 0.0), c + Vector2(s * 0.45, s),
		c + Vector2(-s * 0.45, s), c + Vector2(-s * 0.45, 0.0), c + Vector2(-s, 0.0),
	])
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	ci.draw_colored_polygon(pts, fill)
	ci.draw_polyline(outline, INK, 3.0, true)


static func lock(ci: CanvasItem, c: Vector2, s: float, fill: Color = MUTED) -> void:
	ci.draw_arc(c + Vector2(0.0, -s * 0.15), s * 0.55, PI, TAU, 16, INK, s * 0.34)
	ci.draw_arc(c + Vector2(0.0, -s * 0.15), s * 0.55, PI, TAU, 16, fill, s * 0.18)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.1), Vector2(s * 1.6, s * 1.3)), INK)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.68, s * 0.02), Vector2(s * 1.36, s * 1.06)), fill)
	ci.draw_circle(c + Vector2(0.0, s * 0.5), s * 0.2, INK)


static func paw(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(0.0, s * 0.35), s * 0.55, col)
	for p in [Vector2(-0.75, -0.2), Vector2(-0.28, -0.7), Vector2(0.28, -0.7), Vector2(0.75, -0.2)]:
		ci.draw_circle(c + p * s, s * 0.26, col)


static func crown(ci: CanvasItem, c: Vector2, s: float, fill: Color = AMBER) -> void:
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
