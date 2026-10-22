class_name Fx
extends RefCounted
# Tiny effects layer shared by screens: particle bursts and floating text popups.
# Owner calls update(dt) every frame and draw(canvas_item) from its _draw().

const MAX_PARTICLES := 300
const MAX_POPUPS := 24

var parts: Array = []   # {pos, vel, t, life, col, r, grav}
var pops: Array = []    # {pos, text, t, life, col, size}


func burst(pos: Vector2, col: Color, n: int = 10, speed: float = 140.0, life: float = 0.5, r: float = 3.0, grav: float = 300.0) -> void:
	for i in n:
		if parts.size() >= MAX_PARTICLES:
			return
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * speed * randf_range(0.4, 1.0)
		parts.append({"pos": pos, "vel": v, "t": 0.0, "life": life * randf_range(0.7, 1.2), "col": col, "r": r * randf_range(0.7, 1.3), "grav": grav})


func popup(pos: Vector2, text: String, col: Color = UIKit.AMBER, size: int = 18, life: float = 0.8) -> void:
	if pops.size() >= MAX_POPUPS:
		pops.pop_front()
	pops.append({"pos": pos, "text": text, "t": 0.0, "life": life, "col": col, "size": size})


func clear() -> void:
	parts.clear()
	pops.clear()


func update(dt: float) -> void:
	for p in parts:
		p["t"] = float(p["t"]) + dt
		p["vel"] = Vector2(p["vel"]) + Vector2(0.0, float(p["grav"])) * dt
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * dt
	parts = parts.filter(func(p): return float(p["t"]) < float(p["life"]))
	for q in pops:
		q["t"] = float(q["t"]) + dt
		q["pos"] = Vector2(q["pos"]) + Vector2(0.0, -34.0) * dt
	pops = pops.filter(func(q): return float(q["t"]) < float(q["life"]))


func draw(ci: CanvasItem) -> void:
	for p in parts:
		var k := 1.0 - float(p["t"]) / float(p["life"])
		var c: Color = p["col"]
		ci.draw_circle(Vector2(p["pos"]), float(p["r"]) * (0.4 + 0.6 * k), Color(c, clampf(k * 1.4, 0.0, 1.0)))
	for q in pops:
		var k := 1.0 - float(q["t"]) / float(q["life"])
		var c: Color = q["col"]
		var pop := 1.0 + 0.3 * maxf(0.0, 1.0 - float(q["t"]) * 8.0)
		UIKit.text(ci, Vector2(q["pos"]), str(q["text"]), int(float(q["size"]) * pop), Color(c, clampf(k * 2.0, 0.0, 1.0)), Color(UIKit.INK, clampf(k * 2.0, 0.0, 1.0)), 5, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
