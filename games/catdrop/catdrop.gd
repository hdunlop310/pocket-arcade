extends GameBase
# Cat Drop: drop balls for coins, spend coins on cats and upgrades, defend the house.
# Everything is built in code so there is just one scene to open.
#
# One round, in order: MAP (upgrade, then press play) -> DROP (one burst of balls, coins bank)
# -> BATTLE (place cats, fight the wave) -> back to the MAP. There is no way to drop twice
# without fighting in between, so coins can't be farmed.

const BallScript := preload("res://games/catdrop/ball.gd")
const BattleScript := preload("res://games/catdrop/battle.gd")

# --- Tuning knobs -----------------------------------------------------------
const BASE_BALLS := 12            # balls per round before any upgrades
const BALLS_STEP := 2             # extra balls per "more balls" level
const BASE_COINS_PER_BALL := 1    # coins per ball before any upgrades
const MAX_BALLS_ALIVE := 250      # safety cap so big multipliers can't tank the framerate
const DROP_STAGGER := 0.06        # seconds between balls in the burst
const SWEEP_SPEED := 2.2          # how fast the dropper swings
const SWEEP_RANGE := 130.0        # how far it swings from the centre

# Profile XP reported to the hub
const XP_PER_WAVE := 10
const XP_PER_ROUND := 5
const XP_RUN_WON := 50

# Rewards for clearing waves
const WAVE_BONUS_BALLS := 4       # extra balls on your next drop round
const WAVE_COINS_PER_WAVE := 15   # coins = this * wave number
const RUN_COMPLETE_COINS := 200

# Board upgrades. Cost of the next level = round(base * growth ^ current_level).
const UPGRADE_ORDER := ["balls", "coin", "gates"]
const UPGRADES := {
	"balls": {"name": "MORE BALLS", "base": 50.0, "growth": 1.6, "max": 6},
	"coin": {"name": "COIN VALUE", "base": 80.0, "growth": 1.8, "max": 5},
	"gates": {"name": "BIGGER GATES", "base": 200.0, "growth": 2.5, "max": 2},
}

const CHAPTER_TITLE := "CHAPTER 1: THE MOUSE INVASION"
const STORY := [
	"Squeaks in the walls. Someone ate the cheese.",
	"A mouse in the pantry. Macho is not amused.",
	"They are bringing friends.",
	"The kitchen floor is crawling.",
	"Halfway there. Whiskers twitching.",
	"They are chewing through the garden fence.",
	"Something big is digging under the house.",
	"The mice built a barricade of bottle caps.",
	"The ground shakes. The Rat King is near.",
	"THE RAT KING. Defend the house.",
]

# --- Layout (viewport is 390 x 844) -----------------------------------------
const FIELD := Rect2(16.0, 130.0, 358.0, 590.0)
const CUP_WALL_LEFT := Rect2(131.0, 650.0, 6.0, 56.0)
const CUP_WALL_RIGHT := Rect2(253.0, 650.0, 6.0, 56.0)
const CUP_SENSOR := Rect2(137.0, 656.0, 116.0, 46.0)
const MAP_PANEL := Rect2(16.0, 392.0, 358.0, 330.0)
const ROW_STEP := 58.0
const ROW_H := 54.0
const PATH_TOP := 150.0
const PATH_BOTTOM := 362.0

# Each gate multiplies any ball that falls through it.
const GATES := [
	{"rect": Rect2(30.0, 330.0, 100.0, 28.0), "mult": 2},
	{"rect": Rect2(260.0, 330.0, 100.0, 28.0), "mult": 3},
	{"rect": Rect2(145.0, 440.0, 100.0, 28.0), "mult": 5},
	{"rect": Rect2(30.0, 540.0, 100.0, 28.0), "mult": 3},
	{"rect": Rect2(260.0, 540.0, 100.0, 28.0), "mult": 2},
]

# --- Colours (crimson / black / amber) ---------------------------------------
const COL_BG := Color("#7E1236")
const COL_FIELD := Color("#101015")
const COL_EDGE := Color("#0B0B0E")
const COL_PEG := Color("#E0285E")
const COL_AMBER := Color("#F2A81D")
const COL_TEXT := Color("#F4F4F6")
const COL_MUTED := Color("#A6A6B2")
const COL_GRAY := Color("#33333D")
const COL_CAT := Color("#1B1B23")

var coins := 0
var levels := {"balls": 0, "coin": 0, "gates": 0}
var stats := {"balls_banked": 0, "best_wave": 0, "runs_won": 0}
var bonus_balls := 0
var balls_left := BASE_BALLS
var state := "map"          # "map", "drop" or "battle"
var dropped := false        # this round's one drop has been used
var round_over := false     # the drop is finished and every ball has landed
var dropping := false
var returning := false      # a wave just ended; back to the map when its banner is gone
var drop_x := 195.0
var t := 0.0
var pegs: Array[Vector2] = []

var battle: Node2D
var main_btn: Button
var home_btn: Button
var map_panel: Panel
var map_rows := {}  # "cat:macho" / "up:balls" -> {"desc", "pips", "buy", "lvl"}


func _init() -> void:
	id = "catdrop"
	title = "Cat Drop"


func _ready() -> void:
	battle = BattleScript.new()
	battle.visible = false
	add_child(battle)
	battle.wave_cleared.connect(_on_wave_cleared)
	battle.run_won.connect(_on_run_won)
	battle.run_failed.connect(_on_run_failed)
	battle.changed.connect(_on_battle_changed)

	balls_left = balls_per_round()
	_build_walls()
	_build_funnels()
	_build_pegs()
	_build_gates()
	_build_cup()
	_build_buttons()
	_build_map_panel()
	_refresh_panel()
	_apply_state()
	# Without a hub (editor F6, tests) load our own save; the hub calls start() itself right after adding us.
	start_standalone.call_deferred()


func _on_start() -> void:
	_load_game()
	balls_left = balls_per_round()
	_go_map()


# ----------------------------------------------------------------------------
# Upgrade maths
# ----------------------------------------------------------------------------

func balls_per_round() -> int:
	return BASE_BALLS + BALLS_STEP * int(levels["balls"])


func coins_per_ball() -> int:
	return BASE_COINS_PER_BALL + int(levels["coin"])


func gate_mult(i: int) -> int:
	return int(GATES[i]["mult"]) + int(levels["gates"])


func upgrade_cost(key: String) -> int:
	var u: Dictionary = UPGRADES[key]
	return int(round(float(u["base"]) * pow(float(u["growth"]), float(levels[key]))))


func is_maxed(key: String) -> bool:
	return int(levels[key]) >= int(UPGRADES[key]["max"])


func buy(key: String) -> bool:
	if is_maxed(key):
		return false
	var cost := upgrade_cost(key)
	if coins < cost:
		return false
	coins -= cost
	levels[key] = int(levels[key]) + 1
	_save_game()
	_refresh_panel()
	_report(0)
	return true


func buy_cat(key: String) -> bool:
	if not battle.can_add_cat(key):
		return false
	var cost: int = battle.cat_cost(key)
	if coins < cost:
		return false
	coins -= cost
	battle.add_cat(key)
	_save_game()
	_refresh_panel()
	_report(0)
	return true


func upgrade_cat(key: String) -> bool:
	if not battle.can_level(key):
		return false
	var cost: int = battle.level_cost(key)
	if coins < cost:
		return false
	coins -= cost
	battle.level_up(key)
	_save_game()
	_refresh_panel()
	_report(0)
	return true


# ----------------------------------------------------------------------------
# Reporting to the hub (profile XP and achievements)
# ----------------------------------------------------------------------------

func unlocked_achievements() -> Array:
	var ids: Array = []
	var banked: int = int(stats["balls_banked"])
	var cats: int = 0
	for k in battle.CAT_ORDER:
		cats += int(battle.owned[k])
	if banked >= 1:
		ids.append("cd_first_ball")
	if banked >= 100:
		ids.append("cd_100_balls")
	if banked >= 1000:
		ids.append("cd_1000_balls")
	if int(stats["best_wave"]) >= 1:
		ids.append("cd_first_wave")
	if int(stats["best_wave"]) >= 5:
		ids.append("cd_wave_5")
	if cats >= 4:
		ids.append("cd_four_cats")
	for key in UPGRADE_ORDER:
		if is_maxed(key):
			ids.append("cd_maxed")
			break
	if int(stats["runs_won"]) >= 1:
		ids.append("cd_boss")
	return ids


func _report(xp: int) -> void:
	progress.emit({"xp": xp, "achievements": unlocked_achievements()})


# ----------------------------------------------------------------------------
# Saving
# ----------------------------------------------------------------------------

func _save_game() -> void:
	slot["coins"] = coins
	slot["bonus_balls"] = bonus_balls
	slot["levels"] = levels.duplicate()
	slot["stats"] = stats.duplicate()
	battle.save_to(slot)
	save_requested.emit()


func _load_game() -> void:
	if slot.is_empty():
		return
	coins = int(slot.get("coins", 0))
	bonus_balls = maxi(int(slot.get("bonus_balls", 0)), 0)
	var saved_levels: Dictionary = slot.get("levels", {})
	for k in UPGRADE_ORDER:
		var maxl: int = int(UPGRADES[k]["max"])
		levels[k] = clampi(int(saved_levels.get(k, 0)), 0, maxl)
	var saved_stats: Dictionary = slot.get("stats", {})
	for k in stats:
		stats[k] = maxi(int(saved_stats.get(k, 0)), 0)
	battle.load_from(slot)


func _on_battle_changed() -> void:
	_save_game()
	_refresh_panel()


# ----------------------------------------------------------------------------
# Building the board
# ----------------------------------------------------------------------------

func _bouncy(amount: float) -> PhysicsMaterial:
	var mat := PhysicsMaterial.new()
	mat.bounce = amount
	mat.friction = 0.1
	return mat


func _add_static_rect(rect: Rect2, bounce: float = 0.3) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	body.collision_layer = 1
	body.physics_material_override = _bouncy(bounce)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _add_static_polygon(points: PackedVector2Array, bounce: float = 0.2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.physics_material_override = _bouncy(bounce)
	var shape := CollisionPolygon2D.new()
	shape.polygon = points
	body.add_child(shape)
	add_child(body)


func _build_walls() -> void:
	_add_static_rect(Rect2(FIELD.position.x - 10.0, FIELD.position.y, 10.0, FIELD.size.y))
	_add_static_rect(Rect2(FIELD.end.x, FIELD.position.y, 10.0, FIELD.size.y))


func _funnel_left() -> PackedVector2Array:
	return PackedVector2Array([Vector2(16.0, 590.0), Vector2(137.0, 650.0), Vector2(16.0, 650.0)])


func _funnel_right() -> PackedVector2Array:
	return PackedVector2Array([Vector2(374.0, 590.0), Vector2(253.0, 650.0), Vector2(374.0, 650.0)])


func _build_funnels() -> void:
	_add_static_polygon(_funnel_left())
	_add_static_polygon(_funnel_right())
	_add_static_rect(CUP_WALL_LEFT)
	_add_static_rect(CUP_WALL_RIGHT)


func _blocked_by_gate(p: Vector2) -> bool:
	for g in GATES:
		var r: Rect2 = g["rect"]
		if r.grow(16.0).has_point(p):
			return true
	return false


func _build_pegs() -> void:
	var row := 0
	var y := FIELD.position.y + 90.0
	while y < FIELD.end.y - 130.0:
		var x := FIELD.position.x + 30.0
		if row % 2 == 1:
			x += 25.0
		while x < FIELD.end.x - 24.0:
			var p := Vector2(x, y)
			if not _blocked_by_gate(p):
				pegs.append(p)
				_add_peg(p)
			x += 50.0
		y += 52.0
		row += 1


func _add_peg(p: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = p
	body.collision_layer = 1
	body.physics_material_override = _bouncy(0.4)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	body.add_child(shape)
	add_child(body)


func _add_sensor(rect: Rect2) -> Area2D:
	# A sensor only detects balls (layer 2); it never blocks them.
	var area := Area2D.new()
	area.position = rect.get_center()
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	area.add_child(shape)
	add_child(area)
	return area


func _build_gates() -> void:
	for i in GATES.size():
		var rect: Rect2 = GATES[i]["rect"]
		var area := _add_sensor(rect)
		area.body_entered.connect(_on_gate_entered.bind(i))


func _build_cup() -> void:
	var area := _add_sensor(CUP_SENSOR)
	area.body_entered.connect(_on_cup_entered)


# ----------------------------------------------------------------------------
# UI
# ----------------------------------------------------------------------------

func _style_button(btn: Button, bg: Color, fg: Color, size: int) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", size)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(c, fg)
	btn.add_theme_color_override("font_disabled_color", COL_MUTED)
	for s in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		if s == "pressed":
			sb.bg_color = bg.darkened(0.2)
		if s == "disabled":
			sb.bg_color = COL_GRAY
		btn.add_theme_stylebox_override(s, sb)


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build_buttons() -> void:
	main_btn = Button.new()
	main_btn.position = Vector2(16.0, 760.0)
	main_btn.size = Vector2(284.0, 56.0)
	main_btn.text = "PLAY WAVE 1"
	_style_button(main_btn, COL_AMBER, COL_EDGE, 20)
	main_btn.pressed.connect(_on_main_pressed)
	add_child(main_btn)

	home_btn = Button.new()
	home_btn.position = Vector2(308.0, 760.0)
	home_btn.size = Vector2(66.0, 56.0)
	home_btn.text = "HUB"
	_style_button(home_btn, COL_CAT, COL_AMBER, 18)
	home_btn.pressed.connect(func(): quit_requested.emit())
	add_child(home_btn)


# One row of the upgrade panel. Cat rows get two stacked buttons (buy a copy / level up),
# board upgrade rows get one button and a row of pips.
func _add_row(id_: String, title_: String, y: float, portrait: String, max_pips: int, two_buttons: bool) -> void:
	var row_bg := ColorRect.new()
	row_bg.color = Color("#16161C")
	row_bg.position = Vector2(12.0, y)
	row_bg.size = Vector2(MAP_PANEL.size.x - 24.0, ROW_H)
	map_panel.add_child(row_bg)

	var text_x := 24.0
	var art_path := "res://games/catdrop/art/%s.png" % portrait
	if portrait != "" and ResourceLoader.exists(art_path):
		var pic := TextureRect.new()
		pic.texture = load(art_path)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.position = Vector2(20.0, y + 7.0)
		pic.size = Vector2(40.0, 40.0)
		map_panel.add_child(pic)
		text_x = 70.0

	var name_label := _make_label(title_, 18, COL_TEXT)
	name_label.position = Vector2(text_x, y + 2.0)
	map_panel.add_child(name_label)

	var desc := _make_label("", 12, COL_MUTED)
	desc.position = Vector2(text_x, y + 26.0)
	map_panel.add_child(desc)

	var pips := Control.new()
	pips.position = Vector2(text_x, y + 44.0)
	map_panel.add_child(pips)
	for p in max_pips:
		var pip := ColorRect.new()
		pip.position = Vector2(float(p) * 22.0, 0.0)
		pip.size = Vector2(18.0, 6.0)
		pips.add_child(pip)

	var btn_x := MAP_PANEL.size.x - 24.0 - 104.0 + 12.0
	var buy_btn := Button.new()
	buy_btn.position = Vector2(btn_x, y + (4.0 if two_buttons else 7.0))
	buy_btn.size = Vector2(104.0, 22.0 if two_buttons else 40.0)
	_style_button(buy_btn, COL_AMBER, COL_EDGE, 14 if two_buttons else 18)
	map_panel.add_child(buy_btn)

	var lvl_btn: Button = null
	if two_buttons:
		lvl_btn = Button.new()
		lvl_btn.position = Vector2(btn_x, y + 28.0)
		lvl_btn.size = Vector2(104.0, 22.0)
		_style_button(lvl_btn, COL_PEG, COL_TEXT, 14)
		map_panel.add_child(lvl_btn)

	map_rows[id_] = {"desc": desc, "pips": pips, "buy": buy_btn, "lvl": lvl_btn}


func _build_map_panel() -> void:
	map_panel = Panel.new()
	map_panel.position = MAP_PANEL.position
	map_panel.size = MAP_PANEL.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_EDGE
	sb.border_color = COL_AMBER
	sb.set_border_width_all(3)
	map_panel.add_theme_stylebox_override("panel", sb)
	add_child(map_panel)

	var cats_heading := _make_label("YOUR CATS  (tap to upgrade)", 12, COL_MUTED)
	cats_heading.position = Vector2(16.0, 3.0)
	map_panel.add_child(cats_heading)
	for i in battle.CAT_ORDER.size():
		var key: String = battle.CAT_ORDER[i]
		var def: Dictionary = battle.CAT_TYPES[key]
		_add_row("cat:" + key, str(def["name"]), 20.0 + float(i) * ROW_STEP, key, 0, true)
		var cat_btn: Button = map_rows["cat:" + key]["buy"]
		cat_btn.pressed.connect(func(): buy_cat(key))
		var lvl_btn: Button = map_rows["cat:" + key]["lvl"]
		lvl_btn.pressed.connect(func(): upgrade_cat(key))

	var up_y := 20.0 + float(battle.CAT_ORDER.size()) * ROW_STEP
	var up_heading := _make_label("BOARD UPGRADES", 12, COL_MUTED)
	up_heading.position = Vector2(16.0, up_y - 3.0)
	map_panel.add_child(up_heading)
	for i in UPGRADE_ORDER.size():
		var key: String = UPGRADE_ORDER[i]
		_add_row("up:" + key, str(UPGRADES[key]["name"]), up_y + 15.0 + float(i) * ROW_STEP, "", int(UPGRADES[key]["max"]), false)
		var up_btn: Button = map_rows["up:" + key]["buy"]
		up_btn.pressed.connect(func(): buy(key))


func _desc_for(key: String) -> String:
	match key:
		"balls":
			return "%d > %d balls per round" % [balls_per_round(), balls_per_round() + BALLS_STEP]
		"coin":
			return "%d > %d coins per ball" % [coins_per_ball(), coins_per_ball() + 1]
		"gates":
			return "+1 on every gate"
	return ""


func _refresh_panel() -> void:
	if map_panel == null:
		return

	for key in battle.CAT_ORDER:
		var row: Dictionary = map_rows["cat:" + key]
		var buy_btn: Button = row["buy"]
		var lvl_btn: Button = row["lvl"]
		var desc: Label = row["desc"]
		var role: String = str(battle.CAT_TYPES[key]["role"]).capitalize()
		desc.text = "%s  own %d  Lv %d" % [role, int(battle.owned[key]), int(battle.cat_levels[key])]
		if not battle.can_add_cat(key):
			buy_btn.text = "MAX CATS"
			buy_btn.disabled = true
		else:
			var cost: int = battle.cat_cost(key)
			buy_btn.text = "BUY %d" % cost
			buy_btn.disabled = coins < cost
		if not battle.can_level(key):
			lvl_btn.text = "MAX LEVEL"
			lvl_btn.disabled = true
		else:
			var lcost: int = battle.level_cost(key)
			lvl_btn.text = "LEVEL UP %d" % lcost
			lvl_btn.disabled = coins < lcost

	for key in UPGRADE_ORDER:
		var row: Dictionary = map_rows["up:" + key]
		var lvl: int = int(levels[key])
		var pips: Control = row["pips"]
		for p in pips.get_child_count():
			(pips.get_child(p) as ColorRect).color = COL_PEG if p < lvl else COL_GRAY
		var buy_btn: Button = row["buy"]
		var desc: Label = row["desc"]
		if is_maxed(key):
			desc.text = "Maxed out"
			buy_btn.text = "MAX"
			buy_btn.disabled = true
		else:
			desc.text = _desc_for(key)
			var cost := upgrade_cost(key)
			buy_btn.text = str(cost)
			buy_btn.disabled = coins < cost


# ----------------------------------------------------------------------------
# Game flow: map -> drop (once) -> battle -> map
# ----------------------------------------------------------------------------

func _apply_state() -> void:
	battle.visible = (state == "battle")
	map_panel.visible = (state == "map")
	home_btn.visible = (state == "map")
	main_btn.size.x = 284.0 if state == "map" else 358.0


func _go_map() -> void:
	state = "map"
	returning = false
	dropped = false
	round_over = false
	_refresh_panel()
	_apply_state()
	_save_game()


func _begin_round() -> void:
	# The round's balls are counted now; bonus balls are only spent when they are dropped.
	state = "drop"
	dropped = false
	round_over = false
	balls_left = balls_per_round() + bonus_balls
	_apply_state()


func _enter_battle() -> void:
	state = "battle"
	returning = false
	_apply_state()


func _busy() -> bool:
	return dropping or battle.active or not get_tree().get_nodes_in_group("balls").is_empty()


func _process(delta: float) -> void:
	t += delta
	drop_x = 195.0 + sin(t * SWEEP_SPEED) * SWEEP_RANGE

	var alive := get_tree().get_nodes_in_group("balls")

	# Clean up any ball that somehow got out of the board.
	for b in alive:
		if b.position.y > 800.0:
			b.queue_free()

	if state == "drop" and dropped and balls_left == 0 and not dropping and not round_over and alive.is_empty():
		round_over = true
		_save_game()
		_report(XP_PER_ROUND)

	# After a wave ends, let its banner show, then go back to the map.
	if state == "battle" and returning and not battle.active and battle.banner_t <= 0.0:
		_go_map()

	# The main button reflects what you can do right now.
	match state:
		"map":
			main_btn.text = "PLAY WAVE %d" % battle.wave
			main_btn.disabled = false
		"drop":
			if round_over:
				main_btn.text = "TO BATTLE"
				main_btn.disabled = false
			elif dropped:
				main_btn.text = "DROPPING..."
				main_btn.disabled = true
			else:
				main_btn.text = "DROP ALL BALLS"
				main_btn.disabled = false
		"battle":
			if battle.active:
				main_btn.text = "FIGHTING..."
			elif returning:
				main_btn.text = "..."
			elif not battle.any_placed():
				main_btn.text = "PLACE A CAT"
			else:
				main_btn.text = "START WAVE %d" % battle.wave
			main_btn.disabled = battle.active or returning or not battle.any_placed()
	home_btn.disabled = _busy()

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# Space / Enter also works, handy when testing on desktop.
	if event.is_action_pressed("ui_accept") and not main_btn.disabled:
		_on_main_pressed()


func _on_main_pressed() -> void:
	match state:
		"map":
			_begin_round()
		"drop":
			if round_over:
				_enter_battle()
			elif not dropped:
				_drop_ball()
		"battle":
			if not returning:
				battle.start_wave()


func _drop_ball() -> void:
	# The one drop of the round: every ball goes in a quick burst from where the cat is now.
	if state != "drop" or dropped or balls_left <= 0 or dropping:
		return
	dropped = true
	dropping = true
	bonus_balls = 0
	_save_game()
	var x := drop_x
	var count := balls_left
	balls_left = 0
	for i in count:
		var jitter := Vector2(randf_range(-12.0, 12.0), randf_range(-6.0, 6.0))
		_spawn_ball(Vector2(x, FIELD.position.y + 36.0) + jitter, {}, Vector2(randf_range(-30.0, 30.0), 0.0))
		await get_tree().create_timer(DROP_STAGGER).timeout
	dropping = false


func _spawn_ball(pos: Vector2, seen: Dictionary, vel: Vector2) -> void:
	var ball = BallScript.new()
	ball.position = pos
	ball.linear_velocity = vel
	ball.gates_seen = seen.duplicate()
	add_child(ball)


func _on_gate_entered(body, idx: int) -> void:
	if not body.is_in_group("balls"):
		return
	if body.gates_seen.has(idx):
		return
	body.gates_seen[idx] = true

	var mult := gate_mult(idx)
	for i in mult - 1:
		if get_tree().get_nodes_in_group("balls").size() >= MAX_BALLS_ALIVE:
			break
		var offset := Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
		var vel: Vector2 = body.linear_velocity + Vector2(randf_range(-50.0, 50.0), 0.0)
		# Physics callbacks can't add bodies directly, so defer the spawn.
		call_deferred("_spawn_ball", body.position + offset, body.gates_seen, vel)


func _on_cup_entered(body) -> void:
	if not body.is_in_group("balls"):
		return
	coins += coins_per_ball()
	stats["balls_banked"] = int(stats["balls_banked"]) + 1
	body.queue_free()


func _on_wave_cleared(w: int) -> void:
	var reward := WAVE_COINS_PER_WAVE * w
	coins += reward
	bonus_balls += WAVE_BONUS_BALLS
	battle.set_banner_detail("+%d coins, +%d balls next drop" % [reward, WAVE_BONUS_BALLS])
	stats["best_wave"] = maxi(int(stats["best_wave"]), w)
	returning = true
	_save_game()
	_refresh_panel()
	_report(XP_PER_WAVE)


func _on_run_won() -> void:
	coins += RUN_COMPLETE_COINS
	battle.set_banner_detail("+%d coins. A new run begins." % RUN_COMPLETE_COINS)
	stats["runs_won"] = int(stats["runs_won"]) + 1
	_save_game()
	_refresh_panel()
	_report(XP_RUN_WON)


func _on_run_failed() -> void:
	returning = true


# ----------------------------------------------------------------------------
# Drawing (map, board, gates, cup, dropper and HUD are all drawn here)
# ----------------------------------------------------------------------------

func _path_point(n: int) -> Vector2:
	# Node n (1..10) climbs from the bottom of the map to the boss at the top, wiggling left and right.
	var frac := float(n - 1) / float(battle.MAX_WAVE - 1)
	return Vector2(195.0 + sin(float(n) * 1.25) * 105.0, lerpf(PATH_BOTTOM, PATH_TOP, frac))


func _draw_map(font: Font) -> void:
	draw_string(font, Vector2(16.0, 108.0), CHAPTER_TITLE, HORIZONTAL_ALIGNMENT_CENTER, 358.0, 18, COL_TEXT)
	var story_line: String = STORY[clampi(battle.wave - 1, 0, STORY.size() - 1)]
	draw_string(font, Vector2(16.0, 130.0), story_line, HORIZONTAL_ALIGNMENT_CENTER, 358.0, 13, COL_AMBER)

	var n_nodes: int = battle.MAX_WAVE
	for n in range(1, n_nodes):
		var a := _path_point(n)
		var b := _path_point(n + 1)
		draw_line(a, b, COL_EDGE, 10.0)
		if n < battle.wave:
			draw_line(a, b, COL_AMBER, 5.0)
	for n in range(1, n_nodes + 1):
		var p := _path_point(n)
		var boss: bool = n == n_nodes
		if n < battle.wave:
			draw_circle(p, 13.0, COL_EDGE)
			draw_circle(p, 11.0, COL_AMBER)
			draw_string(font, p + Vector2(-10.0, 5.0), str(n), HORIZONTAL_ALIGNMENT_CENTER, 20.0, 14, COL_EDGE)
		elif n == battle.wave:
			var pulse := 1.0 + 0.08 * sin(t * 4.0)
			draw_circle(p, 22.0 * pulse, COL_AMBER)
			draw_circle(p, 19.0 * pulse, COL_PEG)
			if battle.textures.has("macho"):
				draw_texture_rect(battle.textures["macho"], Rect2(p - Vector2(14.0, 14.0), Vector2(28.0, 28.0)), false)
			else:
				draw_string(font, p + Vector2(-10.0, 6.0), str(n), HORIZONTAL_ALIGNMENT_CENTER, 20.0, 18, COL_TEXT)
		else:
			var r := 20.0 if boss else 12.0
			draw_circle(p, r + 2.0, COL_EDGE)
			draw_circle(p, r, COL_GRAY)
			if boss:
				draw_string(font, p + Vector2(-20.0, 4.0), "BOSS", HORIZONTAL_ALIGNMENT_CENTER, 40.0, 12, COL_AMBER)
			else:
				draw_string(font, p + Vector2(-10.0, 5.0), str(n), HORIZONTAL_ALIGNMENT_CENTER, 20.0, 13, COL_MUTED)
	if bonus_balls > 0:
		draw_string(font, Vector2(16.0, 384.0), "+%d bonus balls waiting for your next drop" % bonus_balls, HORIZONTAL_ALIGNMENT_CENTER, 358.0, 13, COL_AMBER)


func _draw_board(font: Font) -> void:
	draw_rect(FIELD, COL_FIELD)

	# Funnels and cup
	draw_colored_polygon(_funnel_left(), COL_GRAY)
	draw_colored_polygon(_funnel_right(), COL_GRAY)
	draw_rect(Rect2(CUP_SENSOR.position.x, 650.0, CUP_SENSOR.size.x, 56.0), COL_CAT)
	draw_rect(CUP_WALL_LEFT, COL_AMBER)
	draw_rect(CUP_WALL_RIGHT, COL_AMBER)
	draw_rect(Rect2(CUP_WALL_LEFT.position.x, 700.0, 128.0, 6.0), COL_AMBER)
	draw_string(font, Vector2(CUP_SENSOR.position.x, 686.0), "CUP", HORIZONTAL_ALIGNMENT_CENTER, CUP_SENSOR.size.x, 18, COL_AMBER)

	# Pegs
	for p in pegs:
		draw_circle(p, 6.5, COL_EDGE)
		draw_circle(p, 5.0, COL_PEG)

	# Gates
	for i in GATES.size():
		var r: Rect2 = GATES[i]["rect"]
		var mult := gate_mult(i)
		var fill := COL_GRAY
		var text_col := COL_TEXT
		if mult >= 5:
			fill = COL_AMBER
			text_col = COL_EDGE
		elif mult >= 3:
			fill = COL_PEG
		var poly := PackedVector2Array([
			Vector2(r.position.x + 8.0, r.position.y),
			Vector2(r.end.x, r.position.y),
			Vector2(r.end.x - 8.0, r.end.y),
			Vector2(r.position.x, r.end.y),
		])
		draw_colored_polygon(poly, fill)
		draw_string(font, Vector2(r.position.x, r.position.y + 21.0), "X%d" % mult, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, text_col)

	# Field border
	draw_rect(FIELD.grow(3.0), COL_EDGE, false, 6.0)

	# Dropper: a black cat head sweeping across the top, with an aim line (until the one drop is used)
	if not dropped:
		var c := Vector2(drop_x, FIELD.position.y + 6.0)
		draw_dashed_line(c + Vector2(0.0, 28.0), c + Vector2(0.0, 150.0), Color(1.0, 1.0, 1.0, 0.35), 2.0, 6.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-24.0, -4.0), c + Vector2(-19.0, -28.0), c + Vector2(-5.0, -12.0)]), COL_CAT)
		draw_colored_polygon(PackedVector2Array([c + Vector2(24.0, -4.0), c + Vector2(19.0, -28.0), c + Vector2(5.0, -12.0)]), COL_CAT)
		draw_circle(c, 25.0, COL_EDGE)
		draw_circle(c, 23.0, COL_CAT)
		draw_rect(Rect2(c.x - 14.0, c.y - 4.0, 6.0, 14.0), COL_AMBER)
		draw_rect(Rect2(c.x + 8.0, c.y - 4.0, 6.0, 14.0), COL_AMBER)


func _draw() -> void:
	var font := ThemeDB.fallback_font

	draw_rect(Rect2(Vector2.ZERO, Vector2(390.0, 844.0)), COL_BG)
	if state == "map":
		_draw_map(font)
	elif state == "drop":
		_draw_board(font)

	# HUD
	draw_string(font, Vector2(16.0, 28.0), "COINS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT)
	draw_string(font, Vector2(16.0, 70.0), str(coins), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, COL_AMBER)
	if state == "drop":
		draw_string(font, Vector2(190.0, 28.0), "BALLS", HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 14, COL_TEXT)
		draw_string(font, Vector2(190.0, 70.0), "%d/%d" % [balls_left, balls_per_round() + (bonus_balls if not dropped else 0)], HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 40, COL_TEXT)
		if bonus_balls > 0 and not dropped:
			draw_string(font, Vector2(190.0, 90.0), "includes %d bonus" % bonus_balls, HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 13, COL_AMBER)
	else:
		draw_string(font, Vector2(190.0, 28.0), "WAVE", HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 14, COL_TEXT)
		draw_string(font, Vector2(190.0, 70.0), "%d/%d" % [battle.wave, battle.MAX_WAVE], HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 40, COL_TEXT)

	if state == "drop" and round_over:
		draw_rect(Rect2(FIELD.position.x + 20.0, 370.0, FIELD.size.x - 40.0, 90.0), Color(0.043, 0.043, 0.055, 0.9))
		draw_string(font, Vector2(FIELD.position.x, 412.0), "ROUND OVER", HORIZONTAL_ALIGNMENT_CENTER, FIELD.size.x, 44, COL_AMBER)
		draw_string(font, Vector2(FIELD.position.x, 442.0), "Now defend the house", HORIZONTAL_ALIGNMENT_CENTER, FIELD.size.x, 16, COL_MUTED)
