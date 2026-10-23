extends Node
# Screen-wide polish (autoload "Polish"): HDR bloom so the neon actually glows, plus a soft vignette and a
# touch of film grain drawn over everything. Colours brighter than 1.0 (the neon strokes) are what bloom.

const OVERLAY_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform float vignette = 0.38;
uniform float grain = 0.008;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float d = distance(UV, vec2(0.5, 0.46));
	float v = smoothstep(0.38, 0.9, d) * vignette;
	float g = (hash(floor(UV * vec2(390.0, 844.0)) + vec2(floor(TIME * 24.0) * 17.0, 3.0)) - 0.5) * grain;
	float ag = abs(g);
	vec3 cg = vec3(g > 0.0 ? 1.0 : 0.0);
	float a = ag + v * (1.0 - ag);
	vec3 rgb = a > 0.0 ? (cg * ag) / a : vec3(0.0);
	COLOR = vec4(rgb, a);
}
"""

const SHINE_SHADER := """
shader_type canvas_item;

uniform float speed = 0.3;
uniform float width = 0.16;
uniform float strength = 0.5;

void fragment() {
	float pos = fract(TIME * speed) * 2.6 - 0.8;
	float d = (UV.x + UV.y * 0.4) - pos;
	float band = smoothstep(width, 0.0, abs(d));
	COLOR.rgb += band * strength * COLOR.a;
}
"""

static var _shine: ShaderMaterial


# A material that sweeps a soft highlight across a button every few seconds.
static func shine_material() -> ShaderMaterial:
	if _shine == null:
		var sh := Shader.new()
		sh.code = SHINE_SHADER
		_shine = ShaderMaterial.new()
		_shine.shader = sh
	return _shine


func _ready() -> void:
	if OS.get_environment("NO_POLISH") == "1":
		return
	get_tree().root.use_hdr_2d = OS.get_environment("NO_HDR") != "1"
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 1.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3] else 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	if OS.get_environment("NO_OVERLAY") == "1":
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var rect := ColorRect.new()
	rect.size = Vector2(390.0, 844.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = OVERLAY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	layer.add_child(rect)
