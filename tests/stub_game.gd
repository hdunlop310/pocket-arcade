extends GameBase
# Minimal game used to test the hub's handling of finished() and the save slot.

func _init() -> void:
	id = "stub"
	title = "Stub"

func _on_start() -> void:
	slot["started"] = int(slot.get("started", 0)) + 1
