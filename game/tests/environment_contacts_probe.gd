extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const DT: float = 1.0 / 60.0
const IMPACT_SPEED: float = 44.0
var track: Node3D
var cases: Array[Dictionary] = []
var checks: int = 0
var failures: int = 0
var ticks: int = 0


func _initialize() -> void:
	track = Track.new()
	root.add_child.call_deferred(track)
	call_deferred("_prepare")


func _prepare() -> void:
	track.build(false)
	_check(track.load_errors.is_empty(), "valid authored collision package")
	_check(track.data.collision.barriers.size() == (track.data.samples.size() - 1) * 2, "both road edges have continuous barrier segments")
	# Straight, forest bends, bridge slopes and route closure use the real bake.
	for distance: float in [0.0, 40.0, 112.0, 190.0, 302.0, 420.0, 620.0, 730.0]:
		var sample: Dictionary = track.sample_at(distance)
		var forward: Vector3 = Track.Baker.vector(sample.tangent).slide(Vector3.UP).normalized()
		var right: Vector3 = forward.cross(Vector3.UP)
		for side: float in [-1.0, 1.0]:
			for angle: float in [0.0, 45.0, 75.0]:
				var heading: Vector3 = (right * side * cos(deg_to_rad(angle)) + forward * sin(deg_to_rad(angle))).normalized()
				var vehicle: CharacterBody3D = Vehicle.new()
				# Keep coasting impact speed above the normal cap without a powered boost.
				vehicle.configure({"top_speed": 60.0})
				var collider := CollisionShape3D.new()
				collider.shape = Vehicle.create_collision_shape()
				vehicle.add_child(collider)
				vehicle.collision_layer = 2
				vehicle.collision_mask = 1
				root.add_child(vehicle)
				var position: Vector3 = Track.Baker.vector(sample.position) + right * side * 5.5 + Vector3.UP * 0.7
				vehicle.reset_at(Transform3D(Basis.looking_at(heading), position))
				cases.append({"body": vehicle, "heading": heading, "label": "s=%.0f side=%.0f angle=%.0f" % [distance, side, angle], "angle": angle, "contact": false, "escaped": false, "max_speed": 0.0, "max_roll": 0.0})


func _physics_process(_delta: float) -> bool:
	if cases.is_empty():
		return false
	ticks += 1
	for item: Dictionary in cases:
		var vehicle: CharacterBody3D = item.body
		if ticks == 31:
			vehicle.velocity = item.heading * IMPACT_SPEED
		vehicle.step({}, DT)
		if ticks <= 30:
			continue
		item.contact = item.contact or vehicle.is_on_wall()
		item.max_speed = maxf(item.max_speed, vehicle.speed_mps)
		item.max_roll = maxf(item.max_roll, 1.0 - vehicle.global_basis.y.dot(Vector3.UP))
		var nearest: Dictionary = Track.Progress.project(track.data, vehicle.position, 0.0, track.data.length)
		item.escaped = item.escaped or absf(float(nearest.lateral)) > float(nearest.width) * 0.5 + 0.1 or float(nearest.height) < -0.1
	if ticks == 120:
		for item: Dictionary in cases:
			_check(item.contact, "wall contact " + item.label)
			_check(not item.escaped, "no tunnelling or road fall-through " + item.label)
			_check(item.max_speed <= IMPACT_SPEED + 0.05, "stationary geometry does not add speed " + item.label)
			_check(item.max_roll < 0.0001, "no rollover " + item.label)
			if item.angle == 0.0:
				_check(item.body.speed_mps < 4.0, "head-on impact removes forward speed " + item.label)
		print("ENVIRONMENT_CONTACTS_PROBE ", JSON.stringify({"checks": checks, "failures": failures, "cases": cases.size(), "simulation_ticks": ticks, "impact_speed_mps": IMPACT_SPEED, "simulation_hash": track.identity().simulation_hash}))
		quit(0 if failures == 0 else 1)
	return false


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
