extends RigidBody2D
# A single ball. Balls only collide with the board (layer 1), not with each other,
# so big multiplied piles don't jam up.

const RADIUS := 7.0

# Which gates this ball (or its ancestor) has already passed through,
# so a ball can't be multiplied by the same gate twice.
var gates_seen: Dictionary = {}


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

	var mat := PhysicsMaterial.new()
	mat.bounce = 0.4
	mat.friction = 0.1
	physics_material_override = mat

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)

	add_to_group("balls")


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS + 1.5, Color("#0B0B0E"))
	draw_circle(Vector2.ZERO, RADIUS, Color("#F4F4F6"))
