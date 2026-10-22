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
signal shake(amount: float)

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
# Melee cats leave their tile, run to the most advanced mouse anywhere on the field, hold it and fight it.
const CHARGE_SPEED := 150.0         # px/s, out and back
const CHARGE_GAP := 36.0            # it stops this far from the mouse it is fighting
const MELEE_CONTACT := 52.0         # a melee cat hits any mouse within this distance
const COST_GROWTH := 1.35

# Action sprites (art_src/*.webp -> tools/extract_sheet.gd -> art/<cat>_anim.png): 4 x 2 cells of ANIM_CELL,
# every frame aligned on ANIM_ANCHOR (the ground point under the cat). Cats without an atlas use their portrait card.
const ANIM_CELL := Vector2(160.0, 112.0)
const ANIM_ANCHOR := Vector2(80.0, 84.0)
const ANIM_COLS := 4
const MAX_CAT_LEVEL := 5
const LEVEL_STAT_STEP := 0.2        # each cat level adds this much to health and damage (level 1 = x1.0)
const LEVEL_COST_FACTOR := 2.0      # level-up cost = base cost * this * LEVEL_COST_GROWTH ^ (level - 1)
const LEVEL_COST_GROWTH := 1.7

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
var cat_levels := {"macho": 1, "rosette": 1}
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
var anim_tex := {}   # cat key -> action sprite atlas
var fx := Fx.new()
var slashes: Array = []   # {pos, t}: melee slash arcs


func _ready() -> void:
	rng.randomize()
	_init_grid()
	for k in CAT_ORDER:
		var path := "res://games/catdrop/art/%s.png" % k
		if ResourceLoader.exists(path):
			textures[k] = load(path)
		var anim_path := "res://games/catdrop/art/%s_anim.png" % k
		if ResourceLoader.exists(anim_path):
			anim_tex[k] = load(anim_path)


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


func level_mult(key: String) -> float:
	return 1.0 + LEVEL_STAT_STEP * float(int(cat_levels[key]) - 1)


func can_level(key: String) -> bool:
	return int(cat_levels[key]) < MAX_CAT_LEVEL


func level_cost(key: String) -> int:
	return int(round(float(CAT_TYPES[key]["cost"]) * LEVEL_COST_FACTOR * pow(LEVEL_COST_GROWTH, float(int(cat_levels[key]) - 1))))


func level_up(key: String) -> void:
	cat_levels[key] = int(cat_levels[key]) + 1
	changed.emit()


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
	d["cat_levels"] = cat_levels.duplicate()


func load_from(d: Dictionary) -> void:
	_init_grid()
	wave = clampi(int(d.get("wave", 1)), 1, MAX_WAVE)
	house_hp = clampf(float(d.get("house_hp", HOUSE_MAX)), 1.0, HOUSE_MAX)
	var saved_owned: Dictionary = d.get("owned", {})
	for k in CAT_ORDER:
		owned[k] = clampi(int(saved_owned.get(k, owned[k])), 0, MAX_OWNED)
	var saved_levels: Dictionary = d.get("cat_levels", {})
	for k in CAT_ORDER:
		cat_levels[k] = clampi(int(saved_levels.get(k, 1)), 1, MAX_CAT_LEVEL)
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
			var hp: float = float(CAT_TYPES[key]["hp"]) * level_mult(key)
			cats.append({"key": key, "hp": hp, "max": hp, "cd": 0.4, "alive": true, "x": tile_center(i).x, "y": tile_center(i).y, "target": null, "face": 1.0, "n_atk": 0, "atk_t": 9.0, "phase": 0.0, "dust": 0.0, "moving": false})
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
	# Index of the top-most living cat in a column that is standing on its tile, or -1.
	for r in ROWS:
		var i := r * COLS + col
		if cats[i] != null and cats[i]["alive"] and not is_charging(i):
			return i
	return -1


func cat_pos(i: int) -> Vector2:
	# Where a cat is right now: its tile, or wherever it has run to.
	if cats.size() == COLS * ROWS and cats[i] != null:
		return Vector2(float(cats[i]["x"]), float(cats[i]["y"]))
	return tile_center(i)


func is_charging(i: int) -> bool:
	return active and cats.size() == COLS * ROWS and cats[i] != null and cats[i]["alive"] and cat_pos(i).distance_to(tile_center(i)) > 6.0


func _cat_damage_mult(i: int) -> float:
	# The tile bonuses only apply while the cat is standing on its tile.
	return 1.0 if is_charging(i) else _tile_damage_mult(i)


func _pick_charge_target(i: int) -> Dictionary:
	# Keep fighting the current mouse; otherwise go for the most advanced one anywhere (closest to the house).
	var cur = cats[i]["target"]
	if cur is Dictionary and not cur["dead"]:
		return cur
	var best: Dictionary = {}
	var best_y := -1.0
	for e in enemies:
		if not e["dead"] and float(e["y"]) > best_y:
			best = e
			best_y = float(e["y"])
	cats[i]["target"] = best if not best.is_empty() else null
	return best


func _move_melee(i: int, dt: float) -> void:
	var cat: Dictionary = cats[i]
	var pos := cat_pos(i)
	var goal := tile_center(i)
	var target := _pick_charge_target(i)
	if not target.is_empty():
		var tp := Vector2(float(target["x"]), float(target["y"]))
		var gap := pos.distance_to(tp)
		goal = pos if gap <= CHARGE_GAP else tp + (pos - tp).normalized() * CHARGE_GAP
		if absf(tp.x - pos.x) > 4.0:
			cat["face"] = signf(tp.x - pos.x)
		if gap <= MELEE_CONTACT and int(target["held_by"]) < 0:
			target["held_by"] = i
	var np := pos.move_toward(goal, CHARGE_SPEED * dt)
	np.x = clampf(np.x, FIELD.position.x + 22.0, FIELD.end.x - 22.0)
	np.y = clampf(np.y, SPAWN_Y, GRID_BOTTOM)
	cat["x"] = np.x
	cat["y"] = np.y
	var moving: bool = np.distance_to(pos) > 0.01
	cat["moving"] = moving
	if moving:
		cat["phase"] = float(cat["phase"]) + dt * 22.0
		cat["dust"] = float(cat["dust"]) - dt
		if float(cat["dust"]) <= 0.0:
			cat["dust"] = 0.09
			fx.burst(np + Vector2(0.0, 22.0), Color(0.78, 0.72, 0.66), 2, 45.0, 0.35, 3.0, -30.0)


func _find_target(i: int) -> Dictionary:
	var cat: Dictionary = cats[i]
	var center := cat_pos(i)
	var best: Dictionary = {}
	var kind: String = CAT_TYPES[cat["key"]]["kind"]
	var reach := cat_range(i)
	var best_d := INF
	for e in enemies:
		if e["dead"]:
			continue
		var d := Vector2(float(e["x"]), float(e["y"])).distance_to(center)
		if kind == "melee":
			if d <= MELEE_CONTACT and d < best_d:
				best = e
				best_d = d
		elif d <= reach and float(e["y"]) > float(best.get("y", -1.0)):
			best = e
	return best


func step(dt: float) -> void:
	if not active:
		return

	# Spawning
	spawn_timer -= dt
	if spawn_timer <= 0.0 and not spawn_queue.is_empty():
		_spawn(spawn_queue.pop_front())
		spawn_timer = SPAWN_INTERVAL

	# Melee cats run to the most advanced mouse anywhere and hold it
	for e in enemies:
		e["held_by"] = -1
	for i in COLS * ROWS:
		if cats[i] != null and cats[i]["alive"] and CAT_TYPES[cats[i]["key"]]["kind"] == "melee":
			_move_melee(i, dt)

	# Mice walk down their lane, queue behind each other, and chew whatever blocks them
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
			var held: int = int(e["held_by"])
			var lim := limit if idx == 0 else float(list[idx - 1]["y"]) - 20.0
			if held >= 0:
				lim = minf(lim, float(e["y"]))   # a mouse a cat has hold of stops where it is
			e["y"] = minf(float(e["y"]) + float(e["speed"]) * dt, lim)
			var victim := -1
			if held >= 0 and cats[held]["alive"]:
				victim = held
			elif idx == 0 and float(e["y"]) >= limit - 0.5 and front >= 0:
				victim = front
			if victim >= 0:
				cats[victim]["hp"] = float(cats[victim]["hp"]) - float(e["dps"]) * dt * _cat_damage_mult(victim)
				if float(cats[victim]["hp"]) <= 0.0:
					cats[victim]["alive"] = false
					fx.burst(cat_pos(victim), COL_AMBER, 12, 150.0, 0.6, 3.5, 250.0)
					shake.emit(2.0)
			elif held < 0 and idx == 0 and float(e["y"]) >= limit - 0.5 and front < 0:
				house_hp -= float(e["house"])
				fx.burst(Vector2(float(e["x"]), GRID_BOTTOM + 8.0), COL_PEG, 10, 160.0, 0.5, 3.5, 200.0)
				shake.emit(4.0 if e["kind"] == "boss" else 2.5)
				e["dead"] = true

	# Cats attack
	for i in COLS * ROWS:
		if cats[i] == null or not cats[i]["alive"]:
			continue
		var cat: Dictionary = cats[i]
		cat["cd"] = maxf(float(cat["cd"]) - dt, 0.0)
		cat["atk_t"] = float(cat["atk_t"]) + dt
		if float(cat["cd"]) > 0.0:
			continue
		var target := _find_target(i)
		if target.is_empty():
			continue
		var def: Dictionary = CAT_TYPES[cat["key"]]
		var dmg: float = float(def["dmg"]) * level_mult(cat["key"])
		target["hp"] = float(target["hp"]) - dmg
		cat["cd"] = float(def["interval"])
		cat["atk_t"] = 0.0
		cat["n_atk"] = int(cat["n_atk"]) + 1
		if def["kind"] == "melee":
			slashes.append({"pos": Vector2(float(target["x"]), float(target["y"])), "t": 0.2})
		var from := cat_pos(i)
		tracers.append({"from": from, "to": Vector2(float(target["x"]), float(target["y"])), "t": 0.12, "melee": def["kind"] == "melee"})
		floaters.append({"pos": Vector2(float(target["x"]), float(target["y"]) - 14.0), "text": str(int(dmg)), "t": 0.6})
		fx.burst(Vector2(float(target["x"]), float(target["y"])), Color(1.0, 1.0, 1.0), 3, 90.0, 0.2, 2.0, 0.0)
		if float(target["hp"]) <= 0.0:
			target["dead"] = true
			fx.burst(Vector2(float(target["x"]), float(target["y"])), COL_MOUSE if target["kind"] != "boss" else COL_PEG, 8 if target["kind"] != "boss" else 30, 130.0 if target["kind"] != "boss" else 220.0, 0.5, 3.0, 260.0)
			if target["kind"] == "boss":
				shake.emit(9.0)

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
	shake.emit(8.0)
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
	fx.update(delta)
	for sl in slashes:
		sl["t"] = float(sl["t"]) - delta
	slashes = slashes.filter(func(sl): return float(sl["t"]) > 0.0)
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


func _draw_hp_bar(rect: Rect2, frac: float, good: Color = Color("#6BD66B")) -> void:
	draw_rect(rect.grow(2.0), UIKit.INK)
	draw_rect(rect, Color("#2A2A34"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(frac, 0.0, 1.0), rect.size.y)), good if frac > 0.4 else COL_PEG)


func _draw_cat_card(key: String, rect: Rect2, dead: bool) -> void:
	UIKit.panel(self, rect.grow(3.0), UIKit.CRIMSON, UIKit.AMBER if not dead else UIKit.GRAY, 3, 9)
	_draw_portrait(key, rect, false)
	if dead:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.6))


func _sprite_frame(cat: Dictionary) -> int:
	# Which atlas frame: idle 0, wind-up 1, lunge 2, swipe 3, bite 4, impact 5, retreat 6, landing 7.
	var atk := float(cat["atk_t"])
	if atk < 0.41:
		if atk < 0.07:
			return 2
		if atk < 0.17:
			return 3 if int(cat["n_atk"]) % 2 == 1 else 4
		if atk < 0.25:
			return 5
		if atk < 0.33:
			return 6
		return 7
	if cat["moving"]:
		return 2 if int(float(cat["phase"]) / 3.0) % 2 == 0 else 6   # gallop: stretched out, then gathered
	return 0


func _draw_cat_sprite(i: int, center: Vector2, dead: bool) -> void:
	var key: String = grid[i]
	var cat = cats[i] if active and cats.size() == COLS * ROWS else null
	var frame := 0
	var face := 1.0
	if cat != null:
		face = float(cat["face"])
		if not dead:
			frame = _sprite_frame(cat)
	var ground := center + Vector2(0.0, 18.0)
	var src := Rect2(Vector2(float(frame % ANIM_COLS) * ANIM_CELL.x, float(frame / ANIM_COLS) * ANIM_CELL.y), ANIM_CELL)
	draw_set_transform(ground, 0.0, Vector2(face, 1.0))
	draw_texture_rect_region(anim_tex[key], Rect2(-ANIM_ANCHOR, ANIM_CELL), src, Color(1.0, 1.0, 1.0, 0.4) if dead else Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_cat_anim(i: int, center: Vector2, dead: bool) -> void:
	# A cat card with simple procedural animation: bob and lean while running, lunge and pop on attack.
	var key: String = grid[i]
	if anim_tex.has(key):
		_draw_cat_sprite(i, center, dead)
		return
	var cat = cats[i] if active and cats.size() == COLS * ROWS else null
	var off := Vector2.ZERO
	var rot := 0.0
	var sc := Vector2.ONE
	if cat != null and not dead:
		var atk: float = float(cat["atk_t"])
		if atk < 0.22:
			var k := 1.0 - atk / 0.22
			sc = Vector2.ONE * (1.0 + 0.22 * k)
			if CAT_TYPES[key]["kind"] == "melee":
				off = Vector2(0.0, -14.0 * k * k)
				rot = 0.18 * k
			else:
				off = Vector2(0.0, 4.0 * k)
		if cat["moving"]:
			var ph: float = float(cat["phase"])
			off += Vector2(0.0, -absf(sin(ph)) * 5.0)
			rot += sin(ph) * 0.10
			sc *= Vector2(1.0 + 0.05 * sin(ph * 2.0), 1.0 - 0.05 * sin(ph * 2.0))
			for k2 in 3:
				var lx := center.x - 12.0 + float(k2) * 12.0
				draw_line(Vector2(lx, center.y + 26.0), Vector2(lx, center.y + 38.0 + 4.0 * float(k2 % 2)), Color(1.0, 1.0, 1.0, 0.22), 2.0)
	draw_set_transform(center + off, rot, sc)
	_draw_cat_card(key, Rect2(-20.0, -20.0, 40.0, 40.0), dead)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	UIKit.panel(self, FIELD.grow(5.0), UIKit.INK, UIKit.INK, 5, 14)
	UIKit.gradient(self, FIELD, Color("#1B1B25"), Color("#0C0C11"))

	# Lane guides
	for c in COLS:
		var x := column_x(c)
		draw_dashed_line(Vector2(x, 176.0), Vector2(x, GRID_ORIGIN.y - 6.0), Color(1.0, 1.0, 1.0, 0.07), 2.0, 8.0)

	# House bar
	UIKit.text(self, Vector2(26.0, 158.0), "HOUSE", 14, UIKit.CREAM, UIKit.INK, 4)
	_draw_hp_bar(Rect2(92.0, 144.0, 226.0, 14.0), house_hp / HOUSE_MAX, COL_PEG)
	UIKit.text(self, Vector2(326.0, 158.0), str(int(maxf(house_hp, 0.0))), 14, UIKit.CREAM, UIKit.INK, 4)

	# Tiles and cats
	for i in COLS * ROWS:
		var r := tile_rect(i)
		var kind: String = TILE_TYPES[i]
		var cat = cats[i] if active and cats.size() == COLS * ROWS else null
		var key: String = grid[i]
		match kind:
			"flat":
				UIKit.panel(self, r, Color("#22222C"), UIKit.INK, 3, 10)
			"raised":
				UIKit.panel(self, r, Color("#5A5A6C"), UIKit.INK, 3, 10, 8)
				draw_rect(Rect2(r.position.x + 5.0, r.position.y + 4.0, r.size.x - 10.0, 4.0), Color("#9A9AAE"))
			"hole":
				UIKit.panel(self, r, Color("#16161C"), UIKit.INK, 3, 10)
				draw_rect(Rect2(r.position.x + 9.0, r.position.y + 11.0, r.size.x - 18.0, r.size.y - 20.0), Color.BLACK)
		if key != "" and is_charging(i):
			draw_rect(r.grow(-6.0), Color(1.0, 1.0, 1.0, 0.05), false, 2.0)
		elif key != "":
			var dead: bool = cat != null and not cat["alive"]
			var pr := Rect2(r.position.x + (r.size.x - 40.0) * 0.5, r.position.y + (2.0 if kind == "raised" else 7.0), 40.0, 40.0)
			if kind == "hole":
				var peek := Rect2(r.position.x + 18.0, r.position.y + 24.0, r.size.x - 36.0, 36.0)
				_draw_portrait(key, peek, true)
				draw_rect(Rect2(peek.position.x, peek.position.y, peek.size.x, peek.size.y * 0.5), Color(0.0, 0.0, 0.0, 0.18))
			else:
				_draw_cat_anim(i, pr.get_center(), dead)
			if cat != null and not dead:
				var frac := clampf(float(cat["hp"]) / float(cat["max"]), 0.0, 1.0)
				_draw_hp_bar(Rect2(r.position.x + 8.0, r.end.y - (15.0 if kind == "raised" else 9.0), r.size.x - 16.0, 5.0), frac)

	# Cats that have run out of their tile
	for i in COLS * ROWS:
		if is_charging(i):
			var cp := cat_pos(i)
			var ckey: String = grid[i]
			var cr := Rect2(cp.x - 20.0, cp.y - 20.0, 40.0, 40.0)
			draw_circle(cp + Vector2(0.0, 24.0), 16.0, Color(0.0, 0.0, 0.0, 0.3))
			_draw_cat_anim(i, cp, false)
			var cfrac := clampf(float(cats[i]["hp"]) / float(cats[i]["max"]), 0.0, 1.0)
			_draw_hp_bar(Rect2(cp.x - 20.0, cp.y + 26.0, 40.0, 5.0), cfrac)

	# Enemies
	for e in enemies:
		_draw_enemy(e)

	# Attacks and damage numbers
	for t in tracers:
		var a := float(t["t"]) / 0.12
		draw_line(Vector2(t["from"]), Vector2(t["to"]), Color(UIKit.INK, a), 7.0 if t["melee"] else 5.0)
		draw_line(Vector2(t["from"]), Vector2(t["to"]), Color(COL_AMBER, a), 4.0 if t["melee"] else 2.5)
	for sl in slashes:
		var sk := float(sl["t"]) / 0.2
		draw_arc(Vector2(sl["pos"]), 24.0, -2.6, -0.5, 12, Color(UIKit.INK, sk), 10.0)
		draw_arc(Vector2(sl["pos"]), 24.0, -2.6, -0.5, 12, Color(UIKit.CREAM, sk), 5.0)
	fx.draw(self)
	for f in floaters:
		var fa := clampf(float(f["t"]) / 0.6, 0.0, 1.0)
		UIKit.text(self, Vector2(f["pos"]), str(f["text"]), 18, Color(UIKit.CREAM, fa), Color(UIKit.INK, fa), 5)

	# Tray (placement) while no wave is running
	if not active:
		for s in CAT_ORDER.size():
			var key: String = CAT_ORDER[s]
			var cr := _chip_rect(s)
			var sel := selected == key
			UIKit.panel(self, cr, Color("#3A2A12") if sel else UIKit.INK_SOFT, UIKit.AMBER if sel else UIKit.INK, 3, 10, 3)
			_draw_portrait(key, Rect2(cr.position.x + 6.0, cr.position.y + 6.0, 30.0, 30.0), false)
			UIKit.text(self, Vector2(cr.position.x + 44.0, cr.position.y + 20.0), str(CAT_TYPES[key]["name"]), 15, UIKit.CREAM, UIKit.INK, 4)
			draw_string(font, Vector2(cr.position.x + 44.0, cr.position.y + 37.0), "%d spare" % spare(key), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_AMBER if spare(key) > 0 else COL_MUTED)
		var hint := "Tap a cat above, then a tile. Tap a placed cat to pick it up."
		draw_string(font, Vector2(FIELD.position.x, 246.0), hint, HORIZONTAL_ALIGNMENT_CENTER, FIELD.size.x, 12, COL_MUTED)
		draw_string(font, Vector2(FIELD.position.x, 264.0), "Raised: +range, takes more damage.   Hole: tougher, less range.", HORIZONTAL_ALIGNMENT_CENTER, FIELD.size.x, 11, COL_MUTED)

	# Result banner
	if banner_t > 0.0 and banner != "":
		var lines := banner.split("\n")
		UIKit.panel(self, Rect2(FIELD.position.x + 14.0, 296.0, FIELD.size.x - 28.0, 46.0 + 22.0 * float(lines.size())), Color(UIKit.INK_SOFT, 0.96), UIKit.AMBER, 4, 16, 3)
		for n in lines.size():
			var size := 32 if n == 0 else 14
			var col := UIKit.AMBER if n == 0 else UIKit.CREAM
			UIKit.text(self, Vector2(FIELD.position.x, 336.0 + (0.0 if n == 0 else 24.0 + 20.0 * float(n - 1))), lines[n], size, col, UIKit.INK, 7 if n == 0 else 4, HORIZONTAL_ALIGNMENT_CENTER, FIELD.size.x)


func _draw_enemy(e: Dictionary) -> void:
	var p := Vector2(float(e["x"]), float(e["y"]))
	var boss: bool = e["kind"] == "boss"
	var s := 1.9 if boss else 1.0
	var body := Color("#7A3B3B") if boss else COL_MOUSE
	var wob := sin(float(e["y"]) * 0.35) * 1.2 * s
	# ground shadow
	draw_circle(p + Vector2(0.0, 11.0 * s), 9.0 * s, Color(0.0, 0.0, 0.0, 0.25))
	# tail
	var tail := PackedVector2Array([p + Vector2(0.0, -8.0) * s, p + Vector2(7.0 + wob, -17.0) * s, p + Vector2(3.0, -26.0) * s])
	draw_polyline(tail, UIKit.INK, 4.5 * s, true)
	draw_polyline(tail, Color("#D58A9B"), 2.2 * s, true)
	# ears
	for sx in [-1.0, 1.0]:
		draw_circle(p + Vector2(sx * 8.0, 5.0) * s, 6.0 * s, UIKit.INK)
		draw_circle(p + Vector2(sx * 8.0, 5.0) * s, 4.2 * s, body.lightened(0.1))
		draw_circle(p + Vector2(sx * 8.0, 5.0) * s, 2.4 * s, Color("#E7A1B3"))
	# body
	draw_circle(p, 12.0 * s, UIKit.INK)
	draw_circle(p, 9.6 * s, body)
	draw_circle(p + Vector2(-2.5, -3.0) * s, 3.0 * s, body.lightened(0.18))
	# nose, whiskers, angry eyes
	draw_circle(p + Vector2(0.0, 8.0) * s, 2.4 * s, COL_PEG)
	for sx in [-1.0, 1.0]:
		draw_line(p + Vector2(sx * 3.0, 8.0) * s, p + Vector2(sx * 11.0, 9.0 + wob) * s, UIKit.INK, 1.4 * s)
		draw_circle(p + Vector2(sx * 4.0, 3.0) * s, 2.4 * s, Color("#FFE066"))
		draw_circle(p + Vector2(sx * 4.0, 3.4) * s, 1.0 * s, UIKit.INK)
		draw_line(p + Vector2(sx * 1.0, 0.0) * s, p + Vector2(sx * 7.0, 1.6) * s, UIKit.INK, 1.8 * s)
	if boss:
		var cr := PackedVector2Array([
			p + Vector2(-9.0, -9.0) * s, p + Vector2(-9.0, -18.0) * s, p + Vector2(-4.0, -13.0) * s,
			p + Vector2(0.0, -21.0) * s, p + Vector2(4.0, -13.0) * s, p + Vector2(9.0, -18.0) * s, p + Vector2(9.0, -9.0) * s,
		])
		var cr_out: PackedVector2Array = cr.duplicate()
		cr_out.append(cr[0])
		draw_colored_polygon(cr, COL_AMBER)
		draw_polyline(cr_out, UIKit.INK, 2.5, true)
	var frac := clampf(float(e["hp"]) / float(e["max"]), 0.0, 1.0)
	var bw := 26.0 * s
	_draw_hp_bar(Rect2(p.x - bw * 0.5, p.y - 17.0 * s - 8.0, bw, 4.0), frac, COL_PEG)


