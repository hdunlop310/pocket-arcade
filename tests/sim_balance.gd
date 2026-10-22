extends Node
# Balance sweep: for each roster, how far does a full 10-wave run get?
# Cats are placed sensibly (Macho at the front, hole first; Rosette on raised tiles first).
# House health carries between waves, cats heal between waves. Prints one line per roster.

const BattleScript := preload("res://games/catdrop/battle.gd")
const SEEDS := 6
const STEP_DT := 1.0 / 12.0

func place_roster(b, machos: int, rosettes: int) -> void:
	b.owned = {"macho": machos, "rosette": rosettes}
	for i in 16:
		b.grid[i] = ""
	var macho_slots := [1, 0, 2, 3, 5, 7, 9, 15]
	var rosette_slots := [4, 6, 11, 12, 8, 10, 13, 14]
	for n in machos:
		b.grid[macho_slots[n]] = "macho"
	for n in rosettes:
		b.grid[rosette_slots[n]] = "rosette"

func waves_cleared(machos: int, rosettes: int, seed_: int) -> int:
	var b = BattleScript.new()
	add_child(b)
	b.rng.seed = seed_
	place_roster(b, machos, rosettes)
	var cleared := 0
	for w in 10:
		b.start_wave()
		var steps := 0
		while b.active and steps < 60000:
			b.step(STEP_DT)
			steps += 1
		# A failed run resets the wave counter to 1; a cleared wave advances it (or completes the run).
		if w < 9 and b.wave == w + 2:
			cleared += 1
		elif w == 9 and b.wave == 1 and b.house_hp >= b.HOUSE_MAX:
			cleared += 1
		else:
			break
	b.queue_free()
	return cleared

func _ready() -> void:
	var rosters := [[1, 0], [1, 1], [2, 2], [3, 3], [4, 4], [5, 5]]
	for r in rosters:
		var total := 0
		var full := 0
		for s in SEEDS:
			var c := waves_cleared(r[0], r[1], 1000 + s)
			total += c
			if c >= 10:
				full += 1
		print("ROSTER %dM+%dR (%d cats): avg waves cleared %.1f, full clears %d/%d" % [r[0], r[1], r[0] + r[1], float(total) / float(SEEDS), full, SEEDS])
	get_tree().quit()
