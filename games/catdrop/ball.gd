extends RigidBody2D
# A single ball. Balls only collide with the board (layer 1), not with each other,
# so big multiplied piles don't jam up. It draws itself stretched along its velocity,
# squashes when it hits something, pops when a gate multiplies it, and leaves a short fading trail.

signal hit(pos: Vector2)   # touched a peg or wall; pos is the other body's position

const RADIUS := 7.0
const TRAIL := 7

# Which gates this ball (or its ancestor) has already passed through,
# so a ball can't be multiplied by the same gate twice.
var gates_seen: Dictionary = {}
var squash_t := 0.0
var pop_t := 0.0           # set by the board when a gate spawns this ball: it grows in
var trail: Array[Vector2] = []


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	contact_monitor = true
	max_contacts_reported = 3
	body_entered.connect(_on_body_entered)

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


func _on_body_entered(body: Node) -> void:
	squash_t = 0.09
	if body is Node2D:
		hit.emit((body as Node2D).global_position)


func _process(delta: float) -> void:
	squash_t = maxf(squash_t - delta, 0.0)
	pop_t = maxf(pop_t - delta, 0.0)
	trail.append(global_position)
	if trail.size() > TRAIL:
		trail.pop_front()
	queue_redraw()


func _draw() -> void:
	# trail: older points are smaller and more transparent, fading from yellow to pink
	for i in trail.size():
		var k := float(i) / float(TRAIL)
		draw_circle(to_local(trail[i]), RADIUS * (0.25 + 0.6 * k), Color(Color("#E0285E").lerp(Color("#F2A81D"), k), 0.5 * k))
	# body: stretched along the velocity, squashed on impact, grown while popping in
	var speed := linear_velocity.length()
	var stretch := clampf(speed / 1100.0, 0.0, 0.5)
	var sx := 1.0 + stretch
	var sy := 1.0 - stretch * 0.55
	if squash_t > 0.0:
		# impact timeline (90ms): hold (1.2, 0.7) for 40ms, spring to (0.8, 1.2) by 65ms, settle to (1, 1)
		var e := 0.09 - squash_t
		var sq := Vector2(1.2, 0.7)
		if e >= 0.065:
			sq = Vector2(0.8, 1.2).lerp(Vector2.ONE, (e - 0.065) / 0.025)
		elif e >= 0.04:
			sq = Vector2(1.2, 0.7).lerp(Vector2(0.8, 1.2), (e - 0.04) / 0.025)
		sx *= sq.x
		sy *= sq.y
	var grow := 1.0 + 0.7 * (pop_t / 0.25)
	draw_set_transform(Vector2.ZERO, linear_velocity.angle() - global_rotation, Vector2(sx, sy) * grow)
	draw_circle(Vector2.ZERO, RADIUS + 1.8, Color("#0B0B0E"))
	draw_circle(Vector2.ZERO, RADIUS, Color(1.55, 1.1, 0.25))
	draw_circle(Vector2(-2.0, -2.2), RADIUS * 0.42, Color(2.0, 1.8, 1.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
