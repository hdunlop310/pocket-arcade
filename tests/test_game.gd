extends Node
# Integration test: shop, cats, placement, input, waves, rewards, saving, defeat, boss.
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

func _ready() -> void:
	Save.use_test_file()
	var m := new_main()
	await frames(3)
	var b = m.battle

	check("battle node exists and starts hidden", b != null and not b.visible)
	check("new game: 1 Macho owned and placed on tile 0", b.owned["macho"] == 1 and b.grid[0] == "macho" and b.owned["rosette"] == 0)
	check("shop has rows for 2 cats and 3 upgrades", m.shop_rows.size() == 5)

	# Buying cats
	check("cannot buy a cat with 0 coins", m.buy_cat("rosette") == false)
	m.coins = 500
	check("buy Rosette for 60", m.buy_cat("rosette") and m.coins == 440 and b.owned["rosette"] == 1)
	check("second Rosette costs 81", b.cat_cost("rosette") == 81)
	check("second Macho costs 54", b.cat_cost("macho") == 54)

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

	# Mode switching and the start-wave button
	m._toggle_mode()
	await frames(2)
	check("toggle moves to battle mode", m.mode == "battle" and b.visible)
	check("button reads START WAVE 1", m.main_btn.text == "START WAVE 1" and not m.main_btn.disabled)
	m._toggle_shop()
	check("shop opens in battle mode", m.shop_open)
	m._toggle_shop()

	# A real wave through the button, rendering frames so _draw runs
	m._on_main_pressed()
	check("wave starts", b.active and m.main_btn.disabled == false or b.active)
	await frames(90)
	check("button reads FIGHTING while active", m.main_btn.text == "FIGHTING...")
	check("shop and mode locked during a wave", m.shop_btn.disabled and m.mode_btn.disabled)
	run_wave(m)
	await frames(2)
	check("wave 1 cleared with Macho + Rosette", b.wave == 2 and b.house_hp > 0.0)
	check("wave reward: +15 coins", m.coins == 440 + 15)
	check("wave reward: +4 bonus balls", m.bonus_balls == 4)

	# Back to drop mode: bonus joins the round
	m._toggle_mode()
	check("returning to drop mode adds bonus balls", m.mode == "drop" and m.balls_left == 12 + 4 and m.bonus_balls == 0)

	# Persistence
	var coins_now: int = m.coins
	m._save_game()
	m.queue_free()
	await frames(2)
	Save.reload()   # force a real round trip through the file on disk
	var m2 := new_main()
	await frames(3)
	check("coins, wave, cats and grid reload", m2.coins == coins_now and m2.battle.wave == 2 and m2.battle.owned["rosette"] == 1 and m2.battle.grid[6] == "rosette" and m2.battle.grid[0] == "macho")

	# Defeat resets the run but keeps progress
	var b2 = m2.battle
	m2.mode = "battle"
	for i in 16:
		b2.grid[i] = ""
	b2.grid[3] = "macho"
	b2.wave = 8
	b2.start_wave()
	run_wave(m2)
	check("a single Macho cannot hold wave 8: run fails and resets to wave 1", b2.wave == 1 and b2.house_hp == b2.HOUSE_MAX and b2.owned["macho"] == 1)

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

	print("TEST: done, failures=", fails)
	get_tree().quit(1 if fails > 0 else 0)
