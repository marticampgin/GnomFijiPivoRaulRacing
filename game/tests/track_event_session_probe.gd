extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Event = preload("res://race/track_event.gd")
const Bot = preload("res://ai/racing_bot_driver.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Styles = preload("res://vehicle/driving_styles.gd")
const Baker = preload("res://track/track_baker.gd")
const DT: float = 1.0 / 60.0
var checks: int = 0
var failures: int = 0

class TestSession extends "res://race/local_race_session.gd":
	var steps: int = 0
	func _physics_process(_delta: float) -> void:
		if steps > 0:
			steps -= 1
			step_local(DT, {-1: {"connected": true, "keys": {}}})

class Drivers extends Node:
	var track: Node3D
	var drivers: Array = []
	var steps: int = 0
	func _physics_process(_delta: float) -> void:
		if steps <= 0:
			return
		steps -= 1
		for entry: Dictionary in drivers:
			if entry.done:
				continue
			var previous: Vector3 = entry.body.global_position
			entry.body.step(entry.driver.sample(entry.body, entry.progress, DT), DT)
			track.advance_progress(entry.progress, previous, entry.body.global_position)
			entry.done = track.standings_distance(entry.progress, entry.body.global_position) > 510.0
			for index: int in entry.body.get_slide_collision_count():
				if entry.body.get_slide_collision(index).get_collider() in track._event_bodies:
					entry.hit = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session := TestSession.new()
	root.add_child(session)
	var track = Track.new()
	session.add_child(track)
	track.build(false)
	session.configure(track)
	session.start_local([{"device": -1}], [])
	session._phase = "racing"
	session._countdown = 0
	session._players["bot:1"].progress.lap = 2
	await _step(session, 1)
	_check(session.presentation().track_event.phase == "warning", "bot leader starts shared session warning")
	_check(session.presentation().track_event.trigger_tick == session._tick, "event stamps simulation tick")
	var before: Dictionary = session._track_event.snapshot()
	session.pause_local()
	await _step(session, 5)
	_check(session._track_event.snapshot() == before, "local pause freezes warning")
	session.resume_local()
	await _step(session, 181)
	_check(session.presentation().track_event.active == [true, true], "clear world activates both after warning")
	_check(session.presentation().track_event.trigger_tick == before.trigger_tick, "multiple leaders do not restart event")
	session._start_race()
	_check(session.presentation().track_event.phase == "idle" and track._event_bodies[0].collision_layer == 0, "repeat resets authority and collision")
	for player: Dictionary in session._players.values():
		player.vehicle.free()
	session._players.clear()
	session.steps = 0
	var defs: Array = Event.definitions(track)
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = 1
	ray.from = defs[0].transform.origin + defs[0].transform.basis.z * 4.0
	ray.to = defs[0].transform.origin - defs[0].transform.basis.z * 4.0
	var contact_body := CharacterBody3D.new()
	contact_body.collision_layer = 2
	contact_body.collision_mask = 1
	var contact_shape := CollisionShape3D.new()
	contact_shape.shape = Vehicle.create_collision_shape()
	contact_body.add_child(contact_shape)
	root.add_child(contact_body)
	contact_body.global_transform = Transform3D(defs[0].transform.basis, ray.from)
	var motion := PhysicsTestMotionParameters3D.new()
	motion.from = contact_body.global_transform
	motion.motion = ray.to - ray.from
	track.apply_event({"phase": "warning", "remaining": 2.0, "active": [false, false], "trigger_tick": 1})
	await physics_frame
	_check(track.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "warning obstacle is physically passable")
	_check(not PhysicsServer3D.body_test_motion(contact_body.get_rid(), motion), "kart collision shape passes through warning")
	track.apply_event({"phase": "active", "remaining": 0.0, "active": [true, true], "trigger_tick": 1})
	await physics_frame
	var collision: Dictionary = track.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not collision.is_empty() and collision.collider == track._event_bodies[0], "active obstacle is solid world collision")
	var contact := PhysicsTestMotionResult3D.new()
	_check(PhysicsServer3D.body_test_motion(contact_body.get_rid(), motion, contact) and contact.get_collider() == track._event_bodies[0], "kart collision shape hits active obstacle")
	contact_body.free()
	var runners := Drivers.new()
	runners.track = track
	root.add_child(runners)
	for level: String in Bot.DIFFICULTIES:
		for style: String in Styles.IDS:
			var body = Vehicle.new()
			body.collision_layer = 2
			body.collision_mask = 1
			var shape := CollisionShape3D.new()
			shape.shape = Vehicle.create_collision_shape()
			body.add_child(shape)
			runners.add_child(body)
			body.configure(Styles.stats_for(style))
			var sample: Dictionary = track.sample_at(395.0)
			body.reset_at(Transform3D(Basis.looking_at(Baker.vector(sample.tangent), Vector3.UP), Baker.vector(sample.position) + Vector3.UP * 0.65))
			var progress: Dictionary = track.initial_progress()
			progress.started = true
			for gate: Dictionary in track.data.gates:
				if float(gate.s) <= 395.0:
					progress.confirmed_gate = int(gate.id)
					progress.expected_gate = (int(gate.id) + 1) % track.data.gates.size()
			runners.drivers.append({"body": body, "driver": Bot.new(track, runners.drivers.size() % 10, level), "progress": progress, "done": false, "hit": false, "name": level + ":" + style})
	runners.steps = 720
	while runners.steps > 0:
		await physics_frame
		await process_frame
	for entry: Dictionary in runners.drivers:
		_check(entry.done, "bot clears changed stretch " + entry.name)
		_check(entry.progress.interval_valid, "bot stays inside route " + entry.name)
		_check(not entry.hit, "bot avoids new obstacle " + entry.name)
	runners.free()
	session.free()
	print("TRACK_EVENT_SESSION_PROBE %d/%d" % [checks - failures, checks])
	quit(1 if failures else 0)


func _step(session: TestSession, count: int) -> void:
	session.steps = count
	while session.steps > 0:
		await physics_frame
		await process_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
