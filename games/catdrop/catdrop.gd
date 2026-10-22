extends GameBase
# Cat Drop: drop balls for coins, spend coins on cats and upgrades, defend the house.
# Everything is built in code so there is just one scene to open.

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

# Shop upgrades. Cost of the next level = round(base * growth ^ current_level).
const UPGRADE_ORDER := ["balls", "coin", "gates"]
const UPGRADES := {
	"balls": {"name": "MORE BALLS", "base": 50.0, "growth": 1.6, "max": 6},
	"coin": {"name": "COIN VALUE", "base": 80.0, "growth": 1.8, "max": 5},
	"gates": {"name": "BIGGER GATES", "base": 200.0, "growth": 2.5, "max": 2},
}

# --- Layout (viewport is 390 x 844) -----------------------------------------
const FIELD := Rect2(16.0, 130.0, 358.0, 590.0)
const CUP_WALL_LEFT := Rect2(131.0, 650.0, 6.0, 56.0)
const CUP_WALL_RIGHT := Rect2(253.0, 650.0, 6.0, 56.0)
const CUP_SENSOR := Rect2(137.0, 656.0, 116.0, 46.0)

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
var bonus_balls := 0
var stats := {"balls_banked": 0, "best_wave": 0, "runs_won": 0}
var balls_left := BASE_BALLS
var round_over := false
var dropping := false
var shop_open := false
var mode := "drop"          # "drop" or "battle"
var drop_x := 195.0
var t := 0.0
var pegs: Array[Vector2] = []

var battle: Node2D
var main_btn: Button
var shop_btn: Button
var home_btn: Button
var mode_btn: Button
var shop_panel: Panel
var shop_coins_label: Label
var shop_rows := {}  # "cat:macho" / "up:balls" -> {"desc","pips","buy"}


func _init() -> void:
	id = "catdrop"
	title = "Cat Drop"


func _ready() -> void:
	battle = BattleScript.new()
	battle.visible = false
	add_child(battle)
	battle.wave_cleared.connect(_on_wave_cleared)
	battle.run_won.connect(_on_run_won)
	battle.changed.connect(_on_battle_changed)

	balls_left = balls_per_round()
	_build_walls()
	_build_funnels()
	_build_pegs()
	_build_gates()
	_build_cup()
	_build_buttons()
	_build_shop()
	_refresh_shop()
	# Without a hub (editor F6, tests) load our own save; the hub calls start() itself right after adding us.
	start_standalone.call_deferred()


func _on_start() -> void:
	_load_game()
	balls_left = balls_per_round()
	_refresh_shop()


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
	# Buying more balls before the round has started adds them straight away.
	if key == "balls" and balls_left > 0 and not dropping:
		balls_left += BALLS_STEP
	_save_game()
	_refresh_shop()
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
	_refresh_shop()
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
	_refresh_shop()


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
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		if state == "pressed":
			sb.bg_color = bg.darkened(0.2)
		if state == "disabled":
			sb.bg_color = COL_GRAY
		btn.add_theme_stylebox_override(state, sb)


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build_buttons() -> void:
	main_btn = Button.new()
	main_btn.position = Vector2(16.0, 760.0)
	main_btn.size = Vector2(210.0, 56.0)
	main_btn.text = "DROP ALL BALLS"
	_style_button(main_btn, COL_AMBER, COL_EDGE, 20)
	main_btn.pressed.connect(_on_main_pressed)
	add_child(main_btn)

	shop_btn = Button.new()
	shop_btn.position = Vector2(234.0, 760.0)
	shop_btn.size = Vector2(66.0, 56.0)
	shop_btn.text = "SHOP"
	_style_button(shop_btn, COL_CAT, COL_TEXT, 18)
	shop_btn.pressed.connect(_toggle_shop)
	add_child(shop_btn)

	home_btn = Button.new()
	home_btn.position = Vector2(308.0, 760.0)
	home_btn.size = Vector2(66.0, 56.0)
	home_btn.text = "HUB"
	_style_button(home_btn, COL_CAT, COL_AMBER, 18)
	home_btn.pressed.connect(func(): quit_requested.emit())
	add_child(home_btn)

	mode_btn = Button.new()
	mode_btn.position = Vector2(132.0, 24.0)
	mode_btn.size = Vector2(124.0, 44.0)
	mode_btn.text = "BATTLE"
	_style_button(mode_btn, COL_PEG, COL_TEXT, 18)
	mode_btn.pressed.connect(_toggle_mode)
	add_child(mode_btn)


func _add_shop_row(id: String, title: String, y: float, portrait: String, with_pips: bool, max_pips: int) -> void:
	var row_bg := ColorRect.new()
	row_bg.color = Color("#16161C")
	row_bg.position = Vector2(12.0, y)
	row_bg.size = Vector2(FIELD.size.x - 24.0, 72.0)
	shop_panel.add_child(row_bg)

	var text_x := 24.0
	if portrait != "" and ResourceLoader.exists("res://games/catdrop/art/%s.png" % portrait):
		var pic := TextureRect.new()
		pic.texture = load("res://games/catdrop/art/%s.png" % portrait)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.position = Vector2(22.0, y + 12.0)
		pic.size = Vector2(48.0, 48.0)
		shop_panel.add_child(pic)
		text_x = 82.0

	var name_label := _make_label(title, 20, COL_TEXT)
	name_label.position = Vector2(text_x, y + 6.0)
	shop_panel.add_child(name_label)

	var desc := _make_label("", 13, COL_MUTED)
	desc.position = Vector2(text_x, y + 32.0)
	shop_panel.add_child(desc)

	var pips := Control.new()
	pips.position = Vector2(text_x, y + 58.0)
	shop_panel.add_child(pips)
	if with_pips:
		for p in max_pips:
			var pip := ColorRect.new()
			pip.position = Vector2(float(p) * 22.0, 0.0)
			pip.size = Vector2(18.0, 7.0)
			pips.add_child(pip)

	var buy_btn := Button.new()
	buy_btn.position = Vector2(FIELD.size.x - 24.0 - 100.0, y + 12.0)
	buy_btn.size = Vector2(100.0, 48.0)
	_style_button(buy_btn, COL_AMBER, COL_EDGE, 20)
	shop_panel.add_child(buy_btn)

	shop_rows[id] = {"desc": desc, "pips": pips, "buy": buy_btn}


func _build_shop() -> void:
	shop_panel = Panel.new()
	shop_panel.position = FIELD.position
	shop_panel.size = FIELD.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_EDGE
	sb.border_color = COL_AMBER
	sb.set_border_width_all(3)
	shop_panel.add_theme_stylebox_override("panel", sb)
	shop_panel.visible = false
	add_child(shop_panel)

	var title := _make_label("SHOP", 34, COL_AMBER)
	title.position = Vector2(16.0, 6.0)
	shop_panel.add_child(title)

	shop_coins_label = _make_label("", 22, COL_TEXT)
	shop_coins_label.position = Vector2(150.0, 14.0)
	shop_coins_label.size = Vector2(FIELD.size.x - 166.0, 30.0)
	shop_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shop_panel.add_child(shop_coins_label)

	var cats_heading := _make_label("CATS", 13, COL_MUTED)
	cats_heading.position = Vector2(16.0, 54.0)
	shop_panel.add_child(cats_heading)
	for i in battle.CAT_ORDER.size():
		var key: String = battle.CAT_ORDER[i]
		var def: Dictionary = battle.CAT_TYPES[key]
		_add_shop_row("cat:" + key, str(def["name"]), 74.0 + float(i) * 78.0, key, false, 0)
		var cat_btn: Button = shop_rows["cat:" + key]["buy"]
		cat_btn.pressed.connect(func(): buy_cat(key))

	var up_heading := _make_label("BOARD UPGRADES", 13, COL_MUTED)
	up_heading.position = Vector2(16.0, 234.0)
	shop_panel.add_child(up_heading)
	for i in UPGRADE_ORDER.size():
		var key: String = UPGRADE_ORDER[i]
		_add_shop_row("up:" + key, str(UPGRADES[key]["name"]), 254.0 + float(i) * 78.0, "", true, int(UPGRADES[key]["max"]))
		var up_btn: Button = shop_rows["up:" + key]["buy"]
		up_btn.pressed.connect(func(): buy(key))

	var close_btn := Button.new()
	close_btn.position = Vector2(12.0, FIELD.size.y - 62.0)
	close_btn.size = Vector2(FIELD.size.x - 24.0, 48.0)
	close_btn.text = "CLOSE"
	_style_button(close_btn, COL_CAT, COL_TEXT, 20)
	close_btn.pressed.connect(_toggle_shop)
	shop_panel.add_child(close_btn)


func _desc_for(key: String) -> String:
	match key:
		"balls":
			return "%d > %d balls per round" % [balls_per_round(), balls_per_round() + BALLS_STEP]
		"coin":
			return "%d > %d coins per ball" % [coins_per_ball(), coins_per_ball() + 1]
		"gates":
			return "Every gate gets +1 multiplier"
	return ""


func _refresh_shop() -> void:
	if shop_coins_label == null:
		return
	shop_coins_label.text = "%d coins" % coins

	for key in battle.CAT_ORDER:
		var row: Dictionary = shop_rows["cat:" + key]
		var buy_btn: Button = row["buy"]
		var desc: Label = row["desc"]
		var have: int = int(battle.owned[key])
		var role: String = str(battle.CAT_TYPES[key]["role"]).capitalize()
		desc.text = "%s - own %d" % [role, have]
		if not battle.can_add_cat(key):
			buy_btn.text = "MAX"
			buy_btn.disabled = true
		else:
			var cost: int = battle.cat_cost(key)
			buy_btn.text = str(cost)
			buy_btn.disabled = coins < cost

	for key in UPGRADE_ORDER:
		var row: Dictionary = shop_rows["up:" + key]
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


func _toggle_shop() -> void:
	if not shop_open and _busy():
		return
	shop_open = not shop_open
	shop_panel.visible = shop_open
	_refresh_shop()


func _busy() -> bool:
	return dropping or battle.active or not get_tree().get_nodes_in_group("balls").is_empty()


func _toggle_mode() -> void:
	if shop_open or _busy():
		return
	if mode == "drop":
		mode = "battle"
		mode_btn.text = "DROP"
	else:
		mode = "drop"
		mode_btn.text = "BATTLE"
		_collect_bonus()
	battle.visible = (mode == "battle")


func _collect_bonus() -> void:
	# Bonus balls from cleared waves join the current round if it hasn't started.
	if bonus_balls > 0 and not round_over and not dropping and balls_left > 0:
		balls_left += bonus_balls
		bonus_balls = 0
		_save_game()


# ----------------------------------------------------------------------------
# Game flow
# ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	drop_x = 195.0 + sin(t * SWEEP_SPEED) * SWEEP_RANGE

	var alive := get_tree().get_nodes_in_group("balls")

	# Clean up any ball that somehow got out of the board.
	for b in alive:
		if b.position.y > 800.0:
			b.queue_free()

	if balls_left == 0 and not dropping and not round_over and alive.is_empty():
		round_over = true
		_save_game()
		_report(XP_PER_ROUND)

	# Buttons reflect what you can do right now.
	if mode == "battle":
		if battle.active:
			main_btn.text = "FIGHTING..."
		elif not battle.any_placed():
			main_btn.text = "PLACE A CAT"
		else:
			main_btn.text = "START WAVE %d" % battle.wave
		main_btn.disabled = shop_open or battle.active or not battle.any_placed()
	else:
		main_btn.text = "NEW ROUND" if round_over else "DROP ALL BALLS"
		main_btn.disabled = shop_open
	var busy: bool = dropping or battle.active or not alive.is_empty()
	shop_btn.disabled = (not shop_open) and busy
	mode_btn.disabled = shop_open or busy
	home_btn.disabled = busy

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# Space / Enter also works, handy when testing on desktop.
	if event.is_action_pressed("ui_accept") and not shop_open:
		_on_main_pressed()


func _on_main_pressed() -> void:
	if shop_open:
		return
	if mode == "battle":
		battle.start_wave()
		return
	if round_over:
		_new_round()
	else:
		_drop_ball()


func _new_round() -> void:
	balls_left = balls_per_round() + bonus_balls
	bonus_balls = 0
	round_over = false
	_save_game()


func _drop_ball() -> void:
	# Releases every remaining ball in a quick burst from where the cat is now.
	if balls_left <= 0 or dropping:
		return
	dropping = true
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
	_save_game()
	_refresh_shop()
	_report(XP_PER_WAVE)


func _on_run_won() -> void:
	coins += RUN_COMPLETE_COINS
	battle.set_banner_detail("+%d coins. A new run begins." % RUN_COMPLETE_COINS)
	stats["runs_won"] = int(stats["runs_won"]) + 1
	_save_game()
	_refresh_shop()
	_report(XP_RUN_WON)


# ----------------------------------------------------------------------------
# Drawing (board, gates, cup, dropper and HUD are all drawn here)
# ----------------------------------------------------------------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font

	draw_rect(Rect2(Vector2.ZERO, Vector2(390.0, 844.0)), COL_BG)
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

	# Dropper: a black cat head sweeping across the top, with an aim line
	if mode == "drop" and not shop_open:
		var c := Vector2(drop_x, FIELD.position.y + 6.0)
		draw_dashed_line(c + Vector2(0.0, 28.0), c + Vector2(0.0, 150.0), Color(1.0, 1.0, 1.0, 0.35), 2.0, 6.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-24.0, -4.0), c + Vector2(-19.0, -28.0), c + Vector2(-5.0, -12.0)]), COL_CAT)
		draw_colored_polygon(PackedVector2Array([c + Vector2(24.0, -4.0), c + Vector2(19.0, -28.0), c + Vector2(5.0, -12.0)]), COL_CAT)
		draw_circle(c, 25.0, COL_EDGE)
		draw_circle(c, 23.0, COL_CAT)
		draw_rect(Rect2(c.x - 14.0, c.y - 4.0, 6.0, 14.0), COL_AMBER)
		draw_rect(Rect2(c.x + 8.0, c.y - 4.0, 6.0, 14.0), COL_AMBER)

	# HUD
	draw_string(font, Vector2(16.0, 28.0), "COINS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT)
	draw_string(font, Vector2(16.0, 70.0), str(coins), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, COL_AMBER)
	if mode == "battle":
		draw_string(font, Vector2(190.0, 28.0), "WAVE", HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 14, COL_TEXT)
		draw_string(font, Vector2(190.0, 70.0), "%d/%d" % [battle.wave, battle.MAX_WAVE], HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 40, COL_TEXT)
	else:
		draw_string(font, Vector2(190.0, 28.0), "BALLS", HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 14, COL_TEXT)
		draw_string(font, Vector2(190.0, 70.0), "%d/%d" % [balls_left, balls_per_round()], HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 40, COL_TEXT)
		if bonus_balls > 0:
			draw_string(font, Vector2(190.0, 90.0), "+%d bonus next round" % bonus_balls, HORIZONTAL_ALIGNMENT_RIGHT, 184.0, 13, COL_AMBER)

	if mode == "drop" and round_over:
		draw_rect(Rect2(FIELD.position.x + 20.0, 370.0, FIELD.size.x - 40.0, 90.0), Color(0.043, 0.043, 0.055, 0.9))
		draw_string(font, Vector2(FIELD.position.x, 412.0), "ROUND OVER", HORIZONTAL_ALIGNMENT_CENTER, FIELD.size.x, 44, COL_AMBER)
		draw_string(font, Vector2(FIELD.position.x, 442.0), "Shop, battle, or go again", HORIZONTAL_ALIGNMENT_CENTER, FIELD.size.x, 16, COL_MUTED)
