extends Node
# Save autoload (registered as "Save"). One ConfigFile, one section per game plus [profile] and [settings].
# A game gets a live Dictionary for its own section: change it in place, then flush().
# Games never read another game's section.

const DEFAULT_PATH := "user://hub.cfg"
const LEGACY_CATDROP_PATH := "user://catdrop.cfg"
const OLD_PROJECT_DIR := "Cat Drop"   # user:// folder name before the project was renamed Pocket Arcade

var path := DEFAULT_PATH
var sections := {}


func _ready() -> void:
	reload()
	if path == DEFAULT_PATH and not FileAccess.file_exists(path):
		_import_old_user_dir(OS.get_user_data_dir().get_base_dir().path_join(OLD_PROJECT_DIR))
		if sections.is_empty() and FileAccess.file_exists(LEGACY_CATDROP_PATH):
			migrate_catdrop(LEGACY_CATDROP_PATH)


# Picks up saves from before the rename: a hub.cfg is copied, a bare catdrop.cfg is migrated.
func _import_old_user_dir(dir: String) -> void:
	var old_hub := dir.path_join("hub.cfg")
	var old_cat := dir.path_join("catdrop.cfg")
	if FileAccess.file_exists(old_hub):
		DirAccess.copy_absolute(old_hub, ProjectSettings.globalize_path(path))
		reload()
	elif FileAccess.file_exists(old_cat):
		migrate_catdrop(old_cat)


# Tests call this first so they never touch the player's real save.
func use_test_file(test_path: String = "user://test_hub.cfg") -> void:
	path = test_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	sections = {}


func section(id: String) -> Dictionary:
	if not sections.has(id):
		sections[id] = {}
	return sections[id]


func reload() -> void:
	sections = {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for s in cfg.get_sections():
		var d := {}
		for k in cfg.get_section_keys(s):
			d[k] = cfg.get_value(s, k)
		sections[s] = d


func flush() -> void:
	var cfg := ConfigFile.new()
	for s in sections:
		for k in sections[s]:
			cfg.set_value(s, k, sections[s][k])
	cfg.save(path)


func reset_all() -> void:
	sections = {}
	flush()


func reset_section(id: String) -> void:
	sections.erase(id)
	flush()


# Converts the prototype's user://catdrop.cfg into the [catdrop] section. The old file is left alone.
func migrate_catdrop(old_path: String) -> bool:
	var old := ConfigFile.new()
	if old.load(old_path) != OK:
		return false
	var d := {}
	d["coins"] = int(old.get_value("save", "coins", 0))
	d["bonus_balls"] = int(old.get_value("save", "bonus_balls", 0))
	var lv := {}
	if old.has_section("levels"):
		for k in old.get_section_keys("levels"):
			lv[k] = int(old.get_value("levels", k))
	d["levels"] = lv
	var owned := {}
	if old.has_section("owned"):
		for k in old.get_section_keys("owned"):
			owned[k] = int(old.get_value("owned", k))
	d["owned"] = owned
	d["wave"] = int(old.get_value("battle", "wave", 1))
	d["house_hp"] = float(old.get_value("battle", "house_hp", 100.0))
	d["grid"] = old.get_value("battle", "grid", [])
	sections["catdrop"] = d
	flush()
	return true
