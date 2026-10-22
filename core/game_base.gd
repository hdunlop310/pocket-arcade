class_name GameBase
extends Node2D
# Common interface for every game in the hub (see docs/HUB.md).
# The hub instances the scene, calls start(slot), and listens to the signals.
# `slot` is the game's own live save section: change it in place, then emit save_requested.

signal progress(result: Dictionary)   # {xp = 10, achievements = ["id", ...]}; the game keeps running
signal finished(result: Dictionary)   # same keys plus anything extra, e.g. stars; hub returns to the picker
signal quit_requested                 # player pressed the hub button
signal save_requested

var id := ""
var title := ""
var icon: Texture2D
var slot: Dictionary = {}
var started := false


func start(save_slot: Dictionary) -> void:
	slot = save_slot
	started = true
	_on_start()


# Games override this to load from `slot` and refresh their UI.
func _on_start() -> void:
	pass


func suspend() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false


func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true


# Runs the game without a hub (F6 in the editor, tests): uses the Save autoload directly.
func start_standalone() -> void:
	if started:
		return
	var save: Node = Engine.get_main_loop().root.get_node("Save")
	save_requested.connect(save.flush)
	start(save.section(id))
