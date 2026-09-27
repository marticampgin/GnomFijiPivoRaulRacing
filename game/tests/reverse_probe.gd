extends SceneTree

const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Protocol = preload("res://net/prototype_protocol.gd")
const DT: float = 1.0 / 60.0
var checks: int = 0
var failures: int = 0
var kart: CharacterBody3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500.0, 1.0, 500.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	kart = Vehicle.new()
	var collider := CollisionShape3D.new()
	collider.shape = Vehicle.create_collision_shape()
	kart.add_child(collider)
	root.add_child(kart)
	kart.reset_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.0)))
	await _steps(30, Protocol.BLOCKED)
	_check(kart.grounded, "fixture grounded")
	await _steps(60, {"throttle": 1.0})
	_check(_speed() > 10.0, "forward acceleration")
	var saw_stop: bool = false
	for tick: int in 80:
		var before: float = _speed()
		await _steps(1, {"brake": 1.0})
		if before > 0.0:
			_check(_speed() >= -0.00001, "brake cannot cross forward motion directly into reverse")
		if absf(_speed()) < 0.00001:
			saw_stop = true
	_check(saw_stop and _speed() < -1.0, "held brake stops then reverses")
	await _steps(60, {"brake": 1.0})
	_check(absf(_speed() + Vehicle.REVERSE_MAX_SPEED) < 0.01, "reverse reaches bounded speed")
	kart.boost_remaining = 2.0
	await _steps(20, {"brake": 1.0})
	_check(absf(_speed() + Vehicle.REVERSE_MAX_SPEED) < 0.01, "boost cannot increase reverse speed")
	kart.velocity = kart.global_basis.z * 12.0
	await _steps(1, {"brake": 1.0})
	_check(_speed() < -11.9 and _speed() > -12.0, "backward contact overspeed retains momentum without gaining engine energy")
	await _steps(65, {"brake": 1.0})
	_check(absf(_speed() + Vehicle.REVERSE_MAX_SPEED) < 0.01, "backward contact overspeed coasts down to reverse cap")
	var basis_before: Basis = kart.global_basis
	await _steps(12, {"brake": 1.0, "steering": 1.0})
	_check((-kart.global_basis.z).x < (-basis_before.z).x, "reverse steering yaw opposes forward yaw")
	var snapshot: Dictionary = Protocol.unpack_state(Protocol.pack_state(kart.capture_state()))
	_check(not snapshot.is_empty(), "reverse state passes network validation")
	await _steps(1, {"brake": 1.0, "steering": 0.5})
	var expected: Dictionary = kart.capture_state()
	kart.restore_state(snapshot)
	await _steps(1, {"brake": 1.0, "steering": 0.5})
	_check(kart.global_position.distance_to(expected.transform.origin) < 0.001 and kart.velocity.distance_to(expected.velocity) < 0.001, "reverse reconciliation reproduces next tick")
	await _steps(60, {"throttle": 1.0})
	_check(_speed() > 0.0, "throttle stops reverse then accelerates forward")
	await _steps(90, Protocol.BLOCKED)
	_check(absf(_speed()) < 0.001, "blocked command parks despite live boost")
	kart.boost_remaining = 2.0
	await _steps(30, Protocol.BLOCKED)
	_check(absf(_speed()) < 0.001, "countdown finish lost-input parking never reverses")
	kart.boost_remaining = 0.0
	await _steps(30, Protocol.NEUTRAL)
	_check(absf(_speed()) < 0.001, "wire neutral never reverses")
	await _steps(30, {"throttle": 1.0, "brake": 1.0})
	_check(absf(_speed()) < 0.001, "simultaneous pedals do not reverse")
	var wire: Dictionary = Protocol.NEUTRAL.duplicate()
	wire.merge({"type": "input", "sequence": 1})
	_check(not Protocol.validate_input(wire).is_empty(), "neutral preserves input packet schema")
	wire.drive_blocked = true
	_check(Protocol.validate_input(wire).is_empty(), "clients cannot inject simulation-only parking flag")
	print("REVERSE_PROBE ", JSON.stringify({"checks": checks, "failures": failures}))
	kart.queue_free()
	floor_body.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _speed() -> float:
	return kart.velocity.dot(-kart.global_basis.z)


func _steps(count: int, command: Dictionary) -> void:
	for index: int in count:
		await physics_frame
		kart.step(command, DT)


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
