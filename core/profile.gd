class_name Profile
extends RefCounted
# Shared profile: total XP -> level, and achievement unlocking. Lives in the [profile] save section.
# Pure functions over a section Dictionary, so they test without a scene.

const BASE_XP := 100        # XP to go from level 1 to 2
const STEP_XP := 50         # each later level needs this much more


static func xp_for_level(level: int) -> int:
	return BASE_XP + STEP_XP * (level - 1)


# Returns {level, into, need}: current level, XP earned inside it, XP needed to finish it.
static func level_info(total_xp: int) -> Dictionary:
	var level := 1
	var left := maxi(total_xp, 0)
	while left >= xp_for_level(level):
		left -= xp_for_level(level)
		level += 1
	return {"level": level, "into": left, "need": xp_for_level(level)}


static func xp(section: Dictionary) -> int:
	return int(section.get("xp", 0))


static func unlocked(section: Dictionary) -> Array:
	return section.get("achievements", [])


# Adds XP and unlocks achievements (each pays its own XP once). Returns the newly unlocked ids.
static func award(section: Dictionary, add_xp: int, achievement_ids: Array) -> Array:
	var got: Array = unlocked(section).duplicate()
	var fresh: Array = []
	var total := xp(section) + maxi(add_xp, 0)
	for aid in achievement_ids:
		var a := str(aid)
		if got.has(a) or not Achievements.BY_ID.has(a):
			continue
		got.append(a)
		fresh.append(a)
		total += int(Achievements.BY_ID[a]["xp"])
	section["xp"] = total
	section["achievements"] = got
	return fresh
