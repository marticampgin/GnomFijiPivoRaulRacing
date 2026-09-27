extends SceneTree

const LocalSession = preload("res://race/local_race_session.gd")
const Track = preload("res://track/authored_track.gd")
const DT: float = 1.0 / 60.0

class TestSession extends "res://race/local_race_session.gd":
	var requested: int = 0
	var snapshots: Dictionary = {}

	func _physics_process(_delta: float) -> void:
		if requested > 0:
			requested -= 1
			step_local(DT, snapshots)

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _step(session: TestSession, snapshots: Dictionary, count: int = 1) -> void:
	session.snapshots = snapshots
	session.requested = count
	while session.requested > 0:
		await physics_frame
		await process_frame


func _run() -> void:
	for count: int in range(1, 5):
		var session := TestSession.new()
		root.add_child(session)
		var track := Track.new()
		session.add_child(track)
		track.build(false)
		session.configure(track)
		var seats: Array = []
		var raw: Dictionary = {-1: {"connected": true, "keys": {}}}
		for seat: int in count:
			seats.append({"device": seat - 1, "style_id": LocalSession.Styles.IDS[seat]})
			if seat > 0:
				raw[seat - 1] = {"connected": true, "axes": {}, "buttons": {}}
		_check(session.start_local(seats, [0, 1, 2]), "%d seats start without transport" % count)
		_check(session._players.size() == 10 and session._human_count() == count, "bots fill ten places")
		_check(not session.start_local([{"device": -1}, {"device": -1}], []), "duplicate device fails transactionally")
		_check(session._human_count() == count, "failed configuration preserves existing session")
		await _step(session, raw)
		_check(session._tick == 1, "all seats advance exactly one tick")
		session._phase = "racing"
		session._countdown = 0
		var first: Dictionary = session._players["local:0"]
		first.combat.slots = ["fanta", "mermaid_rum"]
		first.combat.health = 40.0
		raw[-1].keys = {KEY_Q: true}
		await _step(session, raw)
		_check(first.combat.slots == ["mermaid_rum", ""] and first.combat.health == 40.0, "item press consumes only queue head")
		await _step(session, raw, 3)
		_check(first.combat.slots == ["mermaid_rum", ""] and first.combat.health == 40.0, "held item button never consumes reserve")
		raw[-1].keys = {}
		await _step(session, raw)
		raw[-1].keys = {KEY_Q: true}
		await _step(session, raw)
		_check(first.combat.slots == ["", ""] and first.combat.health > 40.0, "next fresh item press consumes advanced reserve")
		first.combat.slots = ["fanta", "ice_rum"]
		var item_sequence: int = first.item_accepted
		_check(session.use_item_seat(0) and session.use_item_seat(0), "distinct UI presses can queue before the next physics tick")
		await _step(session, raw)
		_check(first.combat.slots == ["", ""] and first.combat.item_ack == item_sequence + 2, "queued local presses execute once each without held-key duplication")
		var frozen_tick: int = session._tick
		var frozen_time: float = session._race_elapsed
		var frozen_combat: Dictionary = first.combat.duplicate(true)
		_prime_drift(first.vehicle)
		session.pause_local()
		_check(_drift_canceled(first.vehicle), "manual pause cancels stored drift without awarding turbo")
		await _step(session, raw, 3)
		_check(session._tick == frozen_tick and session._race_elapsed == frozen_time and first.combat == frozen_combat, "pause freezes all authority and effects")
		_check(not session.recover_seat(0), "recovery cannot move a paused vehicle")
		_check(session.resume_local(), "manual pause resumes")
		_prime_drift(first.vehicle)
		session.set_focused(false)
		_check(_drift_canceled(first.vehicle), "focus loss immediately cancels stored drift without turbo")
		_check(not session.resume_local(), "unfocused session cannot resume")
		session.set_focused(true)
		_check(session.presentation().paused, "focus return requires explicit resume")
		session.resume_local()
		raw[-1].keys = {}
		await _step(session, raw)
		if count > 1:
			_prime_drift(first.vehicle)
			raw[0].connected = false
			frozen_tick = session._tick
			await _step(session, raw, 2)
			_check(session._tick == frozen_tick and session.presentation().pause_reason == "device", "disconnect pauses before physics")
			_check(_drift_canceled(first.vehicle), "another seat disconnect cancels all drift state without turbo")
			_check(not session.resume_local() and session._human_count() == count, "disconnect keeps player and blocks resume")
			_check(session.assign_device(1, 3, [3]), "replacement pad can claim disconnected seat")
			raw[3] = {"connected": true, "axes": {}, "buttons": {}}
			_check(session.resume_local(), "assigned replacement allows explicit resume")
		var before_epoch: int = first.epoch
		_check(session.recover_seat(0) and first.epoch == before_epoch + 1, "manual recovery increments epoch")
		_check(not session.recover_seat(0), "manual recovery rate limited")
		first.finished = true
		first.combat.slots = ["fanta", ""]
		raw[-1].keys = {KEY_Q: true}
		await _step(session, raw)
		_check(first.combat.slots[0] == "fanta", "finished seat cannot consume inventory")
		_check(session.presentation().seats.size() == count and session.presentation().players.size() == 10, "presentation retains finished seat and standings")
		session._phase = "results"
		var race_id: int = session._race_id
		for seat: int in count - 1:
			session.ready_seat(seat)
		await _step(session, raw)
		_check(session._race_id == race_id, "repeat waits for every human")
		_check(session.ready_seat(count - 1), "last seat can become ready")
		await _step(session, raw)
		_check(session._race_id == race_id + 1 and session._phase == "countdown", "all ready resets once")
		await _step(session, raw)
		_check(session._race_id == race_id + 1 and first.combat.slots == ["", ""] and not first.finished, "repeat clears inventory and finish state without duplication")
		session.free()
		await process_frame
	print("LOCAL_RACE_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _prime_drift(vehicle: CharacterBody3D) -> void:
	vehicle.is_drifting = true
	vehicle.drift_owner = -1
	vehicle.drift_chain = 2
	vehicle.drift_charge = 0.8
	vehicle.boost_remaining = 0.0


func _drift_canceled(vehicle: CharacterBody3D) -> bool:
	return not vehicle.is_drifting and vehicle.drift_owner == 0 and vehicle.drift_chain == 0 and vehicle.drift_charge == 0.0 and vehicle.boost_remaining == 0.0


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
