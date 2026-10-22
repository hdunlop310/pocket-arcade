extends Node2D
# The battle grid. Mice walk down the lane and chew through whatever cat blocks their
# column; cats on the 4x4 grid fight back automatically. Tile types matter:
#   flat   - normal
#   raised - ranged cats shoot further, but any cat there takes 50% more damage
#   hole   - any cat there takes half damage, but ranged cats lose range
# All the fighting maths lives in step(dt) so it can be tested without a screen.

signal wave_cleared(wave: int)
signal run_failed
signal run_won
signal changed

# --- Layout (matches the 390 x 844 viewport) ---------------------------------
const FIELD := Rect2(16.0, 130.0, 358.0, 590.0)
const COLS := 4
const ROWS := 4
const GRID_ORIGIN := Vector2(26.0, 430.0)
const TILE := Vector2(78.0, 64.0)
const STEP := Vector2(86.0, 72.0)
const GRID_BOTTOM := 710.0
const SPAWN_Y := 168.0
const STOP_GAP := 16.0

# Tile type per grid index (row * 4 + column).
const TILE_TYPES := [
	"flat", "hole", "flat", "flat",
	"raised", "flat", "raised", "flat",
	"flat", "hole", "flat", "raised",
	"raised", "flat", "flat", "hole",
]
const RAISED_DAMAGE_TAKEN := 1.5
const HOLE_DAMAGE_TAKEN := 0.5
const RAISED_RANGE_BONUS := 90.0
const HOLE_RANGE_PENALTY := 90.0

# --- Game tuning -------------------------------------------------------------
const MAX_WAVE := 10
const HOUSE_MAX := 100.0
const HOUSE_REGEN := 10.0
const MAX_OWNED := 10
const SPAWN_INTERVAL := 0.8

const CAT_ORDER := ["macho", "rosette"]
const CAT_TYPES := {
	"macho": {"name": "MACHO", "role": "MELEE", "kind": "melee", "hp": 150.0, "dmg": 14.0, "interval": 0.7, "reach": 86.0, "cost": 40.0},
	"rosette": {"name": "ROSETTE", "role": "RANGED", "kind": "ranged", "hp": 50.0, "dmg": 34.0, "interval": 1.5, "range": 300.0, "cost": 60.0},
}
const COST_GROWTH := 1.35

const MOUSE_HP := 30.0
const MOUSE_HP_GROWTH := 0.35
const MOUSE_DPS := 7.0
const MOUSE_DPS_GROWTH := 0.15
const MOUSE_SPEED := 40.0
const MOUSE_HOUSE_DAMAGE := 5.0
const BOSS_HP := 2500.0
const BOSS_DPS := 40.0
const BOSS_SPEED := 22.0
const BOSS_HOUSE_DAMAGE := 30.0

# --- Colours -----------------------------------------------------------------
const COL_FIELD := Color("#101015")
const COL_EDGE := Color("#0B0B0E")
const COL_PEG := Color("#E0285E")
const COL_AMBER := Color("#F2A81D")
const COL_TEXT := Color("#F4F4F6")
const COL_MUTED := Color("#A6A6B2")
const COL_GRAY := Color("#33333D")
const COL_TILE := Color("#16161C")
const COL_MOUSE := Color("#8C8C99")

# --- State -------------------------------------------------------------------
var wave := 1
var house_hp := HOUSE_MAX
var owned := {"macho": 1, "rosette": 0}
var grid: Array = []          # 16 entries: "" or a cat key
var selected := ""
var active := false

var enemies: Array = []
var cats: Array = []          # 16 entries: null or {"key","hp","max","cd","alive"}
var spawn_queue: Array = []
var spawn_timer := 0.0
var tracers: Array = []
var floaters: Array = []
var banner := ""
var banner_t := 0.0

var rng := RandomNumberGenerator.new()
var textures := {}


func _ready() -> void:
	rng.randomize()
	_init_grid()
	for k in CAT_ORDER:
		var path := "res://games/catdrop/art/%s.png" % k
		if ResourceLoader.exists(path):
			textures[k] = load(path)


func _init_grid() -> void:
	if grid.size() != COLS * ROWS:
		grid.clear()
		for i in COLS * ROWS:
			grid.append("")
		grid[0] = "macho"


# ----------------------------------------------------------------------------
# Ownership and placement
# ----------------------------------------------------------------------------

func count_placed(key: String) -> int:
	var n := 0
	for g in grid:
		if g == key:
			n += 1
	return n


func spare(key: String) -> int:
	return int(owned[key]) - count_placed(key)


func any_placed() -> bool:
	for g in grid:
		if g != "":
			return true
	return false


func cat_cost(key: String) -> int:
	return int(round(float(CAT_TYPES[key]["cost"]) * pow(COST_GROWTH, float(owned[key]))))


func can_add_cat(key: String) -> bool:
	return int(owned[key]) < MAX_OWNED


func add_cat(key: String) -> void:
	owned[key] = int(owned[key]) + 1
	if selected == "":
		selected = key
	changed.emit()


func place(i: int, key: String) -> bool:
	if active or i < 0 or i >= grid.size() or grid[i] != "" or spare(key) <= 0:
		return false
	grid[i] = key
	changed.emit()
	return true


func pickup(i: int) -> bool:
	if active or i < 0 or i >= grid.size() or grid[i] == "":
		return false
	selected = grid[i]
	grid[i] = ""
	changed.emit()
	return true


# ----------------------------------------------------------------------------
# Saving
# ----------------------------------------------------------------------------

func save_to(d: Dictionary) -> void:
	d["wave"] = wave
	d["house_hp"] = house_hp
	d["grid"] = grid.duplicate()
	d["owned"] = owned.duplicate()


func load_from(d: Dictionary) -> void:
	_init_grid()
	wave = clampi(int(d.get("wave", 1)), 1, MAX_WAVE)
	house_hp = clampf(float(d.get("house_hp", HOUSE_MAX)), 1.0, HOUSE_MAX)
	var saved_owned: Dictionary = d.get("owned", {})
	for k in CAT_ORDER:
		owned[k] = clampi(int(saved_owned.get(k, owned[k])), 0, MAX_OWNED)
	var saved = d.get("grid", [])
	if saved is Array and saved.size() == COLS * ROWS:
		var counts := {}
		for i in saved.size():
			var key := str(saved[i])
			if key != "" and owned.has(key) and int(counts.get(key, 0)) < int(owned[key]):
				grid[i] = key
				counts[key] = int(counts.get(key, 0)) + 1
			else:
				grid[i] = ""


# ----------------------------------------------------------------------------
# Geometry helpers
# ----------------------------------------------------------------------------

func tile_rect(i: int) -> Rect2:
	var c := i % COLS
	var r := i / COLS
	return Rect2(GRID_ORIGIN + Vector2(float(c) * STEP.x, float(r) * STEP.y), TILE)


func tile_center(i: int) -> Vector2:
	return tile_rect(i).get_center()


func column_x(c: int) -> float:
	return GRID_ORIGIN.x + float(c) * STEP.x + TILE.x * 0.5


func tile_at(p: Vector2) -> int:
	for i in COLS * ROWS:
		if tile_rect(i).has_point(p):
			return i
	return -1


func _chip_rect(slot: int) -> Rect2:
	return Rect2(26.0 + float(slot) * 176.0, 176.0, 166.0, 44.0)


# ----------------------------------------------------------------------------
# Waves
# ----------------------------------------------------------------------------

func _build_queue(w: int) -> Array:
	var q: Array = []
	if w >= MAX_WAVE:
		for i in 10:
			q.append("mouse")
		q.insert(4, "boss")
	else:
		for i in 4 + 3 * (w - 1):
			q.append("mouse")
	return q


func start_wave() -> bool:
	if active or not any_placed():
		return false
	cats.clear()
	for i in COLS * ROWS:
		if grid[i] == "":
			cats.append(null)
		else:
			var key: String = grid[i]
			var hp: float = float(CAT_TYPES[key]["hp"])
			cats.append({"key": key, "hp": hp, "max": hp, "cd": 0.4, "alive": true})
	enemies.clear()
	tracers.clear()
	floaters.clear()
	spawn_queue = _build_queue(wave)
	spawn_timer = 0.5
	banner = ""
	banner_t = 0.0
	active = true
	return true


func _spawn(kind: String) -> void:
	var col := rng.randi_range(0, COLS - 1)
	var e := {
		"kind": kind,
		"col": col,
		"x": column_x(col) + rng.randf_range(-10.0, 10.0),
		"y": SPAWN_Y,
		"dead": false,
	}
	if kind == "boss":
		e["hp"] = BOSS_HP
		e["max"] = BOSS_HP
		e["dps"] = BOSS_DPS
		e["speed"] = BOSS_SPEED
		e["house"] = BOSS_HOUSE_DAMAGE
	else:
		var hp := MOUSE_HP * (1.0 + MOUSE_HP_GROWTH * float(wave - 1))
		e["hp"] = hp
		e["max"] = hp
		e["dps"] = MOUSE_DPS * (1.0 + MOUSE_DPS_GROWTH * float(wave - 1))
		e["speed"] = MOUSE_SPEED
		e["house"] = MOUSE_HOUSE_DAMAGE
	enemies.append(e)


func _tile_damage_mult(i: int) -> float:
	match TILE_TYPES[i]:
		"raised":
			return RAISED_DAMAGE_TAKEN
		"hole":
			return HOLE_DAMAGE_TAKEN
	return 1.0


func cat_range(i: int) -> float:
	var key: String = cats[i]["key"]
	var base: float = float(CAT_TYPES[key].get("range", CAT_TYPES[key].get("reach", 0.0)))
	if CAT_TYPES[key]["kind"] == "ranged":
		match TILE_TYPES[i]:
			"raised":
				base += RAISED_RANGE_BONUS
			"hole":
				base -= HOLE_RANGE_PENALTY
	return base


func _front_cat(col: int) -> int:
	# Index of the top-most living cat in a column, or -1.
	for r in ROWS:
		var i := r * COLS + col
		if cats[i] != null and cats[i]["alive"]:
			return i
	return -1


func _find_target(i: int) -> Dictionary:
	var cat: Dictionary = cats[i]
	var center := tile_center(i)
	var best: Dictionary = {}
	var best_y := -1.0
	var kind: String = CAT_TYPES[cat["key"]]["kind"]
	var reach := cat_range(i)
	for e in enemies:
		if e["dead"]:
			continue
		var ok := false
		if kind == "melee":
			var dy: float = center.y - float(e["y"])
			ok = absf(float(e["x"]) - center.x) < 48.0 and dy >= -20.0 and dy <= reach
		else:
			ok = Vector2(float(e["x"]), float(e["y"])).distance_to(center) <= reach
		if ok and float(e["y"]) > best_y:
			best = e
			best_y = float(e["y"])
	return best


func step(dt: float) -> void:
	if not active:
		return

	# Spawning
	spawn_timer -= dt
	if spawn_timer <= 0.0 and not spawn_queue.is_empty():
		_spawn(spawn_queue.pop_front())
		spawn_timer = SPAWN_INTERVAL

	# Movement, blocking and attacks on cats
	var by_col := {}
	for e in enemies:
		if not by_col.has(e["col"]):
			by_col[e["col"]] = []
		by_col[e["col"]].append(e)
	for col in by_col.keys():
		var list: Array = by_col[col]
		list.sort_custom(func(a, b): return float(a["y"]) > float(b["y"]))
		var front := _front_cat(int(col))
		var limit := GRID_BOTTOM + 6.0
		if front >= 0:
			limit = tile_rect(front).position.y - STOP_GAP
		for idx in list.size():
			var e: Dictionary = list[idx]
			var lim := limit if idx == 0 else float(list[idx - 1]["y"]) - 20.0
			e["y"] = minf(float(e["y"]) + float(e["speed"]) * dt, lim)
			if idx == 0 and float(e["y"]) >= limit - 0.5:
				if front >= 0:
					cats[front]["hp"] = float(cats[front]["hp"]) - float(e["dps"]) * dt * _tile_damage_mult(front)
					if float(cats[front]["hp"]) <= 0.0:
						cats[front]["alive"] = false
				else:
					house_hp -= float(e["house"])
					e["dead"] = true

	# Cats attack
	for i in COLS * ROWS:
		if cats[i] == null or not cats[i]["alive"]:
			continue
		var cat: Dictionary = cats[i]
		cat["cd"] = maxf(float(cat["cd"]) - dt, 0.0)
		if float(cat["cd"]) > 0.0:
			continue
		var target := _find_target(i)
		if target.is_empty():
			continue
		var def: Dictionary = CAT_TYPES[cat["key"]]
		target["hp"] = float(target["hp"]) - float(def["dmg"])
		cat["cd"] = float(def["interval"])
		var from := tile_center(i)
		tracers.append({"from": from, "to": Vector2(float(target["x"]), float(target["y"])), "t": 0.12, "melee": def["kind"] == "melee"})
		floaters.append({"pos": Vector2(float(target["x"]), float(target["y"]) - 14.0), "text": str(int(def["dmg"])), "t": 0.6})
		if float(target["hp"]) <= 0.0:
			target["dead"] = true

	# Clean up
	var alive_enemies: Array = []
	for e in enemies:
		if not e["dead"]:
			alive_enemies.append(e)
	enemies = alive_enemies

	if house_hp <= 0.0:
		_fail()
	elif spawn_queue.is_empty() and enemies.is_empty():
		_clear()


func _fail() -> void:
	active = false
	enemies.clear()
	house_hp = HOUSE_MAX
	wave = 1
	banner = "THE HOUSE FELL\nBack to wave 1. Your cats and upgrades stay."
	banner_t = 4.0
	run_failed.emit()
	changed.emit()


func _clear() -> void:
	active = false
	var cleared := wave
	house_hp = minf(HOUSE_MAX, house_hp + HOUSE_REGEN)
	if cleared >= MAX_WAVE:
		wave = 1
		house_hp = HOUSE_MAX
		banner = "RUN COMPLETE"
		banner_t = 4.0
		wave_cleared.emit(cleared)
		run_won.emit()
	else:
		wave += 1
		banner = "WAVE %d CLEARED" % cleared
		banner_t = 3.0
		wave_cleared.emit(cleared)
	changed.emit()


func set_banner_detail(text: String) -> void:
	banner += "\n" + text
	banner_t = maxf(banner_t, 3.5)


# ----------------------------------------------------------------------------
# Frame update and input
# ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if banner_t > 0.0:
		banner_t -= delta
	for t in tracers:
		t["t"] = float(t["t"]) - delta
	tracers = tracers.filter(func(t): return float(t["t"]) > 0.0)
	for f in floaters:
		f["t"] = float(f["t"]) - delta
		f["pos"] = Vector2(f["pos"]) + Vector2(0.0, -24.0) * delta
	floaters = floaters.filter(func(f): return float(f["t"]) > 0.0)
	if active:
		step(delta)
	if visible:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or active:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = make_input_local(event).position
	# Tray chips
	for s in CAT_ORDER.size():
		if _chip_rect(s).has_point(p):
			var key: String = CAT_ORDER[s]
			selected = "" if selected == key else key
			return
	var i := tile_at(p)
	if i < 0:
		return
	if grid[i] != "":
		pickup(i)
	elif selected != "":
		if not place(i, selected):
			# Out of spares of that type: clear the selection.
			if spare(selected) <= 0:
				selected = ""


# ----------------------------------------------------------------------------
# Drawing
# ----------------------------------------------------------------------------

func _draw_portrait(key: String, rect: Rect2, peek: bool) -> void:
	var tex: Texture2D = textures.get(key)
	if tex == null:
		draw_rect(rect, COL_AMBER)
		return
	if peek:
		var src := Rect2(0.0, 0.0, 256.0, 256.0 * 0.5)
		draw_texture_rect_region(tex, Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.5)), src)
	else:
		draw_texture_rect(tex, rect, false)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(FIELD, COL_FIELD)

	# Lane guides
	for c in COLS:
		var x := column_x(c)
		draw_dashed_line(Vector2(x, 150.0), Vector2(x, GRID_ORIGIN.y - 6.0), Color(1.0, 1.0, 1.0, 0.06), 2.0, 8.0)

	# House bar
	draw_string(font, Vector2(26.0, 156.0), "HOUSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT)
	draw_rect(Rect2(90.0, 144.0, 232.0, 12.0), COL_GRAY)
	draw_rect(Rect2(90.0, 144.0, 232.0 * clampf(house_hp / HOUSE_MAX, 0.0, 1.0), 12.0), COL_PEG)
	draw_string(font, Vector2(330.0, 156.0), str(int(maxf(house_hp, 0.0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT)

	# Tiles and cats
	for i in COLS * ROWS:
		var r := tile_rect(i)
		var kind: String = TILE_TYPES[i]
		var cat = cats[i] if active and cats.size() == COLS * ROWS else null
		var key: String = grid[i]
		match kind:
			"flat":
				draw_rect(r, COL_TILE)
				draw_rect(r, COL_GRAY, false, 2.0)
			"raised":
				draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y), Color("#4A4A58"))
				draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 4.0), Color("#8A8A98"))
				draw_rect(Rect2(r.position.x, r.end.y - 12.0, r.size.x, 12.0), COL_EDGE)
			"hole":
				draw_rect(r, Color("#1B1B23"))
				draw_rect(r, COL_GRAY, false, 2.0)
				draw_rect(Rect2(r.position.x + 8.0, r.position.y + 10.0, r.size.x - 16.0, r.size.y - 16.0), Color.BLACK)
		if key != "":
			var dead: bool = cat != null and not cat["alive"]
			var pr := Rect2(r.position.x + (r.size.x - 44.0) * 0.5, r.position.y + (2.0 if kind == "raised" else 6.0), 44.0, 44.0)
			if kind == "hole":
				var peek := Rect2(r.position.x + 18.0, r.position.y + 24.0, r.size.x - 36.0, 36.0)
				_draw_portrait(key, peek, true)
				draw_rect(Rect2(peek.position.x, peek.position.y, peek.size.x, peek.size.y * 0.5), Color(0.0, 0.0, 0.0, 0.18))
			else:
				draw_rect(pr.grow(2.0), COL_AMBER if not dead else COL_GRAY)
				_draw_portrait(key, pr, false)
				if dead:
					draw_rect(pr, Color(0.0, 0.0, 0.0, 0.6))
			if cat != null and not dead:
				var frac := clampf(float(cat["hp"]) / float(cat["max"]), 0.0, 1.0)
				draw_rect(Rect2(r.position.x + 6.0, r.end.y - (13.0 if kind == "raised" else 8.0), r.size.x - 12.0, 5.0), COL_EDGE)
				draw_rect(Rect2(r.position.x + 6.0, r.end.y - (13.0 if kind == "raised" else 8.0), (r.size.x - 12.0) * frac, 5.0), Color("#6BD66B") if frac > 0.4 else COL_PEG)

	# Enemies
	for e in enemies:
		_draw_enemy(e)

	# Attacks and damage numbers
	for t in tracers:
		var a := float(t["t"]) / 0.12
		draw_line(Vector2(t["from"]), Vector2(t["to"]), Color(COL_AMBER, a), 3.0 if t["melee"] else 2.0)
	for f in floaters:
		draw_string(font, Vector2(f["pos"]), str(f["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(COL_TEXT, clampf(float(f["t"]) / 0.6, 0.0, 1.0)))

	draw_rect(FIELD.grow(3.0), COL_EDGE, false, 6.0)

	# Tray (placement) while no wave is running
	if not active:
		for s in CAT_ORDER.size():
			var key: String = CAT_ORDER[s]
			var cr := _chip_rect(s)
			var sel := selected == key
			draw_rect(cr, Color("#2A2A34") if sel else COL_TILE)
			draw_rect(cr, COL_AMBER if sel else COL_GRAY, false, 3.0 if sel else 2.0)
			_draw_portrait(key, Rect2(cr.position.x + 6.0, cr.position.y + 6.0, 32.0, 32.0), false)
			draw_string(font, Vector2(cr.position.x + 46.0, cr.position.y + 20.0), str(CAT_TYPES[key]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TEXT)
			draw_string(font, Vector2(cr.position.x + 46.0, cr.position.y + 37.0), "%d spare" % spare(key), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_AMBER if spare(key) > 0 else COL_MUTED)
		var hint := "Tap a cat above, then a tile. Tap a placed cat to pick it up."
		draw_string(font, Vector2(FIELD.position.x, 246.0), hint, HORIZONTAL_ALIGNMENT_CENTER, FIELD.size.x, 12, COL_MUTED)
		draw_string(font, Vector2(FIELD.position.x, 264.0), "Raised: +range, takes more damage.   Hole: tougher, less range.", HORIZONTAL_ALIGNMENT_CENTER, FIELD.size.x, 11, COL_MUTED)

	# Result banner
	if banner_t > 0.0 and banner != "":
		var lines := banner.split("\n")
		draw_rect(Rect2(FIELD.position.x + 14.0, 300.0, FIELD.size.x - 28.0, 40.0 + 22.0 * float(lines.size())), Color(0.043, 0.043, 0.055, 0.92))
		for n in lines.size():
			var size := 34 if n == 0 else 14
			var col := COL_AMBER if n == 0 else COL_TEXT
			draw_string(font, Vector2(FIELD.position.x, 336.0 + (0.0 if n == 0 else 24.0 + 20.0 * float(n - 1))), lines[n], HORIZONTAL_ALIGNMENT_CENTER, FIELD.size.x, size, col)


func _draw_enemy(e: Dictionary) -> void:
	var p := Vector2(float(e["x"]), float(e["y"]))
	var boss: bool = e["kind"] == "boss"
	var s := 1.9 if boss else 1.0
	var body := Color("#6B3A3A") if boss else COL_MOUSE
	# tail
	draw_line(p + Vector2(0.0, -10.0) * s, p + Vector2(8.0, -22.0) * s, body.darkened(0.2), 2.0 * s)
	# ears
	draw_circle(p + Vector2(-7.0, 6.0) * s, 4.5 * s, body.lightened(0.15))
	draw_circle(p + Vector2(7.0, 6.0) * s, 4.5 * s, body.lightened(0.15))
	# body
	draw_circle(p, 11.0 * s, COL_EDGE)
	draw_circle(p, 9.5 * s, body)
	# nose and eyes
	draw_circle(p + Vector2(0.0, 8.0) * s, 2.2 * s, COL_PEG)
	draw_circle(p + Vector2(-4.0, 3.0) * s, 1.8 * s, Color("#FFE066"))
	draw_circle(p + Vector2(4.0, 3.0) * s, 1.8 * s, Color("#FFE066"))
	if boss:
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-9.0, -10.0) * s, p + Vector2(-9.0, -18.0) * s, p + Vector2(-4.0, -13.0) * s,
			p + Vector2(0.0, -20.0) * s, p + Vector2(4.0, -13.0) * s, p + Vector2(9.0, -18.0) * s, p + Vector2(9.0, -10.0) * s,
		]), COL_AMBER)
	var frac := clampf(float(e["hp"]) / float(e["max"]), 0.0, 1.0)
	var bw := 26.0 * s
	draw_rect(Rect2(p.x - bw * 0.5, p.y - 16.0 * s - 6.0, bw, 4.0), COL_EDGE)
	draw_rect(Rect2(p.x - bw * 0.5, p.y - 16.0 * s - 6.0, bw * frac, 4.0), COL_PEG)
