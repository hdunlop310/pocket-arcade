extends SceneTree
# Crops a 256x256 face portrait for the tray chips and upgrade cards out of a sheet's big portrait.
#   GODOT --headless --path . --script tools/crop_portrait.gd -- adora
# Output: games/catdrop/art/<name>.png (the same kind of file macho.png and rosette.png are).

const PORTRAITS := {
	"adora": {"file": "res://art_src/adora_sheet.webp", "rect": Rect2i(92, 100, 240, 240)},
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var name: String = args[0] if args.size() > 0 else "adora"
	if not PORTRAITS.has(name):
		push_error("unknown portrait " + name)
		quit(1)
		return
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(PORTRAITS[name]["file"])) != OK:
		push_error("cannot load sheet")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var face := img.get_region(PORTRAITS[name]["rect"])
	face.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	face.save_png(ProjectSettings.globalize_path("res://games/catdrop/art/%s.png" % name))
	print("saved ", name)
	quit()
