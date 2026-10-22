extends Node
# Plays a short scripted demo (hub -> Cat Drop map -> one drop -> battle) for screen recording.
# Record with Godot's movie maker, which needs a real renderer (not --headless). To keep the file small
# (the recorder writes uncompressed-ish MJPEG), write a low frame rate and a lower JPEG quality through a
# temporary override.cfg next to project.godot:
#   [editor]
#   movie_writer/mjpeg_quality=0.3
#   [display]
#   window/size/window_width_override=390
#   window/size/window_height_override=844
# then:
#   GODOT --path . --write-movie recordings/cat_drop_demo.avi --fixed-fps 20 res://tests/record_demo.tscn
# The demo uses a throwaway save file, never the player's real one.

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	Save.use_test_file("user://demo_hub.cfg")
	# a mid-game save so all three cats and their sprites show up
	var prof := Save.section("profile")
	prof["xp"] = 180
	prof["achievements"] = ["cd_first_ball", "cd_first_wave", "cd_four_cats"]
	var slot := Save.section("catdrop")
	slot["coins"] = 260
	slot["wave"] = 5
	slot["stats"] = {"balls_banked": 140, "best_wave": 4, "runs_won": 0}
	slot["owned"] = {"macho": 1, "rosette": 1, "adora": 1}
	slot["cat_levels"] = {"macho": 2, "rosette": 1, "adora": 1}
	slot["levels"] = {"balls": 1, "coin": 0, "gates": 0}
	slot["grid"] = ["macho", "", "adora", "", "", "", "rosette", "", "", "", "", "", "", "", "", ""]

	var hub = load("res://hub/hub.tscn").instantiate()
	add_child(hub)
	await frames(30)                      # the hub
	hub.open_game("catdrop")
	var g = hub.game
	await frames(40)                      # the story map
	g._on_main_pressed()                  # play: to the drop board
	await frames(40)
	g._on_main_pressed()                  # the one drop
	var guard := 0
	while not g.round_over and guard < 900:
		await frames(1)
		guard += 1
	await frames(30)                      # CUP! celebration
	g._on_main_pressed()                  # to battle
	await frames(25)
	g.battle.pickup(2)                    # a cat in hand: the empty tiles glow
	await frames(25)
	g.battle.place(2, "adora")
	await frames(15)
	g._on_main_pressed()                  # start the wave
	guard = 0
	while g.battle.active and guard < 200:
		await frames(1)
		guard += 1
	await frames(30)
	get_tree().quit()
