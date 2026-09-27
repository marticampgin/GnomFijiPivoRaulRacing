extends SceneTree

const Event = preload("res://race/track_event.gd")
const Track = preload("res://track/authored_track.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var track = Track.new()
	root.add_child(track)
	var event = Event.new()
	var body := CharacterBody3D.new()
	root.add_child(body)
	body.position = Vector3(0, 100, 0)
	var racer: Dictionary = {"progress": {"lap": 0}, "lap": 3, "vehicle": body, "is_bot": false, "spectator": false, "finished": false}
	var players: Dictionary = {"human": racer}
	_check(Event.validate_snapshot(event.snapshot()), "idle snapshot valid")
	event.step(players, track, 1.0, 8)
	_check(event.snapshot().phase == "idle", "raw display lap cannot trigger")
	racer.progress.lap = 1
	event.step(players, track, 1.0, 9)
	_check(event.snapshot().phase == "idle", "second lap remains idle")
	racer.progress.lap = 2
	racer.spectator = true
	event.step(players, track, 1.0, 10)
	_check(event.snapshot().phase == "idle", "spectator cannot trigger")
	racer.spectator = false
	racer.finished = true
	event.step(players, track, 1.0, 11)
	_check(event.snapshot().phase == "idle", "finished participant cannot trigger")
	racer.finished = false
	event.step(players, track, 1.0, 12)
	_check(event.snapshot() == {"phase": "warning", "remaining": 3.0, "active": [false, false], "trigger_tick": 12}, "leader begins full global warning")
	_check(Event.validate_snapshot(event.snapshot()), "warning snapshot valid")
	var copy: Dictionary = event.snapshot()
	copy.active[0] = true
	_check(not event.snapshot().active[0], "snapshot owns activation copy")
	for bad_delta: float in [0.0, -1.0, NAN, INF]:
		event.step(players, track, bad_delta, 13)
		_check(event.snapshot().remaining == 3.0, "invalid delta cannot advance warning")
	event.step(players, track, 2.9, 14)
	_check(event.snapshot().phase == "warning" and not event.snapshot().active.has(true), "warning is non-solid")
	var obstacles: Array = Event.definitions(track)
	_check(obstacles.size() == 2 and obstacles[0].size == Vector3(3, 1.8, 2), "two narrow stable obstacles")
	_check(obstacles[0].s == 430.0 and obstacles[1].s == 470.0, "both outside shortcut section")
	body.global_position = obstacles[0].transform.origin
	event.step(players, track, 0.11, 15)
	_check(event.snapshot().phase == "active" and event.snapshot().active == [false, true], "occupied obstacle deferred independently")
	_check(Event.validate_snapshot(event.snapshot()), "partially active snapshot valid")
	var basis: Basis = obstacles[0].transform.basis
	body.global_position = obstacles[0].transform.origin + basis.z * 12.0
	body.velocity = -basis.z * 30.0
	event.step(players, track, 0.02, 16)
	_check(not event.snapshot().active[0], "imminent swept crossing defers activation")
	body.velocity = basis.z * 30.0
	event.step(players, track, 0.02, 17)
	_check(event.snapshot().active == [true, true], "departing clear vehicle permits activation")
	body.global_position = obstacles[0].transform.origin
	event.step(players, track, 0.02, 18)
	_check(event.snapshot().active == [true, true] and event.snapshot().trigger_tick == 12, "active obstacle never toggles and trigger stays stable")
	event.reset()
	_check(event.snapshot() == {"phase": "idle", "remaining": 0.0, "active": [false, false], "trigger_tick": 0}, "new race clears entire event")
	racer.is_bot = true
	event.step(players, track, 0.02, 19)
	_check(event.snapshot().phase == "warning", "bot leader obeys same trigger")
	body.global_position = Vector3(0, 100, 0)
	body.velocity = Vector3(NAN, 0, 0)
	event.step(players, track, 3.0, 20)
	_check(event.snapshot().active == [false, false], "invalid vehicle motion fails closed")
	for bad: Variant in [null, [], {}, {"phase": "idle"}, {"phase": "idle", "remaining": 0, "active": [false, false]}]:
		_check(not Event.validate_snapshot(bad), "malformed snapshot rejected")
	var valid: Dictionary = {"phase": "active", "remaining": 0.0, "active": [true, false], "trigger_tick": 123.0}
	_check(Event.validate_snapshot(valid), "JSON float integer tick accepted")
	for pair: Array in [["remaining", NAN], ["remaining", INF], ["remaining", true], ["remaining", -1], ["remaining", 1],
		["phase", "other"], ["active", [true]], ["active", [1, false]], ["trigger_tick", -1], ["trigger_tick", 0.5], ["trigger_tick", NAN], ["trigger_tick", true], ["trigger_tick", 2147483648.0]]:
		var bad: Dictionary = valid.duplicate(true)
		bad[pair[0]] = pair[1]
		_check(not Event.validate_snapshot(bad), "invalid snapshot field rejected")
	for bad: Dictionary in [{"phase": "warning", "remaining": 0, "active": [false, false], "trigger_tick": 1},
		{"phase": "warning", "remaining": 3.1, "active": [false, false], "trigger_tick": 1},
		{"phase": "warning", "remaining": 1, "active": [true, false], "trigger_tick": 1},
		{"phase": "idle", "remaining": 0, "active": [false, false], "trigger_tick": 1},
		{"phase": "idle", "remaining": 0, "active": [true, false], "trigger_tick": 0}]:
		_check(not Event.validate_snapshot(bad), "inconsistent phase rejected")
	body.free()
	track.free()
	print("TRACK_EVENT_PROBE %d/%d" % [checks - failures, checks])
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
