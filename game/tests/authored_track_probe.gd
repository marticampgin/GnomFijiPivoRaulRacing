extends SceneTree

const Definition = preload("res://track/track_definition.gd")
const Baker = preload("res://track/track_baker.gd")
const Progress = preload("res://track/route_progress.gd")
const Track = preload("res://track/authored_track.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition: Resource = load("res://track/castle_waterfalls.tres")
	var first: Dictionary = Baker.bake(definition)
	_check(first.errors.is_empty(), "valid closed route bakes")
	if not first.errors.is_empty():
		print(first.errors)
		quit(1)
		return
	var data: Dictionary = first.data
	var again: Dictionary = Baker.bake(definition)
	_check(JSON.stringify(data, "", true, true) == JSON.stringify(again.data, "", true, true), "bake is byte deterministic")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Track.PACKAGE_PATH))
	_check(data.simulation_hash == saved.simulation_hash, "committed package matches editable source")
	_check(Baker.package_errors(saved).is_empty(), "saved package passes integrity validation")
	var compact_text: String = FileAccess.get_file_as_string("res://../shared/track-manifest.json")
	_check(compact_text == JSON.stringify(Baker.compact(data), "", true, true) + "\n", "backend manifest matches simulation bake")
	var edited: Resource = definition.duplicate(true)
	edited.art_revision += 1
	var art: Dictionary = Baker.bake(edited)
	_check(art.data.simulation_hash == data.simulation_hash and art.data.art_revision != data.art_revision, "scenery revision does not change simulation hash")
	edited.road_width += 0.5
	_check(Baker.bake(edited).data.simulation_hash != data.simulation_hash, "collision width changes simulation hash")
	edited = definition.duplicate(true)
	edited.shoulder_tolerance += 0.1
	_check(Baker.bake(edited).data.simulation_hash != data.simulation_hash, "corridor policy changes simulation hash")
	edited = definition.duplicate(true)
	edited.route.set_point_position(2, edited.route.get_point_position(2) + Vector3.UP)
	_check(Baker.bake(edited).data.simulation_hash != data.simulation_hash, "physical route change changes simulation hash")
	edited = definition.duplicate(true)
	edited.road_width = NAN
	_check(not Baker.bake(edited).errors.is_empty(), "non-finite width rejected")
	edited = definition.duplicate(true)
	edited.route.set_point_position(2, Vector3(INF, 0, 0))
	_check(not Baker.bake(edited).errors.is_empty(), "non-finite route rejected")
	edited = definition.duplicate(true)
	edited.route.set_point_position(2, edited.route.get_point_position(1))
	_check(not Baker.bake(edited).errors.is_empty(), "zero control segment rejected")
	edited = definition.duplicate(true)
	edited.route.set_point_position(edited.route.point_count - 1, Vector3(1, 2, 3))
	_check(not Baker.bake(edited).errors.is_empty(), "open curve rejected")
	edited = definition.duplicate(true)
	edited.surface_id = "unknown"
	_check(not Baker.bake(edited).errors.is_empty(), "unknown gameplay surface rejected")
	for spacing: float in [0.5, 1.0, 3.0]:
		edited = definition.duplicate(true)
		edited.sample_spacing = spacing
		_check(Baker.bake(edited).errors.is_empty(), "valid route topology at %.1f m sample spacing" % spacing)
	var corrupted: Dictionary = saved.duplicate(true)
	corrupted.samples[2].position[1] += 1.0
	_check(not Baker.package_errors(corrupted).is_empty(), "modified runtime collision source fails integrity hash")
	corrupted = saved.duplicate(true)
	corrupted.gates[1].id = 0
	_check(not Baker.package_errors(corrupted).is_empty(), "duplicate runtime gate id rejected")
	corrupted = saved.duplicate(true)
	corrupted.recovery[2].position = [NAN, 0, 0]
	_check(not Baker.package_errors(corrupted).is_empty(), "non-finite recovery anchor rejected")
	_check(not Baker.package_errors({}).is_empty(), "empty simulation package rejected")
	_check(data.starts.size() == 10 and data.recovery.size() == data.gates.size() + 1, "ten starts and checkpoint-linked recovery anchors")
	var monotonic: bool = true
	var guide_valid: bool = true
	for index: int in data.samples.size() - 1:
		monotonic = monotonic and float(data.samples[index + 1].s) > float(data.samples[index].s)
		guide_valid = guide_valid and Progress.in_corridor(data, Baker.vector(data.guides[index].position))
	_check(monotonic, "sample arc length strictly increases")
	_check(guide_valid and data.guides.size() == data.samples.size() - 1, "continuous future AI guide remains on road")
	_check(data.minimap.polyline.size() == data.samples.size() and data.minimap.polyline[0] == data.minimap.polyline[-1], "minimap is same closed sampled route")
	for anchor: Dictionary in data.camera_anchors:
		_check(Progress.in_corridor(data, Baker.vector(anchor.position)), "camera section %s is on driveable route" % anchor.id)
	for anchor: Dictionary in data.recovery:
		_check(Progress.in_corridor(data, Baker.vector(anchor.position)), "safe recovery anchor %s" % anchor.confirmed_gate)
	_test_progress(data)
	await _test_collision(data)
	print("AUTHORED_TRACK_PROBE ", JSON.stringify({"checks": checks, "failures": failures, "length": data.length, "simulation_hash": data.simulation_hash}))
	quit(0 if failures == 0 else 1)


func _test_progress(data: Dictionary) -> void:
	var state: Dictionary = Progress.initial_state()
	var before: Vector3 = _at(data, float(data.length) - 2.0)
	var after: Vector3 = _at(data, 2.0)
	_check(Progress.standings_distance(data, state, before) < 0.0, "pre-start standings do not award lap")
	Progress.advance(data, state, before, after)
	_check(state.started and state.lap == 0 and state.expected_gate == 1, "first start crossing arms lap without awarding it")
	Progress.advance(data, state, after, before)
	Progress.advance(data, state, before, after)
	_check(state.lap == 0 and state.expected_gate == 1, "repeat and wrong-way finish do not advance")
	var lap_events: int = 0
	var finish_events: int = 0
	for lap: int in 3:
		var previous: Vector3 = after
		for index: int in range(2, data.samples.size()):
			var current: Vector3 = Baker.vector(data.samples[index].position) + Vector3.UP * 0.4
			for event: Dictionary in Progress.advance(data, state, previous, current):
				lap_events += int(event.type == "lap")
				finish_events += int(event.type == "finish")
			previous = current
		for event: Dictionary in Progress.advance(data, state, previous, after):
			lap_events += int(event.type == "lap")
			finish_events += int(event.type == "finish")
	_check(state.lap == 3 and state.finished and lap_events == 3 and finish_events == 1, "three full ordered laps finish exactly once")
	_check(Progress.advance(data, state, before, after).is_empty(), "finished racer emits no duplicate result")
	state = Progress.initial_state()
	Progress.advance(data, state, before, after)
	var gate: Dictionary = data.gates[1]
	var center: Vector3 = Baker.vector(gate.position) + Vector3.UP * 0.4
	var forward: Vector3 = Baker.vector(gate.forward)
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	_check(Progress.crossing_fraction(gate, center + forward, center - forward) < 0.0, "backward gate direction rejected")
	_check(Progress.crossing_fraction(gate, center - forward - Vector3.UP * 8.0, center + forward - Vector3.UP * 8.0) < 0.0, "under-bridge crossing rejected by height")
	_check(Progress.crossing_fraction(gate, center - forward + right * 20, center + forward + right * 20) < 0.0, "gate crossing outside width rejected")
	Progress.advance(data, state, after, after + Vector3(0, 0, -30))
	Progress.advance(data, state, center - forward, center + forward)
	_check(not state.interval_valid and state.expected_gate == 1, "off-road shortcut permanently poisons interval despite valid next gate")
	var original_lap: int = int(state.lap)
	var original_gate: int = int(state.expected_gate)
	Progress.recover(state)
	Progress.advance(data, state, before, center + forward)
	_check(state.interval_valid and state.lap == original_lap and state.expected_gate == original_gate, "recovery clears violation but teleport cannot cross gates")
	Progress.advance(data, state, center - forward, center + forward)
	_check(state.expected_gate == 2, "recovered interval can subsequently pass its expected gate")
	var limited: float = Progress.standings_distance(data, state, _at(data, float(data.length) * 0.8))
	_check(limited <= float(data.gates[2].s) + 0.001, "projection cannot jump beyond confirmed interval")
	_check(state.expected_gate == 2, "projection never confirms a checkpoint")
	_check(Progress.needs_recovery(data, center - Vector3.UP * 5), "fall is detected relative to elevated route")
	_check(not Progress.needs_recovery(data, center), "supported surface does not recover")
	state = Progress.initial_state()
	Progress.advance(data, state, before, after, true)
	_check(not state.started, "explicit discontinuity does not start lap")
	var short: Dictionary = data.duplicate(true)
	for index: int in 3:
		var sample: Dictionary = Baker.sample_at(data, float(index) * 8.0)
		short.gates[index].position = sample.position
		short.gates[index].forward = sample.tangent
		short.gates[index].s = sample.s
	state = Progress.initial_state()
	var events: Array = Progress.advance(short, state, before, _at(data, 20.0))
	_check(events.size() == 3 and state.expected_gate == 3, "one swept tick confirms multiple directed gates in order")
	state = Progress.initial_state()
	Progress.advance(data, state, Vector3(NAN, 0, 0), after)
	_check(not state.interval_valid and not state.started, "non-finite position never advances")


func _test_collision(data: Dictionary) -> void:
	var server := Track.new()
	root.add_child(server)
	server.build(false)
	_check(server.find_children("*", "MeshInstance3D", true, false).is_empty(), "headless route has no visual nodes")
	_check(server.find_children("*", "MultiMeshInstance3D", true, false).is_empty(), "headless route has no instanced scenery")
	var count: int = server.get_child_count()
	server.build(false)
	_check(server.get_child_count() == count, "collision build is idempotent")
	var client := Track.new()
	root.add_child(client)
	client.build(true)
	var server_shapes: Array[Node] = server.find_children("*", "CollisionShape3D", true, false)
	var client_shapes: Array[Node] = []
	for shape_node: Node in client.find_children("*", "CollisionShape3D", true, false):
		var body: CollisionObject3D = shape_node.get_parent()
		if body.collision_layer & 1:
			client_shapes.append(shape_node)
		else:
			_check(body.collision_layer == 4 and body.collision_mask == 0,
				"extra client geometry is exclusively camera-only")
	var parity: bool = server_shapes.size() == client_shapes.size()
	for index: int in mini(server_shapes.size(), client_shapes.size()):
		parity = parity and server_shapes[index].get_parent().collision_layer == client_shapes[index].get_parent().collision_layer
		parity = parity and server_shapes[index].get_parent().collision_mask == client_shapes[index].get_parent().collision_mask
		parity = parity and server_shapes[index].global_transform.is_equal_approx(client_shapes[index].global_transform)
		if server_shapes[index].shape is BoxShape3D:
			parity = parity and server_shapes[index].shape.size.is_equal_approx(client_shapes[index].shape.size)
		else:
			parity = parity and server_shapes[index].shape.get_faces() == client_shapes[index].shape.get_faces()
	_check(parity, "client and server collision faces and transforms match exactly")
	client.queue_free()
	await process_frame
	var vehicles: Array[CharacterBody3D] = []
	for slot: int in 10:
		var vehicle: CharacterBody3D = Vehicle.new()
		var collider := CollisionShape3D.new()
		collider.shape = Vehicle.create_collision_shape()
		vehicle.add_child(collider)
		root.add_child(vehicle)
		vehicle.reset_at(server.spawn_transform(slot))
		vehicles.append(vehicle)
	for tick: int in 40:
		await physics_frame
		for vehicle: CharacterBody3D in vehicles:
			vehicle.step({}, 1.0 / 60.0)
	for slot: int in 10:
		_check(vehicles[slot].grounded, "spawn %d settles on road" % slot)
		_check(Progress.in_corridor(data, vehicles[slot].position), "spawn %d remains in safe corridor" % slot)
		vehicles[slot].queue_free()
	await process_frame
	server.queue_free()
	await process_frame


func _at(data: Dictionary, s: float) -> Vector3:
	return Baker.vector(Baker.sample_at(data, s).position) + Vector3.UP * 0.4


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)
