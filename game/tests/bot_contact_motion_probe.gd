extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Driver = preload("res://ai/racing_bot_driver.gd")
const Contacts = preload("res://vehicle/vehicle_contacts.gd")
const DT: float = 1.0 / 60.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var track := Track.new()
	root.add_child(track)
	track.build(false)
	var racers: Array = []
	var bodies: Array = []
	for slot: int in 10:
		var car: CharacterBody3D = _car(track.spawn_transform(slot))
		bodies.append(car)
		racers.append({"car": car, "driver": Driver.new(track, slot), "progress": track.initial_progress(), "last_correction": Vector3.ZERO})
	var max_correction: float = 0.0
	var max_speed_change: float = 0.0
	var max_tick_distance: float = 0.0
	var corrections_over_10cm: int = 0
	var corrections_over_30cm: int = 0
	var slow_reversals: int = 0
	var moving_reversals: int = 0
	var recoveries: int = 0
	var resolutions: int = 0
	var worst: Dictionary = {}
	for tick: int in 720:
		await physics_frame
		var previous: Dictionary = {}
		var before_contact: Dictionary = {}
		var speeds: Dictionary = {}
		for racer: Dictionary in racers:
			var car: CharacterBody3D = racer.car
			previous[car.get_instance_id()] = car.global_transform
			car.step(racer.driver.sample(car, racer.progress, DT), DT)
			before_contact[car.get_instance_id()] = car.position
			speeds[car.get_instance_id()] = car.velocity
		resolutions += Contacts.resolve(bodies, previous, bodies)
		for slot: int in racers.size():
			var racer: Dictionary = racers[slot]
			var car: CharacterBody3D = racer.car
			var correction: Vector3 = car.position - before_contact[car.get_instance_id()]
			var distance: float = correction.length()
			if distance > max_correction:
				max_correction = distance
				worst = {"tick": tick, "slot": slot, "correction": distance, "speed": car.speed_mps}
			max_speed_change = maxf(max_speed_change, (car.velocity - Vector3(speeds[car.get_instance_id()])).length())
			max_tick_distance = maxf(max_tick_distance, car.position.distance_to(previous[car.get_instance_id()].origin))
			if distance > 0.1:
				corrections_over_10cm += 1
			if distance > 0.3:
				corrections_over_30cm += 1
			if car.speed_mps < 0.5 and distance > 0.01 and correction.dot(racer.last_correction) < -0.0001:
				slow_reversals += 1
			if car.speed_mps >= 0.5 and distance > 0.03 and correction.dot(racer.last_correction) < -0.0009:
				moving_reversals += 1
			racer.last_correction = correction
			track.advance_progress(racer.progress, previous[car.get_instance_id()].origin, car.position)
			if track.needs_recovery(car.position) or not racer.progress.interval_valid or racer.driver.needs_recovery():
				recoveries += 1
				car.reset_at(track.recovery_transform(racer.progress))
				track.mark_recovered(racer.progress)
				racer.driver.reset()
	for car: CharacterBody3D in bodies:
		car.queue_free()
	await physics_frame
	var a: CharacterBody3D = _car(Transform3D(Basis.IDENTITY, Vector3(-1000, 1, 0)))
	var b: CharacterBody3D = _car(Transform3D(Basis.IDENTITY, Vector3(-1000 + Vehicle.COLLISION_SIZE.x - 0.05, 1, 0)))
	await physics_frame
	Contacts.resolve([a, b], {})
	var resting_motion: float = 0.0
	for tick: int in 120:
		await physics_frame
		var pos_a: Vector3 = a.position
		var pos_b: Vector3 = b.position
		Contacts.resolve([a, b], {})
		resting_motion += a.position.distance_to(pos_a) + b.position.distance_to(pos_b)
	var passed: bool = recoveries == 0 and corrections_over_30cm == 0 and slow_reversals == 0 and resting_motion < 0.001
	print("BOT_CONTACT_MOTION_PROBE ", JSON.stringify({"passed": passed, "simulated_seconds": 12, "max_correction_m": max_correction,
		"max_contact_velocity_change_mps": max_speed_change, "max_tick_travel_m": max_tick_distance, "corrections_over_10cm": corrections_over_10cm,
		"corrections_over_30cm": corrections_over_30cm, "slow_correction_reversals": slow_reversals, "resting_total_motion_m": resting_motion,
		"moving_correction_reversals": moving_reversals,
		"recoveries": recoveries, "solver_pass_contacts": resolutions, "worst_correction": worst}))
	a.queue_free()
	b.queue_free()
	track.queue_free()
	await process_frame
	quit(0 if passed else 1)


func _car(pose: Transform3D) -> CharacterBody3D:
	var car := Vehicle.new()
	var collider := CollisionShape3D.new()
	collider.shape = Vehicle.create_collision_shape()
	car.add_child(collider)
	car.collision_layer = 2
	car.collision_mask = 1
	root.add_child(car)
	car.reset_at(pose)
	return car
