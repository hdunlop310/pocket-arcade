extends Node
# Platform test: save file, migration, profile maths, achievements, and the hub opening/closing Cat Drop.
# Run: GODOT --headless --path . res://tests/test_hub.tscn   (exits 1 on failure)
var fails := 0
func check(label: String, cond: bool) -> void:
	print(("PASS  " if cond else "FAIL  "), label)
	if not cond:
		fails += 1
func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame

func _ready() -> void:
	Save.use_test_file()

	# --- Save ---
	var d := Save.section("demo")
	d["coins"] = 42
	d["grid"] = ["a", "", "b"]
	d["nested"] = {"x": 1}
	Save.flush()
	Save.reload()
	var back := Save.section("demo")
	check("save round trip keeps ints, arrays and dictionaries", int(back["coins"]) == 42 and back["grid"].size() == 3 and int(back["nested"]["x"]) == 1)
	check("sections are separate", Save.section("other").is_empty())

	# --- Migration of the prototype's catdrop.cfg ---
	var old := ConfigFile.new()
	old.set_value("save", "coins", 321)
	old.set_value("save", "bonus_balls", 4)
	old.set_value("levels", "balls", 2)
	old.set_value("levels", "coin", 1)
	old.set_value("battle", "wave", 6)
	old.set_value("battle", "house_hp", 55.0)
	old.set_value("battle", "grid", ["macho", "", "", "", "rosette", "", "", "", "", "", "", "", "", "", "", ""])
	old.set_value("owned", "macho", 2)
	old.set_value("owned", "rosette", 1)
	old.save("user://test_old_catdrop.cfg")
	Save.use_test_file()
	check("migration succeeds", Save.migrate_catdrop("user://test_old_catdrop.cfg"))
	Save.reload()
	var cd := Save.section("catdrop")
	check("migrated coins, wave and upgrade levels", int(cd["coins"]) == 321 and int(cd["wave"]) == 6 and int(cd["levels"]["balls"]) == 2)
	var m0 = load("res://games/catdrop/catdrop.tscn").instantiate()
	add_child(m0)
	m0.start(cd)
	await frames(2)
	check("Cat Drop loads the migrated save", m0.coins == 321 and m0.battle.wave == 6 and m0.battle.owned["macho"] == 2 and m0.battle.grid[4] == "rosette" and m0.bonus_balls == 4 and int(m0.levels["balls"]) == 2)
	m0.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_old_catdrop.cfg"))

	# --- Profile maths ---
	check("level 1 at 0 XP", Profile.level_info(0) == {"level": 1, "into": 0, "need": 100})
	check("level 2 at 100 XP", Profile.level_info(100) == {"level": 2, "into": 0, "need": 150})
	check("level 3 at 250 XP with 5 into it", Profile.level_info(255) == {"level": 3, "into": 5, "need": 200})
	var prof := {}
	var fresh := Profile.award(prof, 10, ["cd_first_ball", "nonsense"])
	check("award pays XP plus the achievement's XP once", fresh == ["cd_first_ball"] and Profile.xp(prof) == 10 + 20)
	fresh = Profile.award(prof, 0, ["cd_first_ball"])
	check("the same achievement is not paid twice", fresh.is_empty() and Profile.xp(prof) == 30)
	check("every achievement id is in the lookup table", Achievements.LIST.size() == Achievements.BY_ID.size() and Achievements.LIST.size() >= 5)

	# --- Hub ---
	Save.use_test_file()
	var hub = load("res://hub/hub.tscn").instantiate()
	add_child(hub)
	await frames(2)
	check("hub shows a tile per registry entry", hub.tile_buttons.size() == 1 and hub.tile_progress.has("catdrop"))
	check("fresh hub: level 1, no XP", hub.level_label.text == "LEVEL 1" and hub.xp_label.text == "0 / 100 XP")
	check("tile says New game", hub.tile_progress["catdrop"].text == "New game")
	check("a locked game cannot be opened", hub.open_game("carsort") == false and hub.game == null)

	check("opening Cat Drop starts it and hides the picker", hub.open_game("catdrop") and hub.game != null and hub.game.started and not hub.home.visible)
	await frames(3)
	var g = hub.game
	g.coins = 777
	g._save_game()
	Save.reload()
	check("Cat Drop saves into the [catdrop] section", int(Save.section("catdrop")["coins"]) == 777)

	g._report(10)
	check("progress() awards XP", Profile.xp(Save.section("profile")) == 10)
	g.stats["balls_banked"] = 150
	g._report(0)
	var got: Array = Profile.unlocked(Save.section("profile"))
	check("progress() unlocks achievements and pays their XP once", got.has("cd_first_ball") and got.has("cd_100_balls") and not got.has("cd_1000_balls") and Profile.xp(Save.section("profile")) == 10 + 20 + 30)
	g._report(0)
	check("repeating the same report pays nothing", Profile.xp(Save.section("profile")) == 60)

	g.home_btn.pressed.emit()
	await frames(2)
	check("HUB button returns to the picker and frees the game", hub.game == null and hub.home.visible and hub.game_host.get_child_count() == 0)
	check("tile now shows saved progress", hub.tile_progress["catdrop"].text.contains("777"))
	check("profile bar updated", hub.xp_label.text == "60 / 100 XP")

	# Wave rewards end up as XP through the real signal path
	var xp_before: int = Profile.xp(Save.section("profile"))
	hub.open_game("catdrop")
	await frames(2)
	hub.game._on_wave_cleared(1)
	check("clearing a wave reports XP and the first-wave achievement", Profile.xp(Save.section("profile")) == xp_before + 10 + 20 and Profile.unlocked(Save.section("profile")).has("cd_first_wave"))
	hub.close_game()

	# Taps must reach the game through the hub's UI: a full-screen STOP control once swallowed them
	Save.section("catdrop")["stats"] = {"balls_banked": 0, "best_wave": 3, "runs_won": 0}
	Save.section("catdrop")["owned"] = {"macho": 1, "rosette": 1}
	hub.open_game("catdrop")
	await frames(2)
	var gm = hub.game
	gm._on_main_pressed()
	gm.round_over = true
	gm.dropped = true
	gm._on_main_pressed()
	await frames(2)
	check("in the hub, the game reaches the battle screen", gm.state == "battle" and gm.battle.visible)
	for i in 16:
		gm.battle.grid[i] = ""
	gm.battle.selected = ""
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = gm.battle._chip_rect(1).get_center()
	hub.get_viewport().push_input(tap, true)   # true: the position is already in game coordinates
	check("a real tap on a cat chip selects it (hub does not swallow input)", gm.battle.selected == "rosette")
	tap.position = gm.battle.tile_center(5)
	hub.get_viewport().push_input(tap, true)   # true: the position is already in game coordinates
	check("a real tap on a tile places the cat", gm.battle.grid[5] == "rosette")
	hub.close_game()

	# finished() with a stub game returns to the picker and awards
	var stub: GameBase = load("res://tests/stub_game.gd").new()
	hub.run_game(stub, "stub")
	check("stub game gets its own save slot", int(Save.section("stub")["started"]) == 1)
	var xp_now: int = Profile.xp(Save.section("profile"))
	stub.finished.emit({"xp": 40})
	await frames(1)
	check("finished() awards XP and returns to the hub", Profile.xp(Save.section("profile")) == xp_now + 40 and hub.game == null and hub.home.visible)

	# Level up
	Save.section("profile")["xp"] = 95
	hub.refresh()
	hub.open_game("catdrop")
	await frames(1)
	hub.game._report(10)
	check("level up at 100 XP", Profile.level_info(Profile.xp(Save.section("profile")))["level"] == 2)
	hub.close_game()
	check("hub shows level 2", hub.level_label.text == "LEVEL 2")

	# Overlays
	hub.show_achievements()
	await frames(1)
	check("achievements overlay opens and lists every achievement", hub.overlay != null and hub.overlay.get_child_count() > Achievements.LIST.size() * 4)
	hub.close_overlay()
	check("overlay closes", hub.overlay == null)
	hub.show_settings()
	hub.overlay.find_child("SoundButton", true, false).pressed.emit()
	check("sound toggle persists", Save.section("settings")["sound"] == false)
	hub.close_overlay()

	# Reset
	hub.reset_all_progress()
	check("reset clears XP and games", Profile.xp(Save.section("profile")) == 0 and Save.section("catdrop").is_empty() and hub.level_label.text == "LEVEL 1")
	Save.reload()
	check("reset is written to disk", Save.section("catdrop").is_empty())

	print("TEST: done, failures=", fails)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.path))
	get_tree().quit(1 if fails > 0 else 0)
