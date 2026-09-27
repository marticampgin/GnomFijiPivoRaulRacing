extends SceneTree

const VehicleScript = preload("res://vehicle/racing_vehicle.gd")
const DT: float = 1.0 / 60.0
var world: Node3D
var failures: int = 0
var checks: int = 0
var measurements: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	_floor(Vector3.ZERO, Basis.IDENTITY)
	await physics_frame
	await _character_probes()
	await _native_probes()
	print("VEHICLE_PROBE ", JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}))
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _character_probes() -> void:
	var vehicle: CharacterBody3D = _character(Vector3(0.0, 0.8, 0.0))
	await _steps(vehicle, 90, {})
	_check(vehicle.grounded, "CharacterBody settles on floor")
	await _steps(vehicle, 120, {"throttle": 1.0})
	_check(vehicle.speed_mps > 20.0, "CharacterBody accelerates")
	var before: Vector3 = -vehicle.global_basis.z
	await _steps(vehicle, 70, {"throttle": 1.0, "steering": 0.6, "drift": true})
	var low_charge: float = vehicle.drift_charge
	_check(low_charge > 0.5, "valid drift accumulates charge")
	_check(before.dot(-vehicle.global_basis.z) < 0.8, "steering turns the vehicle")
	_check(absf(vehicle.velocity.dot(vehicle.global_basis.x)) > 1.0, "drift preserves lateral slip")
	var state: Dictionary = vehicle.capture_state()
	await _steps(vehicle, 1, {"throttle": 1.0})
	_check(vehicle.boost_remaining > 1.0, "releasing charged drift awards boost")
	_check(vehicle.drift_charge == 0.0, "boost consumes charge")
	await _steps(vehicle, 25, {"throttle": 1.0})
	_check(vehicle.speed_mps > float(vehicle.stats["top_speed"]), "boost exceeds normal speed cap")
	await _steps(vehicle, 180, {"throttle": 1.0})
	_check(vehicle.boost_remaining == 0.0, "boost expires without a repeated award")
	vehicle.restore_state(state)
	_check(vehicle.capture_state() == state, "state round trip preserves drift and physics state")
	vehicle.reset_at(Transform3D(Basis.IDENTITY, Vector3(50.0, 0.8, 0.0)))
	_check(vehicle.boost_remaining == 0.0 and vehicle.drift_charge == 0.0, "respawn clears boost and drift")
	await _steps(vehicle, 70, {"steering": 1.0, "drift": true})
	_check(vehicle.drift_charge == 0.0, "stationary steering does not farm charge")
	_check(vehicle.global_basis.is_equal_approx(Basis.IDENTITY), "stationary steering without throttle does not rotate")
	await _steps(vehicle, 120, {"throttle": 1.0, "drift": true})
	_check(vehicle.drift_charge == 0.0, "straight driving does not farm charge")
	await _steps(vehicle, 3, {"throttle": 1.0, "steering": 0.6, "drift": true})
	await _steps(vehicle, 1, {"throttle": 1.0})
	_check(vehicle.boost_remaining == 0.0, "short uncharged drift gives no boost")
	await _steps(vehicle, 50, {"throttle": 1.0, "steering": 0.6, "drift": true})
	_check(vehicle.drift_charge > 0.25, "second drift can earn fresh charge")
	vehicle.velocity += Vector3.UP * 12.0
	var jump_origin: float = vehicle.position.y
	await _steps(vehicle, 20, {"throttle": 1.0, "steering": 1.0, "drift": true})
	_check(vehicle.position.y > jump_origin + 1.0, "jump detaches despite floor snap")
	_check(not vehicle.grounded and vehicle.drift_charge == 0.0, "airborne drift cannot earn boost")
	await _steps(vehicle, 1, {})
	_check(vehicle.boost_remaining == 0.0, "releasing drift in air gives no boost")
	await _steps(vehicle, 120, {})
	_check(vehicle.grounded, "jump returns to ground")
	vehicle.configure({"drift": 2.0})
	vehicle.reset_at(Transform3D(Basis.IDENTITY, Vector3(100.0, 0.8, 0.0)))
	await _steps(vehicle, 120, {"throttle": 1.0})
	await _steps(vehicle, 70, {"throttle": 1.0, "steering": 0.6, "drift": true})
	_check(vehicle.drift_charge > low_charge, "drift stat increases charge rate")
	measurements["character_charge_default"] = low_charge
	measurements["character_charge_drift_2"] = vehicle.drift_charge
	vehicle.reset_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 10.0, 0.0)))
	await _steps(vehicle, 20, {}, Vector3.RIGHT)
	_check(vehicle.velocity.x < -5.0, "local gravity accelerates along requested down")
	_check(vehicle.global_basis.y.dot(Vector3.RIGHT) > 0.999, "local frame follows gravity up")
	_check(absf(vehicle.velocity.y) < 0.001, "world Y gravity is not applied in local frame")
	var wall_basis: Basis = Basis(Vector3.FORWARD, PI * 0.5)
	_floor(Vector3(500.0, 20.0, 0.0), wall_basis)
	vehicle.reset_at(Transform3D(wall_basis, Vector3(500.8, 20.0, 0.0)))
	await _steps(vehicle, 90, {}, Vector3.RIGHT)
	_check(vehicle.grounded, "wall is a floor in local gravity")
	await _steps(vehicle, 120, {"throttle": 1.0}, Vector3.RIGHT)
	_check(vehicle.grounded and vehicle.speed_mps > 20.0, "vehicle drives along vertical surface")
	var barrier: StaticBody3D = StaticBody3D.new()
	var barrier_collider: CollisionShape3D = CollisionShape3D.new()
	var barrier_shape: BoxShape3D = BoxShape3D.new()
	barrier_shape.size = Vector3(12.0, 2.0, 0.5)
	barrier_collider.shape = barrier_shape
	barrier.add_child(barrier_collider)
	barrier.position = Vector3(-100.0, 1.0, -4.0)
	world.add_child(barrier)
	vehicle.configure()
	vehicle.reset_at(Transform3D(Basis.IDENTITY, Vector3(-100.0, 0.8, 0.0)))
	await _steps(vehicle, 120, {"throttle": 1.0})
	measurements["head_on_stop"] = {"speed": vehicle.speed_mps, "wall": vehicle.is_on_wall(), "position": [vehicle.position.x, vehicle.position.y, vehicle.position.z]}
	var barrier_position: Vector3 = vehicle.position
	var maximum_wall_motion: float = 0.0
	var wall_contact: bool = vehicle.is_on_wall()
	for tick: int in 120:
		await _steps(vehicle, 1, {"throttle": 1.0})
		maximum_wall_motion = maxf(maximum_wall_motion, vehicle.position.distance_to(barrier_position))
		wall_contact = wall_contact or vehicle.is_on_wall()
	# Solver margin can retain a small attempted velocity; verify actual motion.
	measurements["head_on_hold_motion"] = maximum_wall_motion
	_check(wall_contact and maximum_wall_motion < 0.03 and vehicle.position.z > -2.73, "head-on barrier holds the kart under sustained throttle")
	await _steps(vehicle, 240, {"throttle": 1.0, "steering": 1.0})
	measurements["head_on_escape_distance"] = absf(vehicle.position.x - barrier_position.x)
	_check(absf(vehicle.position.x - barrier_position.x) > 2.0, "powered low-speed steering escapes a head-on stop")
	vehicle.queue_free()
	await physics_frame


func _native_probes() -> void:
	var native: VehicleBody3D = VehicleBody3D.new()
	native.mass = 80.0
	native.position = Vector3(-200.0, 1.0, 0.0)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1.5, 0.6, 2.4)
	collider.shape = shape
	collider.position.y = 0.65
	native.add_child(collider)
	for x: float in [-0.8, 0.8]:
		for z: float in [-0.8, 0.8]:
			var wheel: VehicleWheel3D = VehicleWheel3D.new()
			wheel.position = Vector3(x, 0.35, z)
			wheel.wheel_radius = 0.35
			wheel.wheel_rest_length = 0.3
			wheel.suspension_travel = 0.3
			wheel.suspension_stiffness = 30.0
			wheel.use_as_traction = true
			wheel.use_as_steering = z > 0.0
			native.add_child(wheel)
	world.add_child(native)
	await _wait(120)
	native.engine_force = 140.0
	await _wait(120)
	measurements["native_acceleration_speed"] = native.linear_velocity.length()
	_check(native.linear_velocity.length() > 1.0, "VehicleBody candidate accelerates")
	native.steering = 0.3
	for child: Node in native.get_children():
		if child is VehicleWheel3D:
			child.wheel_friction_slip = 0.8
	await _wait(60)
	measurements["native_low_grip_lateral_speed"] = absf(native.linear_velocity.dot(native.global_basis.x))
	_check(native.global_transform.is_finite(), "VehicleBody low-grip steering stays finite")
	var y_before: float = native.position.y
	native.apply_central_impulse(Vector3.UP * native.mass * 12.0)
	await _wait(20)
	_check(native.position.y > y_before + 1.0, "VehicleBody jump candidate detaches")
	native.gravity_scale = 0.0
	native.constant_force = Vector3.LEFT * native.mass * 28.0
	var x_before: float = native.linear_velocity.x
	await _wait(30)
	_check(native.linear_velocity.x < x_before - 5.0, "VehicleBody custom gravity force changes velocity")
	measurements["native_frame_up_after_local_gravity"] = native.global_basis.y.dot(Vector3.RIGHT)
	# Force direction alone does not align the suspension/chassis to a new surface.
	_check(absf(native.global_basis.y.dot(Vector3.RIGHT)) < 0.95, "native local gravity still needs chassis orientation control")
	native.queue_free()
	await physics_frame


func _character(origin: Vector3) -> CharacterBody3D:
	var vehicle: CharacterBody3D = VehicleScript.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = VehicleScript.create_collision_shape()
	vehicle.add_child(collider)
	world.add_child(vehicle)
	vehicle.reset_at(Transform3D(Basis.IDENTITY, origin))
	return vehicle


func _floor(origin: Vector3, orientation: Basis) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(600.0, 1.0, 600.0)
	collider.shape = shape
	collider.position.y = -0.5
	body.add_child(collider)
	body.transform = Transform3D(orientation, origin)
	world.add_child(body)


func _steps(vehicle: CharacterBody3D, count: int, input: Dictionary, up: Vector3 = Vector3.UP) -> void:
	for index: int in count:
		await physics_frame
		vehicle.step(input, DT, up)


func _wait(count: int) -> void:
	for index: int in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)
