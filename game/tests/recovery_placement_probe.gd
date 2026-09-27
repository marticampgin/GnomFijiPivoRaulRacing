extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Protocol = preload("res://net/prototype_protocol.gd")
const DT: float = 1.0 / 60.0

class TestSession extends "res://race/local_race_session.gd":
	var requested: int = 0
	func _physics_process(_delta: float) -> void:
		if requested > 0:
			requested -= 1
			_step_session(DT)

class Settler extends Node:
	var bodies: Array = []
	var remaining: int = 0
	func _physics_process(_delta: float) -> void:
		if remaining <= 0:
			return
		remaining -= 1
		for body: CharacterBody3D in bodies:
			body.step(Protocol.BLOCKED, DT)

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session := TestSession.new()
	root.add_child(session)
	var track := Track.new()
	session.add_child(track)
	track.build(false)
	session.configure(track)
	session.start_local([{"device": -1}], [])
	var players: Array = session._players.values()
	var settler := Settler.new()
	root.add_child(settler)
	await physics_frame
	await process_frame
	_park(players)
	var first: Dictionary = players[0]
	var second: Dictionary = players[1]
	first.progress = _progress(track, 0)
	second.progress = _progress(track, 0)
	session._recover(first)
	var occupied: Transform3D = first.vehicle.global_transform
	var before: Dictionary = second.progress.duplicate(true)
	session._recover(second)
	_check(_separated(first.vehicle, second.vehicle), "same-checkpoint recovery does not overlap the occupant immediately")
	_check(first.vehicle.global_transform == occupied, "recovery does not move the existing occupant")
	_check(_same_progress(second.progress, before), "occupied-anchor recovery preserves checkpoint and lap")
	for active: bool in [false, true]:
		track.apply_event({"phase": "active" if active else "idle", "remaining": 0.0,
			"active": [active, active], "trigger_tick": 1 if active else 0})
		await physics_frame
		await process_frame
		for gate: int in range(-1, track.data.gates.size()):
			_park(players)
			first.progress = _progress(track, gate)
			before = first.progress.duplicate(true)
			var epoch: int = first.epoch
			session._recover(first)
			var label: String = "gate %d event %s" % [gate, active]
			_check(first.epoch == epoch + 1, label + " finds a recovery position")
			_check(_same_progress(first.progress, before), label + " retains route progress")
			await physics_frame
			await process_frame
			_check(_clear_environment(first.vehicle), label + " shape starts clear of world collision")
			await _settle(settler, [first.vehicle])
			_check(first.vehicle.grounded, label + " settles onto supported road")
			_check(not track.needs_recovery(first.vehicle.global_position), label + " remains on recoverable road")
			var events: Array = track.advance_progress(first.progress, first.previous_position, first.vehicle.global_position)
			_check(events.is_empty() and _same_progress(first.progress, before), label + " teleport and settling award no progress")
	for gate: int in [-1, 0, 9]:
		_park(players)
		for player: Dictionary in players:
			player.progress = _progress(track, gate)
			var epoch: int = player.epoch
			session._recover(player)
			_check(player.epoch == epoch + 1, "ten-player recovery gate %d allocates slot %d" % [gate, player.slot])
		for index: int in players.size():
			for other: int in range(index + 1, players.size()):
				_check(_separated(players[index].vehicle, players[other].vehicle),
					"ten-player recovery gate %d separates %d and %d immediately" % [gate, index, other])
		await physics_frame
		await process_frame
		for player: Dictionary in players:
			_check(_clear_environment(player.vehicle), "ten-player recovery gate %d slot %d clears active obstacles" % [gate, player.slot])
		await _settle(settler, players.map(func(player: Dictionary) -> CharacterBody3D: return player.vehicle))
		for player: Dictionary in players:
			_check(player.vehicle.grounded and not track.needs_recovery(player.vehicle.global_position),
				"ten-player recovery gate %d slot %d has road support" % [gate, player.slot])
	_park(players)
	first.progress = _progress(track, 9)
	first.queue = [{"sequence": 12}]
	first.item_queue = [{"sequence": 13, "slot": 0}]
	first.driving.start_boost_remaining = 0.75
	var blocker: StaticBody3D = _block_route()
	await physics_frame
	await process_frame
	var blocked_before: Dictionary = _recovery_state(first)
	var recovered: Variant = session._recover(first)
	_check(recovered == false, "fully obstructed interval declines recovery")
	_check(_recovery_state(first) == blocked_before, "failed recovery leaves pose, progress, input, effects and epoch unchanged")
	blocker.free()
	await physics_frame
	await process_frame
	session._recover(first)
	_check(first.epoch == blocked_before.epoch + 1 and _clear_environment(first.vehicle), "recovery succeeds after obstruction is removed")
	for player: Dictionary in players:
		if player.id != first.id:
			player.vehicle.free()
			session._players.erase(player.id)
	_park([first])
	first.progress = _progress(track, 9)
	first.combat.health = 0.0
	first.combat.destroyed_remaining = DT
	first.combat.invulnerable_remaining = 0.0
	session._phase = "racing"
	session._countdown = 0
	blocker = _block_route()
	await physics_frame
	await process_frame
	var destroyed_epoch: int = first.epoch
	var destroyed_pose: Transform3D = first.vehicle.global_transform
	await _session_step(session)
	_check(first.combat.health == 0.0 and first.combat.destroyed_remaining > 0.0,
		"blocked destruction recovery remains destroyed until placement is safe")
	_check(first.epoch == destroyed_epoch and first.vehicle.global_transform == destroyed_pose and first.vehicle.velocity == Vector3.ZERO,
		"blocked destruction recovery neither teleports nor moves")
	blocker.free()
	await physics_frame
	await process_frame
	await _session_step(session)
	_check(first.combat.health == 100.0 and first.combat.destroyed_remaining == 0.0,
		"next authority step restores health after obstruction is removed")
	_check(first.epoch == destroyed_epoch + 1 and first.combat.invulnerable_remaining > 0.0,
		"successful destruction retry increments epoch once and grants protection")
	_check(not track.needs_recovery(first.vehicle.global_position) and first.progress.interval_valid,
		"successful destruction retry returns to valid road progress")
	settler.free()
	session.free()
	print("RECOVERY_PLACEMENT_PROBE %d/%d" % [checks - failures, checks])
	quit(1 if failures else 0)


func _progress(track: Node3D, gate: int) -> Dictionary:
	var state: Dictionary = track.initial_progress()
	state.started = gate >= 0
	state.confirmed_gate = gate
	state.expected_gate = (gate + 1) % track.data.gates.size()
	state.lap = 1 if gate >= 0 else 0
	state.interval_valid = false
	return state


func _same_progress(after: Dictionary, before: Dictionary) -> bool:
	for key: String in ["started", "confirmed_gate", "expected_gate", "lap", "finished"]:
		if after[key] != before[key]:
			return false
	return true


func _recovery_state(player: Dictionary) -> Dictionary:
	return {"transform": player.vehicle.global_transform, "velocity": player.vehicle.velocity,
		"epoch": player.epoch, "previous_position": player.previous_position,
		"progress": player.progress.duplicate(true), "input": player.input.duplicate(true),
		"queue": player.queue.duplicate(true), "item_queue": player.item_queue.duplicate(true),
		"combat": player.combat.duplicate(true), "driving": player.driving.duplicate(true), "ack": player.ack}


func _block_route() -> StaticBody3D:
	var blocker := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 500.0
	collider.shape = shape
	blocker.add_child(collider)
	root.add_child(blocker)
	return blocker


func _session_step(session: TestSession) -> void:
	session.requested = 1
	while session.requested > 0:
		await physics_frame
		await process_frame


func _park(players: Array) -> void:
	for player: Dictionary in players:
		player.vehicle.reset_at(Transform3D(Basis.IDENTITY, Vector3(1000.0 + float(player.slot) * 10.0, 100.0, 1000.0)))


func _separated(a: CharacterBody3D, b: CharacterBody3D) -> bool:
	return a.global_position.distance_to(b.global_position) >= Vehicle.COLLISION_SIZE.length() - 0.001


func _clear_environment(body: CharacterBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = Vehicle.create_collision_shape()
	query.transform = body.global_transform
	query.collision_mask = 1
	query.margin = 0.0
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _settle(settler: Settler, bodies: Array) -> void:
	settler.bodies = bodies
	settler.remaining = 40
	while settler.remaining > 0:
		await physics_frame
		await process_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
