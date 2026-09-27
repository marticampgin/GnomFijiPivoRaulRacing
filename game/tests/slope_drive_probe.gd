extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Baker = preload("res://track/track_baker.gd")
const Protocol = preload("res://net/prototype_protocol.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const DT: float = 1.0 / 60.0
const RETAINED_SPEED: float = 0.75

# Physical state and the next 12 inputs from the 2026-09-27 server trace.
# Tick 120174 is excluded: its 14.2 m displacement and ack jump were recovery.
const FIXTURES: Array[Dictionary] = [
	{
		"tick": 120546, "ack": 1300,
		"position": Vector3(91.7655334472656, 0.251363605260849, 90.4457244873047),
		"basis": Basis(Vector3(-0.84481292963028, 0.0, -0.535061895847321), Vector3.UP, Vector3(0.535061895847321, 0.0, -0.84481292963028)),
		"velocity": Vector3(-12.0284633636475, 0.0, 19.52219581604),
		"throttle": 1.0, "steering": [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
	},
	{
		"tick": 121050, "ack": 1799,
		"position": Vector3(-72.3734817504883, 3.79792857170105, 102.306159973145),
		"basis": Basis(Vector3(0.548885405063629, 0.0, -0.83589768409729), Vector3.UP, Vector3(0.83589768409729, 0.0, 0.548885405063629)),
		"velocity": Vector3(-20.3354816436768, 0.0, -12.9290256500244),
		"throttle": 0.0, "steering": [0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0],
	},
	{
		"tick": 121113, "ack": 1862,
		"position": Vector3(-76.5404205322266, 4.11640310287476, 99.4901733398438),
		"basis": Basis(Vector3(0.600285947322845, 0.0, -0.799785494804382), Vector3.UP, Vector3(0.799785494804382, 0.0, 0.600285947322845)),
		"velocity": Vector3(-9.59659481048584, 0.0, -6.94157314300537),
		"throttle": 1.0, "steering": [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0],
	},
	{
		"tick": 121158, "ack": 1907,
		"position": Vector3(-79.2257766723633, 4.34034156799316, 97.4506072998047),
		"basis": Basis(Vector3(0.62377142906189, 0.0, -0.781606912612915), Vector3.UP, Vector3(0.781606912612915, 0.0, 0.62377142906189)),
		"velocity": Vector3(-7.49310636520386, 0.0, -5.8053297996521),
		"throttle": 1.0, "steering": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	},
]

var _checks: int = 0
var _failures: int = 0
var _track: Node3D
var _measurements: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_track = Track.new()
	_check(_track.load_errors.is_empty(), "authored collision package is valid")
	if not _track.load_errors.is_empty():
		_track.free()
		quit(1)
		return
	root.add_child(_track)
	_track.build(false)
	for fixture: Dictionary in FIXTURES:
		await _run_fixture(fixture, false)
		await _run_fixture(fixture, true)
	await _check_old_box_control()
	await _check_barrier_control()
	print("SLOPE_DRIVE_PROBE ", JSON.stringify({"passed": _failures == 0, "checks": _checks, "failures": _failures, "balance_version": Vehicle.BALANCE_VERSION, "fixtures": _measurements}))
	_track.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)


func _new_car(old_box: bool = false) -> CharacterBody3D:
	var car := Vehicle.new()
	var collider := CollisionShape3D.new()
	if old_box:
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.25, 0.7, 2.1)
		collider.shape = shape
	else:
		collider.shape = Vehicle.create_collision_shape()
	car.add_child(collider)
	car.collision_layer = 2
	car.collision_mask = 1
	root.add_child(car)
	return car


func _fixture_state(car: CharacterBody3D, fixture: Dictionary) -> Dictionary:
	var state: Dictionary = car.capture_state()
	state.transform = Transform3D(fixture.basis, fixture.position)
	state.velocity = fixture.velocity
	state.grounded = true
	return state


func _command(fixture: Dictionary, tick: int) -> Dictionary:
	return {"type": "input", "sequence": int(fixture.ack) + tick + 1,
		"throttle": fixture.throttle, "steering": float(fixture.steering[tick]),
		"brake": 0.0, "drift_left": false, "drift_right": false}


func _wire_roundtrip(state: Dictionary) -> Dictionary:
	return Protocol.unpack_state(JSON.parse_string(JSON.stringify(Protocol.pack_state(state))))


func _run_fixture(fixture: Dictionary, replay: bool) -> void:
	var car: CharacterBody3D = _new_car()
	var seeded: Dictionary = _fixture_state(car, fixture)
	var decoded: Dictionary = _wire_roundtrip(seeded)
	var label: String = "tick %d %s" % [fixture.tick, "replay" if replay else "direct"]
	_check(not decoded.is_empty() and decoded.transform.is_equal_approx(seeded.transform) and decoded.velocity.is_equal_approx(seeded.velocity), label + " packed JSON preserves physical seed")
	car.restore_state(decoded if replay else seeded)
	var initial_speed: float = car.speed_mps
	var minimum_speed: float = initial_speed
	var maximum_replay_error: float = 0.0
	var maximum_velocity_error: float = 0.0
	var replay_basis_matches: bool = true
	var grounded_ticks: int = 0
	var history: Array[Dictionary] = []
	var snapshot: Dictionary = {}
	for tick: int in 12:
		await physics_frame
		if replay and tick % 3 == 0:
			snapshot = _wire_roundtrip(car.capture_state())
		var command: Dictionary = _command(fixture, tick)
		car.step(command, DT)
		minimum_speed = minf(minimum_speed, car.speed_mps)
		if car.grounded:
			grounded_ticks += 1
		if replay:
			history.append(command)
			if history.size() == 3:
				# Same fixed-tick restore plus pending-command replay as the client.
				var before: Vector3 = car.position
				var before_velocity: Vector3 = car.velocity
				var before_basis: Basis = car.global_basis
				car.restore_state(snapshot)
				for pending: Dictionary in history:
					car.step(pending, DT)
					minimum_speed = minf(minimum_speed, car.speed_mps)
				maximum_replay_error = maxf(maximum_replay_error, before.distance_to(car.position))
				maximum_velocity_error = maxf(maximum_velocity_error, before_velocity.distance_to(car.velocity))
				replay_basis_matches = replay_basis_matches and before_basis.is_equal_approx(car.global_basis)
				history.clear()
	_check(minimum_speed >= initial_speed * RETAINED_SPEED, label + " retains at least 75% speed across 12 ticks")
	_check(car.position.is_finite() and not _track.needs_recovery(car.position), label + " remains in the authored corridor")
	_check(grounded_ticks >= 11, label + " remains supported by the road")
	if replay:
		_check(maximum_replay_error < 0.02, label + " agrees with the unreplayed position within 2 cm")
		_check(maximum_velocity_error < 0.02 and replay_basis_matches, label + " preserves unreplayed velocity and heading")
	_measurements.append({"tick": fixture.tick, "replay": replay, "initial_speed": initial_speed,
		"minimum_speed": minimum_speed, "final_speed": car.speed_mps,
		"grounded_ticks": grounded_ticks, "maximum_replay_error": maximum_replay_error,
		"maximum_velocity_error": maximum_velocity_error, "replay_basis_matches": replay_basis_matches})
	car.queue_free()
	await process_frame


func _check_old_box_control() -> void:
	var car: CharacterBody3D = _new_car(true)
	car.restore_state(_fixture_state(car, FIXTURES[0]))
	var initial_speed: float = car.speed_mps
	var minimum_speed: float = initial_speed
	for tick: int in 3:
		await physics_frame
		car.step(_command(FIXTURES[0], tick), DT)
		minimum_speed = minf(minimum_speed, car.speed_mps)
	_check(minimum_speed < initial_speed * 0.25, "old sharp box reproduces the captured edge stop within three ticks")
	_measurements.append({"control": "old_sharp_box", "initial_speed": initial_speed, "minimum_speed": minimum_speed})
	car.queue_free()
	await process_frame


func _check_barrier_control() -> void:
	var car: CharacterBody3D = _new_car()
	var barrier: Dictionary = _track.data.collision.barriers[0]
	var wall: Vector3 = Baker.vector(barrier.position)
	var center: Vector3 = Baker.vector(_track.sample_at(1.0).position)
	var outward: Vector3 = Vector3.UP.cross(Baker.vector(barrier.forward)).normalized()
	if outward.dot(wall - center) < 0.0:
		outward = -outward
	car.reset_at(Transform3D(Basis.looking_at(outward), wall - outward * 3.0 + Vector3.DOWN * 0.28))
	for tick: int in 12:
		await physics_frame
		car.step({}, DT)
	car.velocity = outward * 20.0
	var barrier_contact: bool = false
	for tick: int in 30:
		await physics_frame
		car.step({"throttle": 1.0}, DT)
		for index: int in car.get_slide_collision_count():
			var contact: KinematicCollision3D = car.get_slide_collision(index)
			for hit: int in contact.get_collision_count():
				if contact.get_collider(hit) != _track.get_node("RoadCollision") and absf(contact.get_normal(hit).y) < 0.2:
					barrier_contact = true
	var held_position: Vector3 = car.position
	var maximum_motion: float = 0.0
	var maximum_outward: float = (car.position - wall).dot(outward)
	for tick: int in 90:
		await physics_frame
		car.step({"throttle": 1.0}, DT)
		maximum_motion = maxf(maximum_motion, (car.position - held_position).slide(Vector3.UP).length())
		maximum_outward = maxf(maximum_outward, (car.position - wall).dot(outward))
	_check(barrier_contact, "production hull still collides with an actual authored barrier")
	_check(maximum_motion < 0.03, "sustained full throttle moves less than 3 cm while held against the barrier")
	_check(maximum_outward < -float(barrier.size[0]) * 0.5, "kart center never crosses the barrier's inner face")
	_measurements.append({"control": "authored_barrier", "contact": barrier_contact, "final_speed": car.speed_mps,
		"maximum_held_motion": maximum_motion, "maximum_outward_offset": maximum_outward})
	car.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
