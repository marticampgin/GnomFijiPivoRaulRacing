extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Driver = preload("res://ai/racing_bot_driver.gd")


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
	var racers: Array = []
	for slot: int in 10:
		var car := Vehicle.new()
		var collider := CollisionShape3D.new()
		collider.shape = Vehicle.create_collision_shape()
		car.add_child(collider)
		car.collision_layer = 2
		car.collision_mask = 1
		root.add_child(car)
		car.reset_at(track.spawn_transform(slot))
		racers.append({"car": car, "driver": Driver.new(track, slot), "progress": track.initial_progress(), "recoveries": 0, "finish_tick": 0, "finish_events": 0})
	var completed: int = 0
	var valid_commands: bool = true
	for tick: int in 15000:
		await physics_frame
		for racer: Dictionary in racers:
			if racer.progress.finished:
				continue
			var car: CharacterBody3D = racer.car
			var command: Dictionary = racer.driver.sample(car, racer.progress, 1.0 / 60.0)
			valid_commands = valid_commands and _valid(command)
			var previous: Vector3 = car.position
			car.step(command, 1.0 / 60.0)
			var events: Array = track.advance_progress(racer.progress, previous, car.position)
			for event: Dictionary in events:
				if event.type == "finish":
					racer.finish_events += 1
			if track.needs_recovery(car.position) or not racer.progress.interval_valid or racer.driver.needs_recovery():
				racer.recoveries += 1
				car.reset_at(track.recovery_transform(racer.progress))
				track.mark_recovered(racer.progress)
				racer.driver.reset()
			if racer.progress.finished:
				racer.finish_tick = tick + 1
				completed += 1
		if completed == 10:
			break
	var report: Array = []
	var passed: bool = completed == 10 and valid_commands
	for slot: int in racers.size():
		var racer: Dictionary = racers[slot]
		passed = passed and racer.recoveries == 0 and racer.finish_events == 1 and racer.progress.lap == 3
		var stopped: Dictionary = racer.driver.sample(racer.car, racer.progress, 1.0 / 60.0)
		passed = passed and stopped.throttle == 0.0 and stopped.brake == 1.0
		report.append({"slot": slot, "seconds": racer.finish_tick / 60.0, "laps": racer.progress.lap,
			"recoveries": racer.recoveries, "finish_events": racer.finish_events})
		# A restart must not retain a stalled driver's recovery request.
		racer.car.reset_at(track.spawn_transform(slot))
		for unused: int in 241:
			racer.driver.sample(racer.car, track.initial_progress(), 1.0 / 60.0)
		passed = passed and racer.driver.needs_recovery()
		racer.driver.reset()
		passed = passed and not racer.driver.needs_recovery()
		racer.car.queue_free()
	print("BOT_RACE_PROBE ", JSON.stringify({"passed": passed, "completed": completed, "valid_commands": valid_commands,
		"racers": report, "note": "Ten unchanged vehicle bodies on real road collision, three complete checkpoint-validated laps; not a server capacity benchmark."}))
	track.queue_free()
	await process_frame
	quit(0 if passed else 1)


func _valid(command: Dictionary) -> bool:
	for key: String in ["steering", "throttle", "brake"]:
		var value: float = command[key]
		if not is_finite(value) or value > 1.0 or value < (-1.0 if key == "steering" else 0.0):
			return false
	return command.drift is bool
