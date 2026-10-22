class_name Fx
extends RefCounted
# Tiny effects layer shared by screens: particle bursts and floating text popups.
# Owner calls update(dt) every frame and draw(canvas_item) from its _draw().

const MAX_PARTICLES := 300
const MAX_POPUPS := 24

var parts: Array = []   # {pos, vel, t, life, col, r, grav}
var pops: Array = []    # {pos, text, t, life, col, size}
var rings: Array = []   # {pos, t, life, col, r0, r1}: expanding shockwave rings


func burst(pos: Vector2, col: Color, n: int = 10, speed: float = 140.0, life: float = 0.5, r: float = 3.0, grav: float = 300.0) -> void:
	for i in n:
		if parts.size() >= MAX_PARTICLES:
			return
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * speed * randf_range(0.4, 1.0)
		parts.append({"pos": pos, "vel": v, "t": 0.0, "life": life * randf_range(0.7, 1.2), "col": col, "r": r * randf_range(0.7, 1.3), "grav": grav})


func popup(pos: Vector2, text: String, col: Color = UIKit.AMBER, size: int = 18, life: float = 0.8, elastic: bool = false) -> void:
	if pops.size() >= MAX_POPUPS:
		pops.pop_front()
	pops.append({"pos": pos, "text": text, "t": 0.0, "life": life, "col": col, "size": size, "elastic": elastic})


func ring(pos: Vector2, col: Color, r0: float = 6.0, r1: float = 40.0, life: float = 0.35) -> void:
	rings.append({"pos": pos, "t": 0.0, "life": life, "col": col, "r0": r0, "r1": r1})


func clear() -> void:
	parts.clear()
	pops.clear()
	rings.clear()


func update(dt: float) -> void:
	for p in parts:
		p["t"] = float(p["t"]) + dt
		p["vel"] = Vector2(p["vel"]) + Vector2(0.0, float(p["grav"])) * dt
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * dt
	parts = parts.filter(func(p): return float(p["t"]) < float(p["life"]))
	for r in rings:
		r["t"] = float(r["t"]) + dt
	rings = rings.filter(func(r): return float(r["t"]) < float(r["life"]))
	for q in pops:
		q["t"] = float(q["t"]) + dt
		q["pos"] = Vector2(q["pos"]) + Vector2(0.0, -34.0) * dt
	pops = pops.filter(func(q): return float(q["t"]) < float(q["life"]))


func draw(ci: CanvasItem) -> void:
	for r in rings:
		var k := float(r["t"]) / float(r["life"])
		var c: Color = r["col"]
		var rad := lerpf(float(r["r0"]), float(r["r1"]), 1.0 - (1.0 - k) * (1.0 - k))
		ci.draw_arc(Vector2(r["pos"]), rad, 0.0, TAU, 28, Color(UIKit.INK, 1.0 - k), 6.0 * (1.0 - k) + 1.0)
		ci.draw_arc(Vector2(r["pos"]), rad, 0.0, TAU, 28, Color(c, 1.0 - k), 3.5 * (1.0 - k) + 0.5)
	for p in parts:
		var k := 1.0 - float(p["t"]) / float(p["life"])
		var c: Color = p["col"]
		ci.draw_circle(Vector2(p["pos"]), float(p["r"]) * (0.4 + 0.6 * k), Color(c, clampf(k * 1.4, 0.0, 1.0)))
	for q in pops:
		if q.get("elastic", false):
			_draw_elastic(ci, q)
			continue
		var k := 1.0 - float(q["t"]) / float(q["life"])
		var c: Color = q["col"]
		var pop := 1.0 + 0.3 * maxf(0.0, 1.0 - float(q["t"]) * 8.0)
		UIKit.text(ci, Vector2(q["pos"]) - Vector2(maxf(80.0, float(q["size"]) * 4.0) * 0.5, 0.0), str(q["text"]), int(float(q["size"]) * pop), Color(c, clampf(k * 2.0, 0.0, 1.0)), Color(UIKit.INK, clampf(k * 2.0, 0.0, 1.0)), 5, HORIZONTAL_ALIGNMENT_CENTER, maxf(80.0, float(q["size"]) * 4.0))


# A celebratory popup: scales 0.2 -> 1.2 with an elastic ease, floats up 40px, then fades out.
func _draw_elastic(ci: CanvasItem, q: Dictionary) -> void:
	var k := float(q["t"]) / float(q["life"])
	var sc := 0.2 + 1.0 * UIKit.elastic_out(minf(k / 0.5, 1.0))
	var lift := 40.0 * (1.0 - pow(1.0 - minf(k, 1.0), 3.0))
	var alpha := 1.0 if k < 0.7 else clampf(1.0 - (k - 0.7) / 0.3, 0.0, 1.0)
	var size: int = int(q["size"])
	var w := float(size) * 6.0
	var c: Color = q["col"]
	ci.draw_set_transform(Vector2(q["pos"]) + Vector2(0.0, -lift), 0.0, Vector2(sc, sc))
	UIKit.text_in(ci, Rect2(-w * 0.5, -float(size) * 0.7, w, float(size) * 1.4), str(q["text"]), size, Color(c, alpha), Color(UIKit.INK, alpha), 7, HORIZONTAL_ALIGNMENT_CENTER)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
