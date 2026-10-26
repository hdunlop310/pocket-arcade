extends Control
# The hub: game picker, profile bar (XP and level), achievements and settings.
# Games are instanced as children of `game_host` and talk to the hub through the GameBase signals.
# Everything is built in code, like the games.

const COL_BG := Color("#1A0B2E")
const COL_PANEL := Color("#2A1644")
const COL_LINE := Color("#4B2B73")
const COL_TEXT := Color("#F4F4F6")
const COL_MUTED := Color("#B7A9CC")
const COL_ACCENT := Color("#00F0FF")
const COL_DARK := Color("#0B0B0E")

const TILE_SIZE := Vector2(165.0, 224.0)
const TILE_GAP := 20.0
const TILES_TOP := 128.0

var home: Control
var game_host: Node
var toast_box: VBoxContainer
var game: GameBase
var current_id := ""

var level_label: Label
var xp_label: Label
var bar_fill: Control
var bar_back: Control
var avatar: Control
var tile_progress := {}      # game id -> Label
var tile_buttons := {}       # game id -> Button
var overlay: Control         # achievements / settings, null when closed
var _tile_art := {}          # game id -> Texture2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # a full-screen STOP control here would swallow every tap meant for the game
	_build_home()
	game_host = Node.new()
	game_host.name = "GameHost"
	add_child(game_host)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	toast_box = VBoxContainer.new()
	toast_box.position = Vector2(20.0, 98.0)
	toast_box.size = Vector2(350.0, 10.0)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toast_box)
	refresh()
	if OS.get_environment("POCKET_AUTOPLAY") != "":
		_autoplay(OS.get_environment("POCKET_AUTOPLAY").split(","))


# Debug only: POCKET_AUTOPLAY=open,play,drop,wait2 drives the real window through a few steps (on a throwaway
# save) so it can be screenshotted from outside. Steps: open, play (main button), drop (same), waitN (seconds).
func _autoplay(steps: PackedStringArray) -> void:
	Save.use_test_file("user://autoplay.cfg")
	var slot := Save.section("catdrop")
	slot["coins"] = 300
	slot["wave"] = 4
	slot["stats"] = {"balls_banked": 100, "best_wave": 4, "runs_won": 0}
	slot["owned"] = {"macho": 1, "rosette": 1, "adora": 1}
	slot["grid"] = ["macho", "", "adora", "", "", "", "rosette", "", "", "", "", "", "", "", "", ""]
	refresh()
	await get_tree().create_timer(1.0).timeout
	for st in steps:
		if st == "open":
			open_game("catdrop")
		elif st == "play" or st == "drop":
			if game != null:
				game._on_main_pressed()
		elif st.begins_with("wait"):
			await get_tree().create_timer(float(st.substr(4))).timeout


# ----------------------------------------------------------------------------
# Small UI helpers
# ----------------------------------------------------------------------------

func _label(parent: Node, text: String, font_size: int, color: Color, pos: Vector2, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font_size >= 16:
		l.add_theme_font_override("font", UIKit.heavy())
		l.add_theme_color_override("font_outline_color", UIKit.INK)
		l.add_theme_constant_override("outline_size", 5 if font_size >= 22 else 4)
	l.position = pos
	if width > 0.0:
		l.horizontal_alignment = align as HorizontalAlignment
		l.clip_text = true
	parent.add_child(l)
	if width > 0.0:
		l.size = Vector2(width, float(font_size) * 1.4)   # after add_child, which resizes to the text
	return l


func _wrap(l: Label) -> Label:
	var w := l.size.x
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.clip_text = false
	l.size = Vector2(w, 40.0)
	return l


func _rect(parent: Node, rect: Rect2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _panel(parent: Node, rect: Rect2, fill: Color, border: Color, border_w: int) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", UIKit.box(fill, border, border_w, 14, 3 if border_w >= 3 else 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _button(parent: Node, text: String, rect: Rect2, bg: Color, fg: Color, font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	UIKit.style_button(b, bg, fg, font_size)
	parent.add_child(b)
	return b


# ----------------------------------------------------------------------------
# Home screen
# ----------------------------------------------------------------------------

func _build_home() -> void:
	home = Control.new()
	home.name = "Home"
	home.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(home)
	_add_background(home)

	# Top bar: avatar ring, level and XP, and a settings gear. Tapping the avatar or bar opens the achievements.
	avatar = Control.new()
	avatar.position = Vector2(20.0, 22.0)
	avatar.size = Vector2(60.0, 60.0)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.draw.connect(_draw_avatar)
	home.add_child(avatar)
	level_label = UIKit.label(home, Rect2(92.0, 20.0, 120.0, 20.0), "", 13, COL_TEXT)
	xp_label = UIKit.label(home, Rect2(180.0, 20.0, 110.0, 20.0), "", 12, COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)
	bar_back = Panel.new()
	bar_back.position = Vector2(92.0, 44.0)
	bar_back.size = Vector2(198.0, 24.0)
	(bar_back as Panel).add_theme_stylebox_override("panel", UIKit.box(Color("#0F0620"), UIKit.PANEL_BORDER, 2, 12, 0, 0))
	bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(bar_back)
	bar_fill = Panel.new()
	bar_fill.position = Vector2(95.0, 47.0)
	bar_fill.size = Vector2(0.0, 18.0)
	(bar_fill as Panel).add_theme_stylebox_override("panel", UIKit.pill(Color("#7AF8FF"), Color("#00B8D9"), Color("#04495A"), 9, 2))
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(bar_fill)
	var profile_btn := _button(home, "", Rect2(14.0, 14.0, 282.0, 76.0), Color(0.0, 0.0, 0.0, 0.0), COL_TEXT)
	profile_btn.name = "ProfileButton"
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 1.0, 1.0, 0.06 if state == "pressed" else 0.0)
		sb.set_corner_radius_all(14)
		profile_btn.add_theme_stylebox_override(state, sb)
	profile_btn.pressed.connect(show_achievements)

	var gear_btn := _button(home, "", Rect2(322.0, 26.0, 48.0, 48.0), Color(0.0, 0.0, 0.0, 0.0), COL_TEXT)
	for st in ["normal", "hover", "pressed", "disabled"]:
		gear_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	gear_btn.name = "SettingsButton"
	gear_btn.pressed.connect(show_settings)
	var gear_icon := Control.new()
	gear_icon.size = gear_btn.size
	gear_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gear_icon.draw.connect(func():
		UIKit.card(gear_icon, Rect2(Vector2.ZERO, gear_icon.size).grow(-1.0), Color("#33205A"), Color("#150A28"), UIKit.INK, 14)
		UIKit.neon_frame(gear_icon, Rect2(Vector2.ZERO, gear_icon.size), 1.4)
		UIKit.gear(gear_icon, gear_icon.size * 0.5, 12.0, UIKit.CYAN))
	gear_btn.add_child(gear_icon)

	for i in Games.LIST.size():
		_build_tile(i)

	var trophies_btn := _button(home, "ACHIEVEMENTS", Rect2(85.0, 704.0, 220.0, 60.0), UIKit.AMBER, Color("#3B2400"), 20)
	trophies_btn.name = "AchievementsButton"
	trophies_btn.pressed.connect(show_achievements)
	trophies_btn.material = Polish.shine_material()
	UIKit.label(home, Rect2(20.0, 786.0, 350.0, 20.0), Games.HUB_NAME.to_upper() + "   -   no ads, no timers, no purchases", 11, Color(COL_MUTED, 0.7), HORIZONTAL_ALIGNMENT_CENTER, false)


func _tile_rect(i: int) -> Rect2:
	var col := i % 2
	var row := i / 2
	return Rect2(Vector2(20.0 + float(col) * (TILE_SIZE.x + TILE_GAP), TILES_TOP + float(row) * (TILE_SIZE.y + TILE_GAP)), TILE_SIZE)


func _build_tile(i: int) -> void:
	var g: Dictionary = Games.LIST[i]
	var r := _tile_rect(i)
	var playable := Games.is_playable(g)
	var card := Control.new()
	card.position = r.position
	card.size = r.size
	card.pivot_offset = r.size * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.draw.connect(_draw_tile.bind(card, g))
	home.add_child(card)
	UIKit.pop_in(card, 0.9, 0.3)
	if playable:
		UIKit.label(card, Rect2(0.0, 136.0, r.size.x, 32.0), str(g["title"]), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		tile_progress[g["id"]] = UIKit.label(card, Rect2(6.0, 166.0, r.size.x - 12.0, 18.0), "", 12, COL_MUTED, HORIZONTAL_ALIGNMENT_CENTER, false)
		var art := TextureRect.new()
		art.texture = load(str(g["art"]))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.position = Vector2(r.size.x * 0.5 - 55.0, 16.0)
		art.size = Vector2(110.0, 110.0)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.material = Polish.rounded_material(0.2)
		card.add_child(art)
		var play := Button.new()
		play.text = "PLAY"
		play.position = Vector2(r.size.x * 0.5 - 45.0, 186.0)
		play.size = Vector2(90.0, 30.0)
		play.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.style_button(play, UIKit.AMBER, Color("#3B2400"), 15)
		card.add_child(play)
		var btn := _button(card, "", Rect2(Vector2.ZERO, r.size), Color(0.0, 0.0, 0.0, 0.0), COL_TEXT)
		btn.name = "Tile_" + str(g["id"])
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1.0, 1.0, 1.0, 0.10 if state == "pressed" else 0.0)
			sb.set_corner_radius_all(22)
			btn.add_theme_stylebox_override(state, sb)
		btn.pressed.connect(open_game.bind(str(g["id"])))
		tile_buttons[g["id"]] = btn
		# The playable tile breathes gently so it reads as the thing to tap
		var tw := create_tween().set_loops()
		tw.tween_property(card, "scale", Vector2.ONE * 1.025, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(card, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		UIKit.label(card, Rect2(10.0, 118.0, r.size.x - 20.0, 56.0), "COMING\nSOON", 20, Color(COL_MUTED, 0.75), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_tile(card: Control, g: Dictionary) -> void:
	var rect := Rect2(Vector2.ZERO, card.size)
	var playable := Games.is_playable(g)
	# dark glassy panel under a glowing neon frame
	UIKit.card(card, rect.grow(-2.0), Color("#33205A") if playable else Color("#241540"), Color("#150A28"), UIKit.INK, 22)
	UIKit.neon_frame(card, rect, 1.6 if playable else 0.55)
	if playable:
		var bg: Color = g["bg"]
		UIKit.panel(card, Rect2(18.0, 18.0, rect.size.x - 36.0, 108.0), Color(bg, 0.35), Color(0, 0, 0, 0), 0, 16)
	else:
		UIKit.lock(card, Vector2(rect.size.x * 0.5, 80.0), 17.0, Color("#6E5C8C"))


func _draw_avatar() -> void:
	var c := Vector2(30.0, 30.0)
	avatar.draw_circle(c, 30.0, Color(UIKit.CYAN.r * 1.5, UIKit.CYAN.g * 1.5, UIKit.CYAN.b * 1.5))
	avatar.draw_circle(c, 26.5, UIKit.INK)
	avatar.draw_circle(c, 24.0, Color("#2A1650"))
	var info := Profile.level_info(Profile.xp(Save.section("profile")))
	UIKit.text_in(avatar, Rect2(0.0, 0.0, 60.0, 60.0), str(info["level"]), 24, UIKit.CREAM, UIKit.INK, 5, HORIZONTAL_ALIGNMENT_CENTER)


func _add_background(parent: Control) -> void:
	var bg := Control.new()
	bg.size = Vector2(390.0, 844.0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.draw.connect(func():
		bg.draw_rect(Rect2(0.0, 0.0, 390.0, 844.0), Color("#0D0518"))
		# a soft radial glow: stacked discs from dark to a deep purple in the middle
		for i in 16:
			var f := float(i) / 15.0
			bg.draw_circle(Vector2(195.0, 360.0), 560.0 - f * 520.0, Color("#2A1254").lerp(Color("#0D0518"), 1.0 - f).darkened(0.0) if false else Color(0.17, 0.07, 0.33, 0.045)))
	parent.add_child(bg)


func refresh() -> void:
	var prof := Save.section("profile")
	var info := Profile.level_info(Profile.xp(prof))
	level_label.text = "LEVEL %d" % int(info["level"])
	xp_label.text = "%d / %d XP" % [int(info["into"]), int(info["need"])]
	var fill_w: float = (bar_back.size.x - 6.0) * float(info["into"]) / float(info["need"])
	bar_fill.visible = fill_w > 0.5
	bar_fill.size.x = maxf(fill_w, 18.0)
	avatar.queue_redraw()
	for g in Games.LIST:
		if tile_progress.has(g["id"]):
			var lbl: Label = tile_progress[g["id"]]
			lbl.text = Games.progress_text(g, Save.section(str(g["id"])))


# ----------------------------------------------------------------------------
# Running a game
# ----------------------------------------------------------------------------

func open_game(id: String) -> bool:
	if game != null or overlay != null:
		return false
	for g in Games.LIST:
		if str(g["id"]) == id and Games.is_playable(g):
			run_game((load(str(g["scene"])) as PackedScene).instantiate(), id)
			return true
	return false


# Hooks an already-instanced game up to the hub and starts it. Tests use this with a stub game.
func run_game(inst: GameBase, id: String) -> void:
	game = inst
	current_id = id
	inst.progress.connect(_on_progress)
	inst.finished.connect(_on_finished)
	inst.quit_requested.connect(close_game)
	inst.save_requested.connect(Save.flush)
	game_host.add_child(inst)
	inst.start(Save.section(id))
	home.visible = false


func close_game() -> void:
	if game == null:
		return
	Save.flush()
	game_host.remove_child(game)
	game.queue_free()
	game = null
	current_id = ""
	home.visible = true
	refresh()


func _on_progress(result: Dictionary) -> void:
	var prof := Save.section("profile")
	var before: int = int(Profile.level_info(Profile.xp(prof))["level"])
	var fresh := Profile.award(prof, int(result.get("xp", 0)), result.get("achievements", []))
	Save.flush()
	for aid in fresh:
		toast("Achievement: " + str(Achievements.BY_ID[aid]["title"]))
	var after: int = int(Profile.level_info(Profile.xp(prof))["level"])
	if after > before:
		toast("Level %d!" % after)
	refresh()


func _on_finished(result: Dictionary) -> void:
	_on_progress(result)
	close_game()


func toast(text: String) -> void:
	var p := PanelContainer.new()
	var sb: StyleBoxFlat = UIKit.box(COL_PANEL, COL_ACCENT, 4, 14, 3).duplicate()
	sb.set_content_margin_all(12.0)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_font_override("font", UIKit.heavy())
	l.add_theme_color_override("font_color", COL_TEXT)
	l.add_theme_color_override("font_outline_color", UIKit.INK)
	l.add_theme_constant_override("outline_size", 4)
	p.add_child(l)
	toast_box.add_child(p)
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_interval(2.4)
		tw.tween_property(p, "modulate:a", 0.0, 0.5)
		tw.tween_callback(p.queue_free)


# ----------------------------------------------------------------------------
# Overlays: achievements and settings
# ----------------------------------------------------------------------------

func _open_overlay(title: String) -> Control:
	close_overlay()
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	home.add_child(overlay)
	UIKit.pop_in(overlay, 0.92, 0.25)
	_add_background(overlay)
	UIKit.label(overlay, Rect2(16.0, 18.0, 358.0, 48.0), title, 30, COL_TEXT)
	var close := _button(overlay, "BACK", Rect2(16.0, 770.0, 358.0, 52.0), COL_ACCENT, COL_DARK, 20)
	close.name = "CloseButton"
	close.pressed.connect(close_overlay)
	return overlay


func close_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		home.remove_child(overlay)
		overlay = null


func show_achievements() -> void:
	if game != null:
		return
	var o := _open_overlay("ACHIEVEMENTS")
	var got: Array = Profile.unlocked(Save.section("profile"))
	UIKit.label(o, Rect2(16.0, 64.0, 358.0, 22.0), "%d / %d unlocked" % [got.size(), Achievements.LIST.size()], 14, COL_ACCENT, HORIZONTAL_ALIGNMENT_LEFT, false)
	for i in Achievements.LIST.size():
		var a: Dictionary = Achievements.LIST[i]
		var done: bool = got.has(a["id"])
		var y := 100.0 + float(i) * 82.0
		_panel(o, Rect2(16.0, y, 358.0, 72.0), COL_PANEL, COL_ACCENT if done else COL_LINE, 2)
		var mark := Control.new()
		mark.position = Vector2(30.0, y + 16.0)
		mark.size = Vector2(40.0, 40.0)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.draw.connect(_draw_mark.bind(mark, done))
		o.add_child(mark)
		UIKit.label(o, Rect2(84.0, y + 6.0, 190.0, 30.0), str(a["title"]), 18, COL_TEXT if done else COL_MUTED)
		UIKit.label(o, Rect2(84.0, y + 36.0, 190.0, 28.0), str(a["desc"]), 13, COL_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
		UIKit.label(o, Rect2(274.0, y + 4.0, 90.0, 64.0), "+%d XP" % int(a["xp"]), 14, COL_ACCENT if done else COL_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)


func _draw_mark(mark: Control, done: bool) -> void:
	mark.draw_circle(Vector2(20.0, 20.0), 20.0, COL_ACCENT if done else COL_LINE)
	if done:
		mark.draw_polyline(PackedVector2Array([Vector2(10.0, 21.0), Vector2(17.0, 28.0), Vector2(30.0, 13.0)]), COL_DARK, 4.0)


func show_settings() -> void:
	if game != null:
		return
	var o := _open_overlay("SETTINGS")
	var st := Save.section("settings")
	var sound := _button(o, "", Rect2(16.0, 90.0, 358.0, 56.0), COL_PANEL, COL_TEXT)
	sound.name = "SoundButton"
	var haptics := _button(o, "", Rect2(16.0, 156.0, 358.0, 56.0), COL_PANEL, COL_TEXT)
	haptics.name = "HapticsButton"
	var sync_toggles := func() -> void:
		sound.text = "SOUND: " + ("ON" if st.get("sound", true) else "OFF")
		haptics.text = "HAPTICS: " + ("ON" if st.get("haptics", true) else "OFF")
	sync_toggles.call()
	sound.pressed.connect(func():
		st["sound"] = not st.get("sound", true)
		Save.flush()
		sync_toggles.call())
	haptics.pressed.connect(func():
		st["haptics"] = not st.get("haptics", true)
		Save.flush()
		sync_toggles.call())
	_wrap(_label(o, "The games have no sound or haptics yet. Your choice is saved for when they do.", 13, COL_MUTED, Vector2(16.0, 220.0), 358.0))

	var reset := _button(o, "RESET ALL PROGRESS", Rect2(16.0, 600.0, 358.0, 56.0), COL_PANEL, Color("#E0285E"))
	reset.name = "ResetButton"
	var note := _wrap(_label(o, "", 13, COL_MUTED, Vector2(16.0, 664.0), 358.0))
	var armed := [false]
	reset.pressed.connect(func():
		if not armed[0]:
			armed[0] = true
			reset.text = "TAP AGAIN TO ERASE EVERYTHING"
			note.text = "Coins, cats, XP and achievements in every game. This cannot be undone."
		else:
			reset_all_progress()
			close_overlay())
	_label(o, "Collects nothing. No ads, no network calls, no tracking.", 13, COL_MUTED, Vector2(16.0, 720.0), 358.0)


func reset_all_progress() -> void:
	Save.reset_all()
	refresh()
