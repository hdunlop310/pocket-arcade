extends Control
# The hub: game picker, profile bar (XP and level), achievements and settings.
# Games are instanced as children of `game_host` and talk to the hub through the GameBase signals.
# Everything is built in code, like the games.

const COL_BG := Color("#12151F")
const COL_PANEL := Color("#1C2030")
const COL_LINE := Color("#2C3248")
const COL_TEXT := Color("#F4F4F6")
const COL_MUTED := Color("#8E94AB")
const COL_ACCENT := Color("#46D9A0")
const COL_DARK := Color("#0B0B0E")

const TILE_SIZE := Vector2(171.0, 170.0)
const TILE_GAP := 16.0
const TILES_TOP := 196.0

var home: Control
var game_host: Node
var toast_box: VBoxContainer
var game: GameBase
var current_id := ""

var level_label: Label
var xp_label: Label
var bar_fill: ColorRect
var bar_back: ColorRect
var avatar: Control
var tile_progress := {}      # game id -> Label
var tile_buttons := {}       # game id -> Button
var overlay: Control         # achievements / settings, null when closed


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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


# ----------------------------------------------------------------------------
# Small UI helpers
# ----------------------------------------------------------------------------

func _label(parent: Node, text: String, font_size: int, color: Color, pos: Vector2, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _button(parent: Node, text: String, rect: Rect2, bg: Color, fg: Color, font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, fg)
	b.add_theme_color_override("font_disabled_color", COL_MUTED)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		if state == "pressed":
			sb.bg_color = bg.darkened(0.2)
		if state == "disabled":
			sb.bg_color = COL_PANEL
		sb.set_corner_radius_all(12)
		b.add_theme_stylebox_override(state, sb)
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
	_rect(home, Rect2(0.0, 0.0, 390.0, 844.0), COL_BG)

	# Profile bar: avatar, level, XP bar. Tapping it opens the achievements.
	avatar = Control.new()
	avatar.position = Vector2(16.0, 22.0)
	avatar.size = Vector2(60.0, 60.0)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.draw.connect(_draw_avatar)
	home.add_child(avatar)
	level_label = _label(home, "", 22, COL_TEXT, Vector2(90.0, 22.0))
	xp_label = _label(home, "", 13, COL_MUTED, Vector2(190.0, 29.0), 184.0, HORIZONTAL_ALIGNMENT_RIGHT)
	bar_back = _rect(home, Rect2(90.0, 58.0, 284.0, 16.0), COL_LINE)
	bar_fill = _rect(home, Rect2(90.0, 58.0, 0.0, 16.0), COL_ACCENT)
	var profile_btn := _button(home, "", Rect2(10.0, 14.0, 370.0, 76.0), Color(0.0, 0.0, 0.0, 0.0), COL_TEXT)
	profile_btn.name = "ProfileButton"
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 1.0, 1.0, 0.06 if state == "pressed" else 0.0)
		sb.set_corner_radius_all(12)
		profile_btn.add_theme_stylebox_override(state, sb)
	profile_btn.pressed.connect(show_achievements)

	_label(home, Games.HUB_NAME.to_upper(), 30, COL_TEXT, Vector2(16.0, 106.0), 358.0)
	_label(home, "No ads. No timers. No purchases.", 14, COL_ACCENT, Vector2(16.0, 146.0), 358.0)

	for i in Games.LIST.size():
		_build_tile(i)

	var settings_btn := _button(home, "SETTINGS", Rect2(16.0, 770.0, 171.0, 52.0), COL_PANEL, COL_TEXT)
	settings_btn.name = "SettingsButton"
	settings_btn.pressed.connect(show_settings)
	var trophies_btn := _button(home, "ACHIEVEMENTS", Rect2(203.0, 770.0, 171.0, 52.0), COL_PANEL, COL_TEXT)
	trophies_btn.name = "AchievementsButton"
	trophies_btn.pressed.connect(show_achievements)


func _tile_rect(i: int) -> Rect2:
	var col := i % 2
	var row := i / 2
	return Rect2(Vector2(16.0 + float(col) * (TILE_SIZE.x + TILE_GAP), TILES_TOP + float(row) * (TILE_SIZE.y + TILE_GAP)), TILE_SIZE)


func _build_tile(i: int) -> void:
	var g: Dictionary = Games.LIST[i]
	var r := _tile_rect(i)
	var playable := Games.is_playable(g)
	if playable:
		_panel(home, r, g["bg"], COL_DARK, 4)
		var pic := TextureRect.new()
		pic.texture = load(str(g["art"]))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.position = r.position + Vector2(36.0, 14.0)
		pic.size = Vector2(98.0, 98.0)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		home.add_child(pic)
		_label(home, str(g["title"]), 22, g["fg"], r.position + Vector2(0.0, 116.0), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		tile_progress[g["id"]] = _label(home, "", 12, COL_TEXT, r.position + Vector2(4.0, 144.0), r.size.x - 8.0, HORIZONTAL_ALIGNMENT_CENTER)
		var btn := _button(home, "", r, Color(0.0, 0.0, 0.0, 0.0), COL_TEXT)
		btn.name = "Tile_" + str(g["id"])
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1.0, 1.0, 1.0, 0.10 if state == "pressed" else 0.0)
			sb.set_corner_radius_all(14)
			btn.add_theme_stylebox_override(state, sb)
		btn.pressed.connect(open_game.bind(str(g["id"])))
		tile_buttons[g["id"]] = btn
	else:
		_panel(home, r, COL_PANEL, COL_LINE, 2)
		var named: bool = str(g["id"]) != ""
		if named:
			_label(home, str(g["title"]), 20, COL_MUTED, r.position + Vector2(0.0, 52.0), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
			_label(home, str(g["tagline"]), 13, COL_MUTED, r.position + Vector2(0.0, 84.0), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			_label(home, "???", 40, COL_LINE, r.position + Vector2(0.0, 58.0), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_avatar() -> void:
	var c := Vector2(30.0, 30.0)
	avatar.draw_circle(c, 30.0, COL_ACCENT)
	avatar.draw_circle(c, 26.0, COL_BG)
	var info := Profile.level_info(Profile.xp(Save.section("profile")))
	var font := ThemeDB.fallback_font
	avatar.draw_string(font, Vector2(0.0, 38.0), str(info["level"]), HORIZONTAL_ALIGNMENT_CENTER, 60.0, 24, COL_TEXT)


# Re-reads the save and updates everything on the home screen.
func refresh() -> void:
	var prof := Save.section("profile")
	var info := Profile.level_info(Profile.xp(prof))
	level_label.text = "LEVEL %d" % int(info["level"])
	xp_label.text = "%d / %d XP" % [int(info["into"]), int(info["need"])]
	bar_fill.size.x = bar_back.size.x * float(info["into"]) / float(info["need"])
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(10.0)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", COL_TEXT)
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
	var back := _rect(overlay, Rect2(0.0, 0.0, 390.0, 844.0), COL_BG)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	_label(overlay, title, 30, COL_TEXT, Vector2(16.0, 24.0), 358.0)
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
	_label(o, "%d / %d unlocked" % [got.size(), Achievements.LIST.size()], 14, COL_ACCENT, Vector2(16.0, 66.0), 358.0)
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
		_label(o, str(a["title"]), 18, COL_TEXT if done else COL_MUTED, Vector2(84.0, y + 10.0), 200.0)
		_label(o, str(a["desc"]), 13, COL_MUTED, Vector2(84.0, y + 40.0), 220.0)
		_label(o, "+%d XP" % int(a["xp"]), 14, COL_ACCENT if done else COL_MUTED, Vector2(290.0, y + 26.0), 74.0, HORIZONTAL_ALIGNMENT_RIGHT)


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
