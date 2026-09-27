extends SceneTree

const Baker = preload("res://track/track_baker.gd")
const Progress = preload("res://track/route_progress.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result: Dictionary = Baker.bake(load("res://track/castle_waterfalls.tres"))
	_check(result.errors.is_empty(), "authored source bakes")
	if not result.errors.is_empty():
		print(result.errors)
		quit(1)
		return
	var data: Dictionary = result.data
	_check(Baker.package_errors(data).is_empty(), "branch is included in validated simulation identity")
	var branch: Dictionary = data.shortcuts[0]
	_check(float(branch.length) < float(branch.to_s) - float(branch.from_s) - 3.0, "shortcut saves more than three metres")
	_check(branch.width == 4.5, "narrow path fits 2.2 m kart but carries steering risk")
	_check(data.minimap.shortcuts.size() == 1, "branch is advertised in minimap descriptor")
	var state: Dictionary = Progress.initial_state()
	state.started = true
	state.confirmed_gate = 4
	state.expected_gate = 5
	var previous: Vector3 = Baker.vector(Baker.sample_at(data, branch.from_s).position) + Vector3.UP * 0.65
	var previous_s: float = float(branch.from_s) - 0.1
	for sample: Dictionary in branch.samples:
		var at: Vector3 = Baker.vector(sample.position) + Vector3.UP * 0.65
		_check(Progress.sweep_in_corridor(data, previous, at), "branch sweep remains in legal corridor")
		_check(not Progress.needs_recovery(data, at), "branch never triggers off-road recovery")
		Progress.advance(data, state, previous, at)
		var distance: float = Progress.standings_distance(data, state, at)
		_check(distance >= previous_s, "branch standings advance monotonically")
		previous_s = distance
		previous = at
	_check(state.expected_gate == 5 and state.lap == 0 and state.interval_valid, "branch cannot award or skip a checkpoint")
	var end: Vector3 = Baker.vector(Baker.sample_at(data, float(data.gates[5].s) + 1.0).position) + Vector3.UP * 0.65
	Progress.advance(data, state, previous, end)
	_check(state.confirmed_gate == 5 and state.expected_gate == 6, "main checkpoint after rejoin is required")
	state.confirmed_gate = 4
	state.expected_gate = 5
	_check(Progress.recovery_anchor(data, state).confirmed_gate == 4, "falling from branch recovers at prior checkpoint")
	var mid: Vector3 = Baker.vector(branch.samples[branch.samples.size() / 2].position)
	var forward: Vector3 = Baker.vector(branch.samples[0].tangent)
	_check(not Progress.in_corridor(data, mid + forward.cross(Vector3.UP).normalized() * 30.0), "unrelated off-road cut remains illegal")
	var tampered: Dictionary = data.duplicate(true)
	tampered.shortcuts[0].samples[2].position[0] += 1.0
	_check(not Baker.package_errors(tampered).is_empty(), "shortcut modification invalidates hash")
	await _physical_crossing(data, branch)
	await _bot_corner(data)
	print("SHORTCUT_PROBE %d/%d" % [checks - failures, checks])
	quit(1 if failures else 0)


func _physical_crossing(data: Dictionary, branch: Dictionary) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var road := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array()
	for vertex: Array in data.collision.road_faces:
		faces.append(Baker.vector(vertex))
	shape.set_faces(faces)
	collider.shape = shape
	road.add_child(collider)
	world.add_child(road)
	for barrier: Dictionary in data.collision.barriers:
		var wall := StaticBody3D.new()
		var box := BoxShape3D.new()
		box.size = Baker.vector(barrier.size)
		var collision := CollisionShape3D.new()
		collision.shape = box
		wall.add_child(collision)
		wall.transform = Transform3D(Basis.looking_at(Baker.vector(barrier.forward)), Baker.vector(barrier.position))
		world.add_child(wall)
	var vehicle := Vehicle.new()
	var kart_shape := CollisionShape3D.new()
	kart_shape.shape = Vehicle.create_collision_shape()
	vehicle.add_child(kart_shape)
	world.add_child(vehicle)
	var forward: Vector3 = Baker.vector(branch.samples[0].tangent).slide(Vector3.UP).normalized()
	var start: Vector3 = Baker.vector(branch.samples[0].position)
	vehicle.global_transform = Transform3D(Basis.looking_at(forward), start - forward * 3.0 + Vector3.UP * 0.65)
	var grounded_ticks: int = 0
	for tick: int in 300:
		await physics_frame
		vehicle.step({"throttle": 1.0}, 1.0 / 60.0)
		if vehicle.grounded:
			grounded_ticks += 1
		if (vehicle.position - start).dot(forward) >= float(branch.length) + 2.0:
			break
	_check((vehicle.position - start).dot(forward) >= float(branch.length) + 2.0, "real kart traverses both joins without barrier blocking")
	_check(grounded_ticks > 40 and vehicle.position.y > -2.0, "real kart remains on shortcut collision surface")
	world.queue_free()
	await process_frame


func _bot_corner(data: Dictionary) -> void:
	var track = load("res://track/authored_track.gd").new()
	track.data = data
	root.add_child(track)
	track.build(false)
	var styles = load("res://vehicle/driving_styles.gd")
	var driver_script = load("res://ai/racing_bot_driver.gd")
	var racers: Array = []
	var sample: Dictionary = Baker.sample_at(data, float(data.gates[3].s) + 3.0)
	for index: int in 4:
		var car := Vehicle.new()
		car.configure(styles.stats_for(styles.IDS[index]))
		car.collision_layer = 2
		car.collision_mask = 1
		var collider := CollisionShape3D.new()
		collider.shape = Vehicle.create_collision_shape()
		car.add_child(collider)
		root.add_child(car)
		car.reset_at(Transform3D(Basis.looking_at(Baker.vector(sample.tangent)), Baker.vector(sample.position) + Vector3.UP * 0.65))
		var state: Dictionary = Progress.initial_state()
		state.started = true
		state.confirmed_gate = 3
		state.expected_gate = 4
		racers.append({"car": car, "state": state, "driver": driver_script.new(track, index), "valid": true})
	for tick: int in 900:
		await physics_frame
		var complete: int = 0
		for racer: Dictionary in racers:
			if int(racer.state.confirmed_gate) >= 5:
				complete += 1
				continue
			var previous: Vector3 = racer.car.position
			racer.car.step(racer.driver.sample(racer.car, racer.state, 1.0 / 60.0), 1.0 / 60.0)
			Progress.advance(data, racer.state, previous, racer.car.position)
			racer.valid = racer.valid and racer.state.interval_valid and not track.needs_recovery(racer.car.position) and not racer.driver.needs_recovery()
		if complete == 4:
			break
	for racer: Dictionary in racers:
		_check(racer.valid and int(racer.state.confirmed_gate) >= 5, "bot driving style clears sharper main bend without recovery")
		racer.car.queue_free()
	track.queue_free()
	await process_frame


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
