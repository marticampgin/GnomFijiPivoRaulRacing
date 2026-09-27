extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Baker = preload("res://track/track_baker.gd")
const Progress = preload("res://track/route_progress.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var track := Track.new()
	if not track.load_errors.is_empty():
		push_error(str(track.load_errors))
		track.free()
		quit(1)
		return
	root.add_child(track)
	track.build(false)
	var car := Vehicle.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.25, 0.7, 2.1)
	collider.shape = shape
	car.add_child(collider)
	root.add_child(car)
	car.reset_at(track.spawn_transform(0))
	car.configure({"top_speed": 26.0})
	var state: Dictionary = track.initial_progress()
	var recovery_count: int = 0
	var air_ticks: int = 0
	var longest_air: int = 0
	var minimum_height: float = INF
	var maximum_height: float = -INF
	var ticks: int = 0
	for tick: int in 6000:
		await physics_frame
		var current: Vector3 = car.position
		var progress: float = track.standings_distance(state, current)
		var target: Dictionary = track.sample_at(progress + 9.0)
		var direction: Vector3 = (Baker.vector(target.position) - current).slide(Vector3.UP).normalized()
		var forward: Vector3 = -car.global_basis.z
		var turn: float = forward.signed_angle_to(direction, Vector3.UP)
		var steering: float = clampf(-turn * 3.0, -1.0, 1.0)
		car.step({"throttle": 1.0, "steering": steering}, 1.0 / 60.0)
		track.advance_progress(state, current, car.position)
		minimum_height = minf(minimum_height, car.position.y)
		maximum_height = maxf(maximum_height, car.position.y)
		if not car.grounded:
			air_ticks += 1
			longest_air = maxi(longest_air, air_ticks)
		else:
			air_ticks = 0
		if track.needs_recovery(car.position) or not state.interval_valid:
			recovery_count += 1
			print("DRIVE_RECOVERY ", JSON.stringify({"tick": tick, "position": Baker.vec(car.position), "speed": car.speed_mps, "state": state}))
			car.reset_at(track.recovery_transform(state))
			track.mark_recovered(state)
		ticks = tick + 1
		if int(state.lap) >= 1:
			break
	var passed: bool = int(state.lap) == 1 and recovery_count == 0 and maximum_height - minimum_height >= 12.0 and longest_air < 24
	if not passed:
		print("DRIVE_CONTACT ", JSON.stringify({"grounded": car.grounded, "velocity": Baker.vec(car.velocity), "floor_normal": Baker.vec(car.get_floor_normal()), "wall": car.is_on_wall(), "up": Baker.vec(car.up_direction)}))
		for index: int in car.get_slide_collision_count():
			var contact: KinematicCollision3D = car.get_slide_collision(index)
			print("DRIVE_NORMAL ", JSON.stringify({"normal": Baker.vec(contact.get_normal()), "point": Baker.vec(contact.get_position()), "collider": str(contact.get_collider())}))
	print("AUTHORED_DRIVE_PROBE ", JSON.stringify({"passed": passed, "ticks": ticks, "seconds": ticks / 60.0, "lap": state.lap, "recoveries": recovery_count, "longest_air_ticks": longest_air, "min_height": minimum_height, "max_height": maximum_height, "final_position": Baker.vec(car.position), "final_speed": car.speed_mps, "state": state, "note": "Deterministic steering test fixture, not a gameplay bot or performance benchmark."}))
	car.queue_free()
	track.queue_free()
	await process_frame
	quit(0 if passed else 1)
