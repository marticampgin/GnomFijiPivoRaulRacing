extends SceneTree

const Track = preload("res://track/authored_track.gd")
const DT: float = 1.0 / 60.0

class TestSession extends "res://race/race_session.gd":
	var requested: int = 0
	var recoveries: Array = []
	var contact_seen: bool = false
	func _physics_process(_delta: float) -> void:
		if requested > 0:
			requested -= 1
			_step_session(DT)
			for player: Dictionary in _players.values():
				contact_seen = contact_seen or player.vehicle.is_on_wall()
	func _recover(player: Dictionary) -> bool:
		recoveries.append({"health": player.combat.health, "interval_valid": player.progress.interval_valid,
			"needs_recovery": _track.needs_recovery(player.vehicle.global_position),
			"position": str(player.vehicle.global_position)})
		return super._recover(player)

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
	session._track = track
	var player: Dictionary = session._new_player("human", "Human", 0, false)
	session._players[player.id] = player
	await physics_frame
	await process_frame
	for distance: float in [0.0, 40.0, 112.0, 190.0, 302.0, 420.0, 620.0, 730.0]:
		var sample: Dictionary = track.sample_at(distance)
		var forward: Vector3 = Track.Baker.vector(sample.tangent).slide(Vector3.UP).normalized()
		var right: Vector3 = forward.cross(Vector3.UP)
		for side: float in [-1.0, 1.0]:
			for angle: float in [0.0, 45.0, 75.0]:
				var heading: Vector3 = (right * side * cos(deg_to_rad(angle)) + forward * sin(deg_to_rad(angle))).normalized()
				var position: Vector3 = Track.Baker.vector(sample.position) + right * side * 5.5 + Vector3.UP * 0.7
				_reset(session, player, position, heading)
				await _ticks(session, 30)
				player.vehicle.velocity = heading * 44.0
				await _ticks(session, 90)
				var label: String = "s=%.0f side=%.0f angle=%.0f" % [distance, side, angle]
				_check(session.contact_seen, "wall contact " + label)
				_check(player.epoch == 0 and session.recoveries.is_empty(), "no wall recovery " + label + " " + JSON.stringify(session.recoveries))
	var start: Dictionary = track.sample_at(40.0)
	var start_forward: Vector3 = Track.Baker.vector(start.tangent).slide(Vector3.UP).normalized()
	var start_right: Vector3 = start_forward.cross(Vector3.UP)
	_reset(session, player, Track.Baker.vector(start.position) + start_right * 5.5 + Vector3.UP * 0.7, start_right)
	await _ticks(session, 30)
	player.combat.health = 1.0
	player.combat.shards = 10
	player.vehicle.velocity = start_right * 44.0
	await _ticks(session, 180)
	_check(session.contact_seen, "low-health wall contact is exercised")
	_check(player.epoch == 0 and player.combat.health > 0.0, "wall impact cannot destroy low-health racer " + JSON.stringify(session.recoveries))
	_check(player.combat.shards < 10, "strong wall impact still removes crystals")
	player.vehicle.reset_at(Transform3D(Basis.looking_at(start_right), Track.Baker.vector(start.position) + start_right * 5.5 + Vector3.UP * 0.7))
	player.vehicle.velocity = start_right * 44.0
	await _ticks(session, 180)
	_check(player.epoch == 0 and player.combat.health > 0.0, "repeated wall impact cannot destroy low-health racer")
	player.combat.health = 0.5
	session._items.apply_damage(player, 30.0, {}, "contact")
	_check(player.combat.health == 0.5, "contact neither kills nor heals fractional remaining health")
	player.combat.health = 1.0
	session._items.apply_damage(player, 100.0, {}, "weapon")
	await _ticks(session, 180)
	_check(player.epoch > 0, "lethal weapon still causes recovery")
	_reset(session, player, Track.Baker.vector(start.position) + Vector3.DOWN * 12.0, start_forward)
	await _ticks(session, 2)
	_check(player.epoch > 0, "actual fall still causes recovery")
	print("WALL_RECOVERY_PROBE %d/%d" % [checks - failures, checks])
	session.free()
	quit(1 if failures else 0)


func _reset(session: TestSession, player: Dictionary, position: Vector3, heading: Vector3) -> void:
	session._phase = "racing"
	session._race_elapsed = 0.0
	session._finish_remaining = -1.0
	session.recoveries.clear()
	session.contact_seen = false
	player.epoch = 0
	player.last_recover_at = -1000
	player.progress = session._track.initial_progress()
	player.previous_position = position
	player.vehicle.reset_at(Transform3D(Basis.looking_at(heading), position))
	session._items.init_player(player)


func _ticks(session: TestSession, count: int) -> void:
	session.requested = count
	while session.requested > 0:
		await physics_frame
		await process_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
