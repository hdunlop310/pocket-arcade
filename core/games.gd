class_name Games
extends RefCounted
# Registry of the games the hub can show. A game without a "scene" is a locked "coming soon" tile.

const HUB_NAME := "Pocket Arcade"

const LIST := [
	{
		"id": "catdrop", "title": "CAT DROP", "tagline": "Drop balls, build a cat army",
		"scene": "res://games/catdrop/catdrop.tscn",
		"bg": Color("#7E1236"), "fg": Color("#F2A81D"), "art": "res://games/catdrop/art/macho.png",
	},
	{"id": "carsort", "title": "CAR SORT", "tagline": "Coming soon", "scene": ""},
	{"id": "", "title": "???", "tagline": "", "scene": ""},
	{"id": "", "title": "???", "tagline": "", "scene": ""},
	{"id": "", "title": "???", "tagline": "", "scene": ""},
	{"id": "", "title": "???", "tagline": "", "scene": ""},
]


static func is_playable(g: Dictionary) -> bool:
	return str(g["scene"]) != ""


# The small line under a tile, worked out from the game's own save section (no scene needed).
static func progress_text(g: Dictionary, slot: Dictionary) -> String:
	if str(g["id"]) == "catdrop":
		if slot.is_empty():
			return "New game"
		return "Wave %d/10  -  %d coins" % [int(slot.get("wave", 1)), int(slot.get("coins", 0))]
	return str(g["tagline"])
