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
const BASE_BALLS := 5             # balls per round before any upgrades
const BALLS_STEP := 1             # extra balls per "more balls" level
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
	"balls": {"name": "MORE BALLS", "base": 60.0, "growth": 1.7, "max": 5},
	"coin": {"name": "COIN VALUE", "base": 80.0, "growth": 1.8, "max": 5},
	"gates": {"name": "BIG GATES", "base": 400.0, "growth": 2.5, "max": 1},
}

# Progression: cats unlock as you clear waves, and the team can only grow as you push further.
const CAT_UNLOCK_WAVE := {"macho": 0, "rosette": 2, "adora": 4}   # waves you must have cleared before the cat can be bought
const TEAM_BASE := 2                                   # cats you may own at the start; +1 for every wave cleared

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
const PATH_TOP := 184.0
const PATH_BOTTOM := 362.0

# Each gate multiplies any ball that falls through it.
const GATES := [
	{"rect": Rect2(30.0, 330.0, 100.0, 28.0), "mult": 2},
	{"rect": Rect2(260.0, 330.0, 100.0, 28.0), "mult": 2},
	{"rect": Rect2(145.0, 440.0, 100.0, 28.0), "mult": 3},
	{"rect": Rect2(30.0, 540.0, 100.0, 28.0), "mult": 2},
	{"rect": Rect2(260.0, 540.0, 100.0, 28.0), "mult": 2},
]

# --- Colours (crimson / black / amber) ---------------------------------------
const COL_BG := Color("#1E121F")
const COL_FIELD := Color("#101015")
const COL_EDGE := Color("#0B0B0E")
const COL_PEG := Color("#FF2E93")
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
var map_rows := {}  # "cat:macho" / "up:balls" -> {"desc", "pips", "buy", "lvl", "badge"}
var fx := Fx.new()
var team_label: Label
var shown_coins := 0.0      # the coin counter counts up towards `coins`
var shake := 0.0
var shaking := false
var peg_lookup := {}        # rounded peg position -> peg position, to find the peg a ball touched
var peg_fx := {}            # rounded peg position -> {t, off}: a flash and a small wobble after a hit
var cup_dip := 0.0
var cup_flash := 0.0        # the cup frame flashes when a ball lands          # the cup dips when it catches a ball
var glow_layer: Node2D      # additive light halos (pegs, gates, cup, balls)
var cup_squash := 0.0       # the cup squashes and shakes for 150ms when a ball lands
var coin_pulse := 0.0       # the coin counter pops when coins increase
var last_coins := 0
var dropper_tex: Texture2D  # the launcher cat's poses (idle, release, drop, celebration), if the art exists
var dropper_x := 195.0      # where the cat stood when the drop was made
var drop_anim_t := 99.0     # seconds since the drop started
var gate_flash := [0.0, 0.0, 0.0, 0.0, 0.0]
var path_curve := Curve2D.new()
var path_offsets: Array = []


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
	battle.shake.connect(kick)

	balls_left = balls_per_round()
	_build_walls()
	_build_funnels()
	_build_pegs()
	for p in pegs:
		peg_lookup[Vector2i(roundi(p.x), roundi(p.y))] = p
	_build_gates()
	_build_cup()
	_build_path()
	_build_buttons()
	if ResourceLoader.exists("res://games/catdrop/art/dropper_anim.png"):
		dropper_tex = load("res://games/catdrop/art/dropper_anim.png")
	_build_map_panel()
	glow_layer = Node2D.new()
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_layer.material = glow_mat
	glow_layer.draw.connect(_draw_glow)
	add_child(glow_layer)
	_refresh_panel()
	_apply_state()
	# Without a hub (editor F6, tests) load our own save; the hub calls start() itself right after adding us.
	start_standalone.call_deferred()


func _on_start() -> void:
	_load_game()
	shown_coins = float(coins)
	last_coins = coins
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


func cat_unlocked(key: String) -> bool:
	return int(stats["best_wave"]) >= int(CAT_UNLOCK_WAVE.get(key, 0))


func team_size() -> int:
	var n := 0
	for k in battle.CAT_ORDER:
		n += int(battle.owned[k])
	return n


func team_cap() -> int:
	return TEAM_BASE + int(stats["best_wave"])


func buy_cat(key: String) -> bool:
	if not cat_unlocked(key) or team_size() >= team_cap() or not battle.can_add_cat(key):
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
	if not cat_unlocked(key) or not battle.can_level(key):
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
	UIKit.style_button(btn, bg, fg, size)


func _make_label(text: String, size: int, color: Color, heavy: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if heavy:
		l.add_theme_font_override("font", UIKit.heavy())
		l.add_theme_color_override("font_outline_color", UIKit.INK)
		l.add_theme_constant_override("outline_size", 5)
	return l


func _build_buttons() -> void:
	main_btn = Button.new()
	main_btn.position = Vector2(16.0, 756.0)
	main_btn.size = Vector2(284.0, 62.0)
	main_btn.text = "PLAY WAVE 1"
	_style_button(main_btn, COL_AMBER, COL_EDGE, 24)
	main_btn.material = Polish.shine_material()
	main_btn.pivot_offset = main_btn.size * 0.5
	main_btn.pressed.connect(_on_main_pressed)
	add_child(main_btn)

	home_btn = Button.new()
	home_btn.position = Vector2(308.0, 756.0)
	home_btn.size = Vector2(66.0, 62.0)
	home_btn.text = "HUB"
	_style_button(home_btn, UIKit.INK_SOFT, COL_AMBER, 18)
	home_btn.pressed.connect(func(): quit_requested.emit())
	add_child(home_btn)


func _add_row(id_: String, title_: String, y: float, portrait: String, max_pips: int, two_buttons: bool) -> void:
	var card := Panel.new()
	card.position = Vector2(10.0, y)
	card.size = Vector2(MAP_PANEL.size.x - 20.0, ROW_H)
	card.add_theme_stylebox_override("panel", UIKit.baked("card_small", UIKit.BAKED_MARGIN["card_small"]) if UIKit.baked("card_small", UIKit.BAKED_MARGIN["card_small"]) != null else UIKit.box(Color("#322A3B"), UIKit.INK, 3, 12, 0, 5))
	map_panel.add_child(card)

	var text_x := 20.0
	var badge: Label = null
	var art_path := "res://games/catdrop/art/%s.png" % portrait
	if portrait != "" and ResourceLoader.exists(art_path):
		var frame := Panel.new()
		frame.position = Vector2(16.0, y + 5.0)
		frame.size = Vector2(44.0, 44.0)
		frame.add_theme_stylebox_override("panel", UIKit.box(UIKit.CRIMSON, UIKit.AMBER, 3, 8))
		map_panel.add_child(frame)
		var pic := TextureRect.new()
		pic.texture = load(art_path)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.position = Vector2(19.0, y + 8.0)
		pic.size = Vector2(38.0, 38.0)
		map_panel.add_child(pic)
		badge = UIKit.label(map_panel, Rect2(34.0, y + 36.0, 28.0, 15.0), "", 10, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER, false)
		badge.add_theme_stylebox_override("normal", UIKit.box(UIKit.GOLD, UIKit.INK, 2, 7))
		badge.add_theme_font_override("font", UIKit.heavy())
		text_x = 70.0

	var name_label := UIKit.label(map_panel, Rect2(text_x, y + 2.0, 150.0, 24.0), title_, 18, UIKit.CREAM)
	name_label.name = "Name"
	pass

	var desc := UIKit.label(map_panel, Rect2(text_x, y + 26.0, 150.0, 16.0), "", 12, COL_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	desc.name = "Desc"
	pass

	var pips := Control.new()
	pips.position = Vector2(text_x, y + 43.0)
	map_panel.add_child(pips)
	for p in max_pips:
		var pip := Panel.new()
		pip.position = Vector2(float(p) * 22.0, 0.0)
		pip.size = Vector2(19.0, 8.0)
		pips.add_child(pip)

	var btn_x := MAP_PANEL.size.x - 20.0 - 104.0 + 6.0
	var buy_btn := Button.new()
	buy_btn.position = Vector2(btn_x, y + (3.0 if two_buttons else 6.0))
	buy_btn.size = Vector2(104.0, 24.0 if two_buttons else 42.0)
	_style_button(buy_btn, COL_AMBER, COL_EDGE, 14 if two_buttons else 20)
	map_panel.add_child(buy_btn)

	var lvl_btn: Button = null
	if two_buttons:
		lvl_btn = Button.new()
		lvl_btn.position = Vector2(btn_x, y + 28.0)
		lvl_btn.size = Vector2(104.0, 24.0)
		_style_button(lvl_btn, UIKit.GREEN, COL_EDGE, 13)
		map_panel.add_child(lvl_btn)

	map_rows[id_] = {"desc": desc, "pips": pips, "buy": buy_btn, "lvl": lvl_btn, "badge": badge}
	if portrait != "":
		var lock_overlay := Control.new()
		lock_overlay.position = Vector2(16.0, y + 5.0)
		lock_overlay.size = Vector2(44.0, 44.0)
		lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_overlay.visible = false
		lock_overlay.draw.connect(func():
			lock_overlay.draw_style_box(UIKit.box(Color(0.05, 0.03, 0.08, 0.78), Color(0, 0, 0, 0), 0, 8), Rect2(Vector2.ZERO, lock_overlay.size))
			UIKit.lock(lock_overlay, Vector2(22.0, 20.0), 9.0, UIKit.MUTED))
		map_panel.add_child(lock_overlay)
		map_rows[id_]["lock"] = lock_overlay


func _add_up_card(key: String, x: float, y: float) -> void:
	var card := Panel.new()
	card.position = Vector2(x, y)
	card.size = Vector2(110.0, 70.0)
	card.add_theme_stylebox_override("panel", UIKit.baked("card_small", UIKit.BAKED_MARGIN["card_small"]) if UIKit.baked("card_small", UIKit.BAKED_MARGIN["card_small"]) != null else UIKit.box(Color("#322A3B"), UIKit.INK, 3, 12, 0, 5))
	map_panel.add_child(card)
	var name_label := UIKit.label(map_panel, Rect2(x + 6.0, y + 2.0, 98.0, 16.0), str(UPGRADES[key]["name"]), 12, UIKit.CREAM)
	name_label.name = "Name"
	pass
	var desc := UIKit.label(map_panel, Rect2(x + 7.0, y + 17.0, 98.0, 13.0), "", 10, COL_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	desc.name = "Desc"
	pass
	var pips := Control.new()
	pips.position = Vector2(x + 7.0, y + 31.0)
	map_panel.add_child(pips)
	var max_pips: int = int(UPGRADES[key]["max"])
	for p in max_pips:
		var pip := Panel.new()
		pip.position = Vector2(float(p) * (95.0 / float(max_pips)), 0.0)
		pip.size = Vector2(95.0 / float(max_pips) - 3.0, 7.0)
		pips.add_child(pip)
	var buy_btn := Button.new()
	buy_btn.position = Vector2(x + 5.0, y + 42.0)
	buy_btn.size = Vector2(100.0, 24.0)
	_style_button(buy_btn, COL_AMBER, COL_EDGE, 15)
	map_panel.add_child(buy_btn)
	map_rows["up:" + key] = {"desc": desc, "pips": pips, "buy": buy_btn, "lvl": null, "badge": null}


func _build_map_panel() -> void:
	map_panel = Panel.new()
	map_panel.position = MAP_PANEL.position
	map_panel.size = MAP_PANEL.size
	map_panel.add_theme_stylebox_override("panel", UIKit.baked("panel", UIKit.BAKED_MARGIN["panel"]) if UIKit.baked("panel", UIKit.BAKED_MARGIN["panel"]) != null else UIKit.box(Color("#221B29"), UIKit.GOLD, 4, 18, 3, 14))
	add_child(map_panel)

	team_label = UIKit.label(map_panel, Rect2(14.0, 5.0, 330.0, 16.0), "YOUR CATS", 12, UIKit.GOLD)
	team_label.name = "TeamLabel"
	pass
	for i in battle.CAT_ORDER.size():
		var key: String = battle.CAT_ORDER[i]
		var def: Dictionary = battle.CAT_TYPES[key]
		_add_row("cat:" + key, str(def["name"]), 22.0 + float(i) * ROW_STEP, key, 0, true)
		var cat_btn: Button = map_rows["cat:" + key]["buy"]
		cat_btn.pressed.connect(func(): buy_cat(key))
		var lvl_btn: Button = map_rows["cat:" + key]["lvl"]
		lvl_btn.pressed.connect(func(): upgrade_cat(key))

	var up_y := 22.0 + float(battle.CAT_ORDER.size()) * ROW_STEP
	var up_heading := UIKit.label(map_panel, Rect2(14.0, up_y - 7.0, 330.0, 16.0), "BOARD UPGRADES", 12, UIKit.GOLD)
	up_heading.name = "UpHeading"
	pass
	for i in UPGRADE_ORDER.size():
		var key: String = UPGRADE_ORDER[i]
		_add_up_card(key, 10.0 + float(i) * 115.0, up_y + 16.0)
		var up_btn: Button = map_rows["up:" + key]["buy"]
		up_btn.pressed.connect(func(): buy(key))


func _desc_for(key: String) -> String:
	match key:
		"balls":
			return "%d > %d balls" % [balls_per_round(), balls_per_round() + BALLS_STEP]
		"coin":
			return "%d > %d coins/ball" % [coins_per_ball(), coins_per_ball() + 1]
		"gates":
			return "+1 on every gate"
	return ""


func _refresh_panel() -> void:
	if map_panel == null:
		return
	team_label.text = "YOUR CATS   team %d/%d  (clear waves to grow it)" % [team_size(), team_cap()]

	for key in battle.CAT_ORDER:
		var row: Dictionary = map_rows["cat:" + key]
		var buy_btn: Button = row["buy"]
		var lvl_btn: Button = row["lvl"]
		var desc: Label = row["desc"]
		if row.has("lock"):
			(row["lock"] as Control).visible = false
		var role: String = str(battle.CAT_TYPES[key]["role"]).capitalize()
		desc.text = "%s  -  own %d" % [role, int(battle.owned[key])]
		(row["badge"] as Label).text = "Lv %d" % int(battle.cat_levels[key])
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
		if not cat_unlocked(key):
			desc.text = "Clear wave %d to unlock" % int(CAT_UNLOCK_WAVE[key])
			if row.has("lock"):
				(row["lock"] as Control).visible = true
			buy_btn.text = "LOCKED"
			buy_btn.disabled = true
			lvl_btn.text = "LOCKED"
			lvl_btn.disabled = true
		elif buy_btn.text != "MAX CATS" and team_size() >= team_cap():
			buy_btn.text = "TEAM FULL"
			buy_btn.disabled = true

	for key in UPGRADE_ORDER:
		var row: Dictionary = map_rows["up:" + key]
		var lvl: int = int(levels[key])
		var pips: Control = row["pips"]
		for p in pips.get_child_count():
			(pips.get_child(p) as Panel).add_theme_stylebox_override("panel", UIKit.box(UIKit.PINK if p < lvl else UIKit.GRAY, UIKit.INK, 2, 4))
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
	UIKit.pop_in(map_panel, 0.94, 0.25)
	_save_game()


func _begin_round() -> void:
	# The round's balls are counted now; bonus balls are only spent when they are dropped.
	state = "drop"
	dropped = false
	round_over = false
	balls_left = balls_per_round() + bonus_balls
	drop_anim_t = 99.0
	_apply_state()


func _enter_battle() -> void:
	state = "battle"
	returning = false
	_apply_state()


func _busy() -> bool:
	return dropping or battle.active or not get_tree().get_nodes_in_group("balls").is_empty()


func _exit_tree() -> void:
	if shaking and get_viewport() != null:
		get_viewport().canvas_transform = Transform2D.IDENTITY


func kick(amount: float) -> void:
	shake = minf(maxf(shake, amount), 9.0)


func _process(delta: float) -> void:
	t += delta
	drop_x = 195.0 + sin(t * SWEEP_SPEED) * SWEEP_RANGE
	shown_coins = move_toward(shown_coins, float(coins), maxf(2.0, absf(float(coins) - shown_coins) * 6.0 * delta))
	fx.update(delta)
	glow_layer.visible = (state == "drop")
	if glow_layer.visible:
		glow_layer.queue_redraw()
	drop_anim_t += delta
	for k in peg_fx.keys():
		peg_fx[k]["t"] = float(peg_fx[k]["t"]) - delta
		if float(peg_fx[k]["t"]) <= 0.0:
			peg_fx.erase(k)
	cup_dip = move_toward(cup_dip, 0.0, 18.0 * delta)
	cup_flash = maxf(cup_flash - delta, 0.0)
	cup_squash = maxf(cup_squash - delta, 0.0)
	if coins > last_coins:
		coin_pulse = 1.0
	last_coins = coins
	coin_pulse = maxf(coin_pulse - delta * 5.0, 0.0)
	for i in gate_flash.size():
		gate_flash[i] = maxf(0.0, float(gate_flash[i]) - delta)
	shake = move_toward(shake, 0.0, 22.0 * delta)
	# Shake the whole view through the canvas transform; moving this node would drag the physics bodies with it.
	if shake > 0.05:
		get_viewport().canvas_transform = Transform2D(0.0, Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake)
		shaking = true
	elif shaking:
		get_viewport().canvas_transform = Transform2D.IDENTITY
		shaking = false
	# The play button breathes on the map so it reads as the thing to press
	if not main_btn.button_pressed:
		main_btn.scale = Vector2.ONE * (1.0 + 0.025 * sin(t * 4.0)) if (state == "map" and not main_btn.disabled) else Vector2.ONE

	var alive := get_tree().get_nodes_in_group("balls")

	# Clean up any ball that somehow got out of the board.
	for b in alive:
		if b.position.y > 800.0:
			b.queue_free()

	if state == "drop" and dropped and balls_left == 0 and not dropping and not round_over and alive.is_empty():
		round_over = true
		_celebrate_cup()
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
	drop_anim_t = 0.0
	dropper_x = drop_x
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


func _spawn_ball(pos: Vector2, seen: Dictionary, vel: Vector2, pop: bool = false) -> void:
	var ball = BallScript.new()
	ball.position = pos
	ball.linear_velocity = vel
	ball.gates_seen = seen.duplicate()
	ball.hit.connect(_on_ball_hit)
	if pop:
		ball.pop_t = 0.25
	add_child(ball)


func _on_gate_entered(body, idx: int) -> void:
	if not body.is_in_group("balls"):
		return
	if body.gates_seen.has(idx):
		return
	body.gates_seen[idx] = true

	var mult := gate_mult(idx)
	var grect: Rect2 = GATES[idx]["rect"]
	gate_flash[idx] = 0.3
	fx.ring(body.position, UIKit.AMBER if mult >= 5 else UIKit.PINK, 8.0, 46.0, 0.4)
	if randi() % 2 == 0:
		fx.popup(body.position + Vector2(0.0, -16.0), "+%d" % (mult - 1), UIKit.CREAM, 15, 0.55)
	fx.burst(body.position, UIKit.AMBER if mult >= 5 else UIKit.PINK, 8, 150.0, 0.45, 3.0, 200.0)
	if mult >= 5:
		kick(1.4)
		fx.popup(grect.get_center() + Vector2(0.0, -22.0), "X%d!" % mult, UIKit.AMBER, 20, 0.7)
	for i in mult - 1:
		if get_tree().get_nodes_in_group("balls").size() >= MAX_BALLS_ALIVE:
			break
		var offset := Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
		var vel: Vector2 = body.linear_velocity + Vector2(randf_range(-50.0, 50.0), 0.0)
		# Physics callbacks can't add bodies directly, so defer the spawn.
		call_deferred("_spawn_ball", body.position + offset, body.gates_seen, vel, true)


func _on_cup_entered(body) -> void:
	if not body.is_in_group("balls"):
		return
	coins += coins_per_ball()
	stats["balls_banked"] = int(stats["balls_banked"]) + 1
	cup_dip = minf(cup_dip + 2.5, 6.0)
	cup_flash = 0.25
	cup_squash = 0.15
	fx.burst(Vector2(body.position.x, CUP_SENSOR.position.y), UIKit.AMBER, 4, 110.0, 0.35, 2.6, 400.0)
	if randi() % 3 == 0:
		fx.popup(Vector2(CUP_SENSOR.get_center().x + randf_range(-30.0, 30.0), CUP_SENSOR.position.y - 8.0), "+%d" % coins_per_ball(), UIKit.AMBER, 15, 0.55)
	body.queue_free()


func _on_ball_hit(pos: Vector2) -> void:
	var key := Vector2i(roundi(pos.x), roundi(pos.y))
	if not peg_lookup.has(key):
		return
	peg_fx[key] = {"t": 0.10, "off": Vector2.from_angle(randf() * TAU) * 2.5}
	if randf() < 0.5:
		fx.burst(pos, Color("#FFD1E0"), 3, 110.0, 0.25, 2.0, 0.0)


func _celebrate_cup() -> void:
	var c := Vector2(CUP_SENSOR.get_center().x, CUP_SENSOR.position.y)
	fx.ring(c, UIKit.AMBER, 10.0, 90.0, 0.6)
	for col in [UIKit.AMBER, UIKit.PINK, UIKit.CREAM, Color("#6FD3FF")]:
		fx.burst(c, col, 14, 260.0, 0.9, 3.5, 380.0)
	fx.popup(c + Vector2(0.0, -30.0), "CUP!", UIKit.GOLD, 40, 0.9, true)
	kick(3.5)


func _on_wave_cleared(w: int) -> void:
	var reward := WAVE_COINS_PER_WAVE * w
	coins += reward
	bonus_balls += WAVE_BONUS_BALLS
	battle.set_banner_detail("+%d coins, +%d balls next drop" % [reward, WAVE_BONUS_BALLS])
	kick(5.0)
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
	return Vector2(195.0 + sin(float(n) * 1.25) * 100.0, lerpf(PATH_BOTTOM, PATH_TOP, frac))


func _build_path() -> void:
	# A smooth curve through the ten nodes (Catmull-Rom style tangents), used for the road.
	var pts: Array[Vector2] = []
	for n in range(1, battle.MAX_WAVE + 1):
		pts.append(_path_point(n))
	path_curve = Curve2D.new()
	for i in pts.size():
		var tangent := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]) / 6.0
		path_curve.add_point(pts[i], -tangent, tangent)
	path_offsets.clear()
	for p in pts:
		path_offsets.append(path_curve.get_closest_offset(p))


func _draw_wallpaper() -> void:
	UIKit.gradient(self, Rect2(0.0, 0.0, 390.0, 844.0), Color("#2C1833"), UIKit.PLUM)
	var x := -6.0
	while x < 390.0:
		draw_rect(Rect2(x, 0.0, 14.0, 844.0), Color(1.0, 1.0, 1.0, 0.008))
		x += 28.0
	# a faint magenta glow behind the content
	for i in 5:
		draw_circle(Vector2(195.0, 300.0), 260.0 - float(i) * 40.0, Color(UIKit.PINK, 0.012))


func _draw_cheese(c: Vector2, s: float) -> void:
	var pts := PackedVector2Array([c + Vector2(-1.0, 0.6) * s, c + Vector2(1.0, 0.6) * s, c + Vector2(1.0, -0.2) * s, c + Vector2(-1.0, -0.9) * s])
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	draw_colored_polygon(pts, Color("#F2C230"))
	draw_polyline(outline, UIKit.INK, 3.0, true)
	draw_circle(c + Vector2(0.3, 0.2) * s, s * 0.17, Color("#C99A12"))
	draw_circle(c + Vector2(-0.45, 0.35) * s, s * 0.12, Color("#C99A12"))


func _draw_map(font: Font) -> void:
	# Scenery: paw prints, cheese and a mouse hole
	for p in [Vector2(40.0, 230.0), Vector2(348.0, 205.0), Vector2(52.0, 318.0), Vector2(338.0, 330.0), Vector2(320.0, 258.0)]:
		UIKit.paw(self, p, 9.0, Color(0.0, 0.0, 0.0, 0.14))
	_draw_cheese(Vector2(44.0, 268.0), 17.0)
	_draw_cheese(Vector2(344.0, 292.0), 14.0)
	draw_circle(Vector2(350.0, 186.0), 20.0, UIKit.INK)
	draw_circle(Vector2(350.0, 190.0), 15.0, Color("#1B0710"))

	# Title and story strip
	UIKit.card(self, Rect2(14.0, 86.0, 362.0, 52.0), Color("#33283B"), Color("#1A131F"), UIKit.INK, 14)
	UIKit.text_in(self, Rect2(14.0, 88.0, 362.0, 26.0), CHAPTER_TITLE, 15, UIKit.GOLD, UIKit.INK, 4, HORIZONTAL_ALIGNMENT_CENTER)
	var story_line: String = STORY[clampi(battle.wave - 1, 0, STORY.size() - 1)]
	UIKit.body_in(self, Rect2(14.0, 112.0, 362.0, 24.0), story_line, 13, UIKit.CREAM, HORIZONTAL_ALIGNMENT_CENTER)

	# The road
	var baked := path_curve.get_baked_points()
	draw_polyline(baked, UIKit.INK, 40.0, true)
	draw_polyline(baked, Color("#3E2646"), 32.0, true)
	draw_polyline(baked, Color(1.0, 1.0, 1.0, 0.05), 24.0, true)
	var j := 0
	while j + 3 < baked.size():
		draw_line(baked[j], baked[j + 3], Color(UIKit.CREAM, 0.22), 3.0)
		j += 8
	var cur: int = clampi(battle.wave, 1, battle.MAX_WAVE)
	var done_idx: int = int(float(path_offsets[cur - 1]) / maxf(path_curve.bake_interval, 0.01))
	if done_idx > 1:
		var done_pts := baked.slice(0, mini(done_idx + 1, baked.size()))
		draw_polyline(done_pts, Color(UIKit.GOLD, 0.25), 16.0, true)
		draw_polyline(done_pts, UIKit.AMBER_DARK, 12.0, true)
		draw_polyline(done_pts, UIKit.GOLD, 7.0, true)

	# Nodes
	var n_nodes: int = battle.MAX_WAVE
	for n in range(1, n_nodes + 1):
		var p := _path_point(n)
		var boss: bool = n == n_nodes
		if n < battle.wave:
			draw_circle(p, 15.0, UIKit.INK)
			draw_circle(p, 12.0, UIKit.GOLD)
			UIKit.star(self, p, 8.0, UIKit.CREAM)
		elif n == battle.wave:
			var pulse := 1.0 + 0.1 * sin(t * 4.0)
			draw_circle(p, 34.0 * pulse, Color(UIKit.PINK, 0.16))
			draw_circle(p, 29.0 * pulse, Color(UIKit.PINK, 0.26))
			draw_circle(p, 24.0, UIKit.INK)
			draw_circle(p, 21.0, UIKit.GOLD)
			draw_circle(p, 17.0, UIKit.PINK)
			UIKit.text_in(self, Rect2(p - Vector2(20.0, 20.0), Vector2(40.0, 40.0)), str(n), 22, UIKit.CREAM, UIKit.INK, 5, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			var r := 21.0 if boss else 14.0
			draw_circle(p, r + 3.0, UIKit.INK)
			draw_circle(p, r, UIKit.GRAY)
			if boss:
				UIKit.crown(self, p + Vector2(0.0, -2.0), 11.0, UIKit.AMBER)
			else:
				UIKit.text_in(self, Rect2(p - Vector2(14.0, 14.0), Vector2(28.0, 28.0)), str(n), 15, UIKit.MUTED, UIKit.INK, 4, HORIZONTAL_ALIGNMENT_CENTER)
		if boss and n <= battle.wave:
			UIKit.crown(self, p + Vector2(0.0, -34.0), 12.0, UIKit.AMBER)
	# Macho marks the next wave, bobbing above its node
	var here := _path_point(cur)
	var bob := sin(t * 3.0) * 3.0
	var frame := Rect2(here + Vector2(-20.0, -70.0 + bob), Vector2(40.0, 40.0))
	UIKit.panel(self, frame, UIKit.CRIMSON, UIKit.GOLD, 3, 9)
	if battle.textures.has("macho"):
		draw_texture_rect(battle.textures["macho"], frame.grow(-4.0), false)
	draw_colored_polygon(PackedVector2Array([here + Vector2(-7.0, -29.0 + bob), here + Vector2(7.0, -29.0 + bob), here + Vector2(0.0, -21.0 + bob)]), UIKit.AMBER)
	if bonus_balls > 0:
		UIKit.text_in(self, Rect2(16.0, 372.0, 358.0, 22.0), "+%d bonus balls waiting" % bonus_balls, 13, UIKit.GOLD, UIKit.INK, 4, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_dropper() -> void:
	if dropper_tex != null:
		var dx := dropper_x if dropped else drop_x
		var cc := Vector2(dx, FIELD.position.y + 14.0 + (sin(t * 3.0) * 1.5 if not dropped else 0.0))
		if not dropped:
			draw_dashed_line(cc + Vector2(0.0, 34.0), cc + Vector2(0.0, 150.0), Color(UIKit.AMBER, 0.55), 3.0, 8.0)
		var frame := 0
		if round_over:
			frame = 3
		elif dropped:
			frame = 2 if drop_anim_t < 0.35 else 1
		var k := 0.78 * ((1.0 + 0.06 * sin(t * 12.0)) if round_over else 1.0)
		var size := Vector2(112.0, 96.0) * k
		draw_texture_rect_region(dropper_tex, Rect2(cc - size * 0.5, size), Rect2(Vector2(float(frame) * 112.0, 0.0), Vector2(112.0, 96.0)))
		return
	var c := Vector2(drop_x, FIELD.position.y + 6.0)
	draw_dashed_line(c + Vector2(0.0, 30.0), c + Vector2(0.0, 160.0), Color(UIKit.AMBER, 0.55), 3.0, 8.0)
	# ears
	for sx in [-1.0, 1.0]:
		var ear := PackedVector2Array([c + Vector2(sx * 25.0, -2.0), c + Vector2(sx * 21.0, -31.0), c + Vector2(sx * 5.0, -14.0)])
		var ear_out: PackedVector2Array = ear.duplicate()
		ear_out.append(ear[0])
		draw_colored_polygon(ear, COL_CAT)
		draw_polyline(ear_out, UIKit.INK, 3.0, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(sx * 20.0, -6.0), c + Vector2(sx * 18.0, -22.0), c + Vector2(sx * 9.0, -13.0)]), UIKit.PINK)
	# spiked collar
	for k in 5:
		var cx := c.x - 20.0 + float(k) * 10.0
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 4.0, c.y + 22.0), Vector2(cx + 4.0, c.y + 22.0), Vector2(cx, c.y + 33.0)]), UIKit.AMBER)
	draw_circle(c, 27.0, UIKit.INK)
	draw_circle(c, 24.0, COL_CAT)
	# grumpy amber eyes with slit pupils and angry brows
	for sx in [-1.0, 1.0]:
		var e := c + Vector2(sx * 10.0, 1.0)
		draw_circle(e, 7.0, UIKit.INK)
		draw_circle(e, 5.5, UIKit.AMBER)
		draw_rect(Rect2(e.x - 1.0, e.y - 4.5, 2.0, 9.0), UIKit.INK)
		draw_line(e + Vector2(-sx * 6.0, -9.0), e + Vector2(sx * 7.0, -5.0), UIKit.INK, 3.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-3.0, 10.0), c + Vector2(3.0, 10.0), c + Vector2(0.0, 14.0)]), UIKit.PINK)


func _draw_board() -> void:
	UIKit.board_frame(self, FIELD, UIKit.PINK, t)

	# Funnels
	for f: PackedVector2Array in [_funnel_left(), _funnel_right()]:
		var outline: PackedVector2Array = f.duplicate()
		outline.append(f[0])
		draw_colored_polygon(f, Color("#3C3346"))
		draw_polyline(outline, UIKit.INK, 4.0, true)

	# The cup: a glowing gold-framed receptacle that dips and flashes when a ball lands
	var flash := cup_flash / 0.25
	var cq := cup_squash / 0.15
	var csx := 1.0 + 0.1 * cq
	var csy := 1.0 - 0.2 * cq
	var cpiv := Vector2(CUP_SENSOR.get_center().x, 706.0)
	draw_set_transform_matrix(Transform2D(Vector2(csx, 0.0), Vector2(0.0, csy), cpiv - Vector2(csx * cpiv.x, csy * cpiv.y) + Vector2(sin(t * 70.0) * 3.0 * cq, cup_dip)))
	var cup_rect := Rect2(CUP_SENSOR.position.x - 6.0, 646.0, CUP_SENSOR.size.x + 12.0, 64.0)
	UIKit.glow_rect(self, cup_rect, UIKit.GOLD, 10, 0.55 + 0.9 * flash)
	draw_rect(Rect2(CUP_SENSOR.position.x, 650.0, CUP_SENSOR.size.x, 56.0), Color("#26152B").lerp(Color("#6B4A12"), flash * 0.8))
	draw_rect(CUP_WALL_LEFT, UIKit.GOLD)
	draw_rect(CUP_WALL_RIGHT, UIKit.GOLD)
	draw_rect(Rect2(CUP_WALL_LEFT.position.x, 700.0, 128.0, 6.0), UIKit.GOLD)
	UIKit.text_in(self, Rect2(CUP_SENSOR.position.x, 650.0, CUP_SENSOR.size.x, 56.0), "CUP", 20, UIKit.GOLD.lerp(Color.WHITE, flash), UIKit.INK, 5, HORIZONTAL_ALIGNMENT_CENTER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Pegs, with a soft glow
	for p in pegs:
		var key := Vector2i(roundi(p.x), roundi(p.y))
		var pp: Vector2 = p
		var pf := 0.0
		if peg_fx.has(key):
			pf = float(peg_fx[key]["t"]) / 0.10
			pp += Vector2(peg_fx[key]["off"]) * pf
		draw_circle(pp, 11.0 + 3.0 * pf, Color(COL_PEG, 0.10 + 0.25 * pf))
		draw_circle(pp, 7.6 + 2.0 * pf, UIKit.INK)
		draw_circle(pp, 5.6 + 1.5 * pf, COL_PEG.lerp(Color.WHITE, pf))
		draw_circle(pp + Vector2(-1.6, -1.8), 1.8, Color("#FFB3D4"))

	# Gates: glowing bumpers, cyan for x2, magenta for x3, gold for x4 and up
	for i in GATES.size():
		var r: Rect2 = GATES[i]["rect"]
		var mult := gate_mult(i)
		var col := UIKit.CYAN
		if mult >= 4:
			col = UIKit.GOLD
		elif mult == 3:
			col = UIKit.PINK
		var gflash: float = float(gate_flash[i]) / 0.3
		var pulse := 0.5 + 0.5 * sin(t * 3.0 + float(i) * 1.3)
		var grow := 3.0 * gflash
		var poly := PackedVector2Array([
			Vector2(r.position.x + 8.0 - grow, r.position.y - grow),
			Vector2(r.end.x + grow, r.position.y - grow),
			Vector2(r.end.x - 8.0 + grow, r.end.y + grow),
			Vector2(r.position.x - grow, r.end.y + grow),
		])
		var poly_out: PackedVector2Array = poly.duplicate()
		poly_out.append(poly[0])
		draw_polyline(poly_out, Color(col, 0.07 + 0.07 * pulse + 0.30 * gflash), 15.0, true)
		draw_polyline(poly_out, Color(col, 0.14 + 0.10 * pulse + 0.30 * gflash), 8.0, true)
		draw_colored_polygon(poly, col.darkened(0.78).lerp(col, 0.35 * gflash))
		var top_half := PackedVector2Array([poly[0], poly[1], poly[1].lerp(poly[2], 0.5), poly[0].lerp(poly[3], 0.5)])
		draw_colored_polygon(top_half, Color(col, 0.20))
		draw_polyline(poly_out, UIKit.INK, 5.5, true)
		var hot := col.lerp(Color.WHITE, 0.35 * gflash)
		draw_polyline(poly_out, Color(hot.r * 1.6, hot.g * 1.6, hot.b * 1.6, 1.0), 3.0, true)
		UIKit.text_in(self, r, "X%d" % mult, 22, Color.WHITE, col.darkened(0.7), 5, HORIZONTAL_ALIGNMENT_CENTER)

	_draw_dropper()


func _draw_glow() -> void:
	# Soft additive light pools: they brighten what is behind them instead of covering it.
	for p in pegs:
		glow_layer.draw_circle(p, 15.0, Color(1.0, 0.18, 0.58, 0.03))
		glow_layer.draw_circle(p, 9.0, Color(1.0, 0.3, 0.65, 0.04))
	for i in GATES.size():
		var r: Rect2 = GATES[i]["rect"]
		var mult := gate_mult(i)
		var col := UIKit.CYAN
		if mult >= 4:
			col = UIKit.GOLD
		elif mult == 3:
			col = UIKit.PINK
		var pulse := 0.5 + 0.5 * sin(t * 3.0 + float(i) * 1.3)
		var a := 0.07 + 0.06 * pulse + 0.25 * (float(gate_flash[i]) / 0.3)
		var gp := PackedVector2Array([
			Vector2(r.position.x + 8.0, r.position.y), Vector2(r.end.x, r.position.y),
			Vector2(r.end.x - 8.0, r.end.y), Vector2(r.position.x, r.end.y), Vector2(r.position.x + 8.0, r.position.y),
		])
		for g in 3:
			glow_layer.draw_polyline(gp, Color(col, a * 0.9 / float(g + 1)), 10.0 + float(g) * 12.0, true)
	var cf := cup_flash / 0.25
	var cup_c := Vector2(CUP_SENSOR.get_center().x, 680.0)
	var cr := Rect2(cup_c - Vector2(66.0, 30.0), Vector2(132.0, 60.0))
	var cp := PackedVector2Array([cr.position, Vector2(cr.end.x, cr.position.y), cr.end, Vector2(cr.position.x, cr.end.y), cr.position])
	for g in 3:
		glow_layer.draw_polyline(cp, Color(UIKit.GOLD, (0.06 + 0.25 * cf) / float(g + 1)), 10.0 + float(g) * 12.0, true)
	for b in get_tree().get_nodes_in_group("balls"):
		glow_layer.draw_circle(b.position, 12.0, Color(1.0, 0.65, 0.15, 0.16))


func _draw_hud() -> void:
	# Coin pill
	UIKit.card(self, Rect2(12.0, 10.0, 168.0, 54.0), Color("#33283B"), Color("#18111C"), UIKit.INK, 27)
	UIKit.coin(self, Vector2(40.0, 37.0), 15.0)
	var cs := 1.0 + 0.15 * coin_pulse
	draw_set_transform_matrix(Transform2D(Vector2(cs, 0.0), Vector2(0.0, cs), Vector2(60.0, 37.0) - Vector2(60.0, 37.0) * cs))
	UIKit.text_in(self, Rect2(60.0, 10.0, 116.0, 50.0), str(int(round(shown_coins))), 28, UIKit.GOLD, UIKit.INK, 6, HORIZONTAL_ALIGNMENT_LEFT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Wave or balls pill
	UIKit.card(self, Rect2(198.0, 10.0, 180.0, 54.0), Color("#33283B"), Color("#18111C"), UIKit.INK, 27)
	if state == "drop":
		draw_circle(Vector2(224.0, 37.0), 12.0, UIKit.INK)
		draw_circle(Vector2(224.0, 37.0), 9.5, UIKit.AMBER)
		draw_circle(Vector2(221.0, 34.0), 3.0, Color("#FFE9A8"))
		var total := balls_per_round() + (bonus_balls if not dropped else 0)
		UIKit.text_in(self, Rect2(242.0, 10.0, 130.0, 50.0), "%d/%d" % [balls_left, total], 26, UIKit.CREAM, UIKit.INK, 6, HORIZONTAL_ALIGNMENT_LEFT)
		if bonus_balls > 0 and not dropped:
			UIKit.text_in(self, Rect2(198.0, 68.0, 180.0, 20.0), "includes %d bonus balls" % bonus_balls, 12, UIKit.GOLD, UIKit.INK, 4, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		UIKit.star(self, Vector2(224.0, 37.0), 13.0, UIKit.GOLD)
		UIKit.text_in(self, Rect2(242.0, 10.0, 134.0, 50.0), "WAVE %d/%d" % [battle.wave, battle.MAX_WAVE], 22, UIKit.CREAM, UIKit.INK, 6, HORIZONTAL_ALIGNMENT_LEFT)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	_draw_wallpaper()
	if state == "map":
		_draw_map(font)
	elif state == "drop":
		_draw_board()
	_draw_hud()
	if state == "drop":
		fx.draw(self)

	if state == "drop" and round_over:
		UIKit.card(self, Rect2(FIELD.position.x + 26.0, 358.0, FIELD.size.x - 52.0, 108.0), Color("#3A2D44"), Color("#1A131F"), UIKit.GOLD, 18)
		UIKit.text_in(self, Rect2(FIELD.position.x, 364.0, FIELD.size.x, 56.0), "ROUND OVER", 38, UIKit.GOLD, UIKit.INK, 8, HORIZONTAL_ALIGNMENT_CENTER)
		UIKit.text_in(self, Rect2(FIELD.position.x, 420.0, FIELD.size.x, 30.0), "Now defend the house", 16, UIKit.CREAM, UIKit.INK, 4, HORIZONTAL_ALIGNMENT_CENTER)
