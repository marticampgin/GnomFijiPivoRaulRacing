extends SceneTree

const Session = preload("res://race/race_session.gd")
const Track = preload("res://track/authored_track.gd")
const DT: float = 1.0 / 60.0

class TestSession extends "res://race/race_session.gd":
	var requested: int = 0

	func _physics_process(_delta: float) -> void:
		if requested > 0:
			requested -= 1
			_step_session(DT)

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _step(session: TestSession, count: int = 1) -> void:
	session.requested = count
	while session.requested > 0:
		await physics_frame
		await process_frame


func _run() -> void:
	for human_count: int in range(1, 5):
		var session := TestSession.new()
		root.add_child(session)
		session._track = Track.new()
		session.add_child(session._track)
		session._track.build(false)
		for seat: int in human_count:
			var id: String = "local:%d" % seat
			session._players[id] = session._new_player(id, "Player %d" % (seat + 1), seat, false, Session.Styles.IDS[seat])
			session._players[id]["last_input_at"] = -100000
			_check(not session._players[id].has("peer_id"), "local participant needs no network peer")
		session._start_race()
		_check(session._human_count() == human_count and session._players.size() == 10, "%d humans share a ten-racer session" % human_count)
		var world: World3D = session.get_world_3d()
		for player: Dictionary in session._players.values():
			_check(player.vehicle.get_world_3d() == world, "each vehicle uses the session physics world")
		await _step(session)
		_check(session._tick == 1 and session._countdown == 299, "one call advances one simulation tick, independent of seat count")
		session._phase = "racing"
		session._countdown = 0
		var first: Dictionary = session._players["local:0"]
		first.vehicle.grounded = true
		first.input = {"steering": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
		first.combat.slots = ["fanta", "mermaid_rum"]
		first.combat.health = 40.0
		for slot: int in 2:
			first.item_queue.append({"sequence": slot + 1, "slot": slot, "epoch": first.epoch})
		await _step(session)
		_check(first.combat.slots == ["", ""] and first.combat.item_ack == 2, "both independent item slots execute without transport")
		_check(first.combat.effects.has("fanta") and first.combat.effects.has("mermaid_rum") and first.combat.health > 40.0, "shared session applies boost and repair")
		for seat: int in range(1, human_count):
			var other: Dictionary = session._players["local:%d" % seat]
			_check(other.combat.health == 100.0 and other.combat.effects.is_empty(), "one seat's items do not apply to another")
		await _step(session, 20)
		_check(first.vehicle.speed_mps > 1.0 and first.last_input_at == -100000, "direct input remains active beyond network timeout without timestamps")
		_check(session._tick == 22 and is_equal_approx(session._race_elapsed, 21.0 * DT), "multiple seats do not multiply race time")
		for seat: int in range(1, human_count):
			var other: Dictionary = session._players["local:%d" % seat]
			_check(other.input.throttle == 0.0, "direct commands remain isolated by participant")
		session.free()
		await process_frame
	print("RACE_SESSION_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
