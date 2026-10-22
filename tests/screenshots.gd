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
	await snap("1_drop_idle")
	m.coins = 300
	m._on_main_pressed()
	await frames(50)
	await snap("2_drop_mid")
	var guard := 0
	while not m.round_over and guard < 1500:
		await get_tree().process_frame
		guard += 1
	await snap("3_round_over")
	m.buy_cat("rosette")
	m.buy_cat("macho")
	m._toggle_shop()
	await frames(3)
	await snap("4_shop")
	m._toggle_shop()
	b.place(4, "rosette")
	b.place(1, "macho")
	m._toggle_mode()
	await frames(3)
	await snap("5_battle_place")
	b.wave = 4
	b.place(2, "rosette") if b.spare("rosette") > 0 else false
	await frames(2)
	m._on_main_pressed()
	await frames(150)
	await snap("6_battle_mid")
	await frames(120)
	await snap("7_battle_later")
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
	await snap("8_hub")
	hub.show_achievements()
	await frames(2)
	await snap("9_hub_achievements")
	hub.close_overlay()
	hub.show_settings()
	await frames(2)
	await snap("10_hub_settings")
	hub.close_overlay()
	hub.open_game("catdrop")
	await frames(5)
	await snap("11_catdrop_in_hub")
	hub.toast("Achievement: First Drop")
	hub.toast("Level 2!")
	await frames(3)
	await snap("12_toasts")
	get_tree().quit()
