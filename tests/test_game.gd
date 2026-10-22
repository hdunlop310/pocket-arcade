extends Node
# Integration test for Cat Drop: map, upgrades, cat levels, placement, the one-drop round loop,
# waves, rewards, saving, defeat, boss.
# Run: see CLAUDE.md. Exits with code 1 if any check fails.
var fails := 0
func check(label: String, cond: bool) -> void:
	print(("PASS  " if cond else "FAIL  "), label)
	if not cond:
		fails += 1
func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame
func new_main() -> Node2D:
	var m = load("res://games/catdrop/catdrop.tscn").instantiate()
	add_child(m)
	m.start_standalone()
	return m
func run_wave(m: Node2D, max_steps: int = 60000) -> void:
	var s := 0
	while m.battle.active and s < max_steps:
		m.battle.step(1.0 / 12.0)
		s += 1
# Waits until the round's drop is finished (every ball landed). Returns false on timeout.
func wait_for_round_over(m: Node2D) -> bool:
	var guard := 0
	while not m.round_over and guard < 4000:
		await frames(1)
		guard += 1
	return m.round_over

func _ready() -> void:
	Save.use_test_file()
	var m := new_main()
	await frames(3)
	var b = m.battle

	check("starts on the map, battle hidden, upgrade panel shown", m.state == "map" and not b.visible and m.map_panel.visible)
	check("new game: 1 Macho owned and placed on tile 0", b.owned["macho"] == 1 and b.grid[0] == "macho" and b.owned["rosette"] == 0)
	check("map panel has rows for 2 cats and 3 upgrades", m.map_rows.size() == 5)
	check("map button reads PLAY WAVE 1 and HUB is shown", m.main_btn.text == "PLAY WAVE 1" and m.home_btn.visible)

	# Buying cats
	check("cannot buy a cat with 0 coins", m.buy_cat("macho") == false)
	check("Rosette starts locked behind wave 2", not m.cat_unlocked("rosette") and m.map_rows["cat:rosette"]["buy"].text == "LOCKED")
	check("the team starts at 1 of 2 cats", m.team_size() == 1 and m.team_cap() == 2)
	m.coins = 500
	check("a locked cat cannot be bought", m.buy_cat("rosette") == false and m.coins == 500)
	m.stats["best_wave"] = 2
	m._refresh_panel()
	check("clearing wave 2 unlocks Rosette and grows the team cap", m.cat_unlocked("rosette") and m.team_cap() == 4)
	check("buy Rosette for 60", m.buy_cat("rosette") and m.coins == 440 and b.owned["rosette"] == 1)
	m.stats["best_wave"] = 0
	m._refresh_panel()
	check("a full team cannot grow", m.buy_cat("macho") == false and m.map_rows["cat:macho"]["buy"].text == "TEAM FULL")
	m.stats["best_wave"] = 3
	check("second Rosette costs 81", b.cat_cost("rosette") == 81)
	check("second Macho costs 54", b.cat_cost("macho") == 54)

	# Cat levels, the long-term coin sink. Level 1 must leave the old balance untouched.
	check("level 1 is x1.0 and a level-up costs 80 for Macho", b.level_mult("macho") == 1.0 and b.level_cost("macho") == 80 and b.cat_levels["macho"] == 1)
	check("level-up button shows its price", m.map_rows["cat:macho"]["lvl"].text == "LEVEL UP 80")
	check("level up Macho: coins drop, level 2, stats x1.2", m.upgrade_cat("macho") and m.coins == 360 and b.cat_levels["macho"] == 2 and is_equal_approx(b.level_mult("macho"), 1.2))
	check("next Macho level costs 136", b.level_cost("macho") == 136)
	m.coins = 5
	check("cannot level up without the coins", m.upgrade_cat("macho") == false and b.cat_levels["macho"] == 2)
	b.cat_levels["rosette"] = b.MAX_CAT_LEVEL
	check("max level cannot be exceeded", b.can_level("rosette") == false and m.upgrade_cat("rosette") == false)
	b.cat_levels["rosette"] = 1
	b.cat_levels["macho"] = 1
	m.coins = 440

	# Placement rules
	check("place Rosette on raised tile 4", b.place(4, "rosette"))
	check("cannot place on an occupied tile", b.place(4, "rosette") == false and b.place(0, "macho") == false)
	check("cannot place without a spare cat", b.place(6, "rosette") == false)
	check("pickup returns a cat to spares", b.pickup(4) and b.spare("rosette") == 1)
	check("re-place it", b.place(6, "rosette"))

	# Click input
	b.visible = true
	b.selected = ""
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = b.tile_center(5)
	b._unhandled_input(ev)
	check("clicking a tile with nothing selected does nothing", b.grid[5] == "")
	b.pickup(6)
	b.selected = ""
	ev.position = b._chip_rect(1).get_center()
	b._unhandled_input(ev)
	check("clicking the Rosette chip selects it", b.selected == "rosette")
	ev.position = b.tile_center(11)
	b._unhandled_input(ev)
	check("clicking a tile then places the selected cat", b.grid[11] == "rosette")
	ev.position = b.tile_center(11)
	b._unhandled_input(ev)
	check("clicking a placed cat picks it up", b.grid[11] == "")
	b.place(6, "rosette")
	b.visible = false

	# Drop phase: exactly one drop per round
	m._drop_ball()
	check("the drop does nothing from the map", m.dropped == false and m.balls_left == 5)
	m._on_main_pressed()
	await frames(2)
	check("PLAY moves to the drop board with a full set of balls", m.state == "drop" and m.balls_left == 5 and not m.map_panel.visible and not m.home_btn.visible)
	check("button reads DROP ALL BALLS", m.main_btn.text == "DROP ALL BALLS" and not m.main_btn.disabled)
	var coins_before_drop: int = m.coins
	m._on_main_pressed()
	await frames(3)
	check("dropping uses the whole round at once", m.dropped and m.balls_left == 0 and m.main_btn.disabled)
	m._drop_ball()
	m._on_main_pressed()
	check("a second drop in the same round is refused", m.balls_left == 0 and m.state == "drop")
	check("the round ends once every ball has landed", await wait_for_round_over(m))
	check("balls banked coins", m.coins > coins_before_drop and int(m.stats["balls_banked"]) > 0)
	var coins_after_drop: int = m.coins
	m._drop_ball()
	await frames(5)
	check("still no extra balls after round over", get_tree().get_nodes_in_group("balls").is_empty() and m.coins == coins_after_drop)
	check("button reads TO BATTLE and the HUB button is hidden", m.main_btn.text == "TO BATTLE" and not m.home_btn.visible)

	# Battle phase
	m._on_main_pressed()
	await frames(2)
	check("TO BATTLE shows the battle grid", m.state == "battle" and b.visible)
	check("button reads START WAVE 1", m.main_btn.text == "START WAVE 1" and not m.main_btn.disabled)

	# A real wave through the button, rendering frames so _draw runs
	var coins_before_wave: int = m.coins
	m._on_main_pressed()
	check("wave starts", b.active)
	await frames(90)
	check("button reads FIGHTING while active", m.main_btn.text == "FIGHTING...")
	check("HUB button locked during a wave", m.home_btn.disabled)
	run_wave(m)
	await frames(2)
	check("wave 1 cleared with Macho + Rosette", b.wave == 2 and b.house_hp > 0.0)
	check("wave reward: +15 coins", m.coins == coins_before_wave + 15)
	check("wave reward: +4 bonus balls", m.bonus_balls == 4)
	check("a cleared wave heads back to the map", m.returning and m.state == "battle")
	b.banner_t = 0.0
	await frames(3)
	check("after the banner the game returns to the map", m.state == "map" and m.map_panel.visible and not b.visible)
	check("map button reads PLAY WAVE 2", m.main_btn.text == "PLAY WAVE 2")

	# Bonus balls join the next round's drop, and are only spent when dropped
	m._on_main_pressed()
	check("next round has 5 + 4 bonus balls", m.state == "drop" and m.balls_left == 9 and m.bonus_balls == 4)
	m._go_map()
	check("leaving without dropping keeps the bonus", m.bonus_balls == 4 and m.state == "map")

	# Persistence
	var coins_now: int = m.coins
	b.cat_levels["macho"] = 3
	m._save_game()
	m.queue_free()
	await frames(2)
	Save.reload()   # force a real round trip through the file on disk
	var m2 := new_main()
	await frames(3)
	check("coins, wave, cats, levels and grid reload", m2.coins == coins_now and m2.battle.wave == 2 and m2.battle.owned["rosette"] == 1 and m2.battle.grid[6] == "rosette" and m2.battle.grid[0] == "macho" and m2.battle.cat_levels["macho"] == 3 and m2.bonus_balls == 4)
	check("a reloaded game opens on the map", m2.state == "map")

	# Defeat resets the run but keeps progress
	var b2 = m2.battle
	m2.battle.cat_levels["macho"] = 1
	for i in 16:
		b2.grid[i] = ""
	b2.grid[3] = "macho"
	b2.wave = 8
	m2.state = "battle"
	b2.start_wave()
	run_wave(m2)
	check("a single Macho cannot hold wave 8: run fails and resets to wave 1", b2.wave == 1 and b2.house_hp == b2.HOUSE_MAX and b2.owned["macho"] == 1)
	check("a failed wave also returns to the map", m2.returning)

	# Boss wave and full run
	for i in 16:
		b2.grid[i] = ""
	b2.owned = {"macho": 5, "rosette": 5}
	for n in [0, 1, 2, 3, 5]:
		b2.grid[n] = "macho"
	for n in [4, 6, 11, 12, 8]:
		b2.grid[n] = "rosette"
	var before: int = m2.coins
	b2.wave = 10
	b2.start_wave()
	var saw_boss := false
	var steps := 0
	while b2.active and steps < 60000:
		b2.step(1.0 / 12.0)
		steps += 1
		for e in b2.enemies:
			if e["kind"] == "boss":
				saw_boss = true
	check("boss appears on wave 10", saw_boss)
	check("10 well-placed cats beat the boss, run completes", b2.wave == 1 and m2.coins >= before + 15 * 10 + 200)

	# Melee charge: Macho runs to the most advanced mouse anywhere (any lane, no leash), holds it, and comes home
	var bt = load("res://games/catdrop/battle.gd").new()
	add_child(bt)
	bt.owned = {"macho": 1, "rosette": 0}
	for i in 16:
		bt.grid[i] = ""
	bt.grid[8] = "macho"
	bt.wave = 2
	bt.rng.seed = 7   # fixed so the lanes the mice pick are the same every run
	bt.start_wave()
	var home: Vector2 = bt.tile_center(8)
	var max_dist := 0.0
	var max_side := 0.0
	var held_seen := false
	var held_still := true
	var prev_y := {}
	var csteps := 0
	while bt.active and csteps < 20000:
		bt.step(1.0 / 12.0)
		csteps += 1
		var cp: Vector2 = bt.cat_pos(8)
		max_dist = maxf(max_dist, cp.distance_to(home))
		max_side = maxf(max_side, absf(cp.x - home.x))
		for e in bt.enemies:
			if int(e["held_by"]) >= 0:
				held_seen = true
				if prev_y.has(e["x"]) and float(e["y"]) > float(prev_y[e["x"]]) + 0.01:
					held_still = false
			prev_y[e["x"]] = float(e["y"])
	check("Macho leaves his tile to meet mice", max_dist > 60.0)
	check("there is no leash: he runs well past the old 130px limit", max_dist > 160.0)
	check("he goes to mice in other lanes, not just his own", max_side > 60.0)
	check("a mouse he has hold of stops advancing", held_seen and held_still)
	check("Macho alone clears wave 2 by fighting mice up the field", bt.house_hp > 0.0 and bt.wave == 3)
	bt.cats[8] = {"key": "macho", "hp": 100.0, "max": 100.0, "cd": 5.0, "alive": true, "x": home.x + 50.0, "y": home.y - 150.0, "target": null, "face": 1.0, "n_atk": 0, "atk_t": 9.0, "phase": 0.0, "dust": 0.0, "moving": false}
	bt.enemies = []
	bt.spawn_queue = ["mouse"]
	bt.spawn_timer = 1000.0
	bt.active = true
	for k in 60:
		bt.step(1.0 / 12.0)
	check("with the field clear he runs back to his tile", bt.cat_pos(8).distance_to(home) < 0.5 and not bt.is_charging(8))
	bt.active = false
	check("the tile bonuses only apply on the tile", bt._cat_damage_mult(8) == bt._tile_damage_mult(8))
	bt.queue_free()

	print("TEST: done, failures=", fails)
	get_tree().quit(1 if fails > 0 else 0)
