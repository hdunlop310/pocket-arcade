class_name Achievements
extends RefCounted
# Achievement definitions. Each game works out which of its own ids currently hold and reports them
# in its progress() result; Profile.award() dedups and pays the XP once.

const LIST := [
	{"id": "cd_first_ball", "game": "catdrop", "title": "First Drop", "desc": "Bank a ball in the cup", "xp": 20},
	{"id": "cd_100_balls", "game": "catdrop", "title": "Ball Pit", "desc": "Bank 100 balls", "xp": 30},
	{"id": "cd_1000_balls", "game": "catdrop", "title": "Avalanche", "desc": "Bank 1000 balls", "xp": 60},
	{"id": "cd_first_wave", "game": "catdrop", "title": "Mouse Trouble", "desc": "Clear wave 1", "xp": 20},
	{"id": "cd_wave_5", "game": "catdrop", "title": "Halfway Home", "desc": "Clear wave 5", "xp": 40},
	{"id": "cd_four_cats", "game": "catdrop", "title": "Pack Leader", "desc": "Own 4 cats", "xp": 30},
	{"id": "cd_maxed", "game": "catdrop", "title": "Maxed Out", "desc": "Max out a board upgrade", "xp": 40},
	{"id": "cd_boss", "game": "catdrop", "title": "Rat King Down", "desc": "Beat the Rat King", "xp": 100},
]

const BY_ID := {
	"cd_first_ball": LIST[0], "cd_100_balls": LIST[1], "cd_1000_balls": LIST[2], "cd_first_wave": LIST[3],
	"cd_wave_5": LIST[4], "cd_four_cats": LIST[5], "cd_maxed": LIST[6], "cd_boss": LIST[7],
}
