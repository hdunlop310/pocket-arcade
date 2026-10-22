extends Node
# Renders PNG screenshots of the main screens. Needs a real renderer (not --headless).
# Set SHOT_DIR to the output folder. See CLAUDE.md.
var out := ""
func snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out + "/" + name + ".png")
	print("SHOT ", name, " ", img.get_size())
func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	out = OS.get_environment("SHOT_DIR")
	Save.use_test_file()
	var m = load("res://games/catdrop/catdrop.tscn").instantiate()
	add_child(m)
	m.start_standalone()
	var b = m.battle
	await frames(5)
	m.coins = 520
	m.battle.wave = 4
	m.stats["best_wave"] = 3
	m._refresh_panel()
	await snap("1_map")
	m.buy_cat("rosette")
	m.upgrade_cat("macho")
	await frames(2)
	await snap("2_map_upgraded")
	m._on_main_pressed()
	await frames(5)
	await snap("3_drop_idle")
	m._on_main_pressed()
	await frames(50)
	await snap("4_drop_mid")
	var guard := 0
	while not m.round_over and guard < 1500:
		await get_tree().process_frame
		guard += 1
	await snap("5_round_over")
	b.place(4, "rosette")
	b.place(1, "macho")
	m._on_main_pressed()
	await frames(3)
	await snap("6_battle_place")
	b.wave = 4
	m._on_main_pressed()
	await frames(150)
	await snap("7_battle_mid")
	await frames(120)
	await snap("8_battle_later")

	# Macho running out and attacking, on a standalone battle so the moment is easy to catch
	var bt = load("res://games/catdrop/battle.gd").new()
	add_child(bt)
	bt.owned = {"macho": 1, "rosette": 0}
	for i in 16:
		bt.grid[i] = ""
	bt.grid[8] = "macho"
	bt.wave = 3
	bt.start_wave()
	var guard2 := 0
	while guard2 < 3000 and not (bt.is_charging(8) and bt.cats[8]["moving"] and bt.cats[8]["y"] < bt.tile_center(8).y - 60.0):
		bt.step(1.0 / 30.0)
		guard2 += 1
	await frames(2)
	await snap("8b_macho_running")
	guard2 = 0
	while guard2 < 3000 and bt.slashes.is_empty():
		bt.step(1.0 / 30.0)
		guard2 += 1
	await frames(1)
	await snap("8c_macho_attacking")
	bt.queue_free()
	m.queue_free()
	await frames(2)

	# The hub, with a bit of progress in the save
	Save.use_test_file()
	var prof := Save.section("profile")
	prof["xp"] = 155
	prof["achievements"] = ["cd_first_ball", "cd_first_wave", "cd_four_cats"]
	var slot := Save.section("catdrop")
	slot["coins"] = 520
	slot["wave"] = 4
	var hub = load("res://hub/hub.tscn").instantiate()
	add_child(hub)
	await frames(3)
	await snap("9_hub")
	hub.show_achievements()
	await frames(2)
	await snap("10_hub_achievements")
	hub.close_overlay()
	hub.show_settings()
	await frames(2)
	await snap("11_hub_settings")
	hub.close_overlay()
	hub.open_game("catdrop")
	await frames(5)
	await snap("12_catdrop_in_hub")
	hub.toast("Achievement: First Drop")
	hub.toast("Level 2!")
	await frames(3)
	await snap("13_toasts")
	get_tree().quit()
