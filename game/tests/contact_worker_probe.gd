extends SceneTree

const Track = preload("res://track/authored_track.gd")
const DT: float = 1.0 / 60.0

class TestWorker extends "res://app/prototype.gd":
	var step_requested: bool = false
	var progress_positions: Dictionary = {}

	func _ready() -> void:
		pass

	func _physics_process(_delta: float) -> void:
		if step_requested:
			step_requested = false
			_step_server(DT)

	func _update_progress(player: Dictionary) -> void:
		progress_positions[player["id"]] = player["vehicle"].global_position
		super._update_progress(player)

	func _broadcast_snapshot() -> void:
		pass

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var worker := TestWorker.new()
	root.add_child(worker)
	worker.set_process(false)
	var track := Track.new()
	worker.add_child(track)
	track.build(false)
	worker._track = track
	var rear: Dictionary = worker._new_player("rear", "Rear", 0, false)
	var front: Dictionary = worker._new_player("front", "Front", 1, false)
	worker._players = {"rear": rear, "front": front}
	var spawn: Transform3D = track.spawn_transform(0)
	var forward: Vector3 = -spawn.basis.z
	await physics_frame
	await process_frame
	for scenario: String in ["active", "spectator", "finished", "countdown", "results"]:
		worker._phase = scenario if scenario in ["countdown", "results"] else "racing"
		worker._countdown = 60 if scenario == "countdown" else 0
		worker._race_elapsed = 0.0
		worker._finish_remaining = -1.0
		worker.progress_positions.clear()
		for player: Dictionary in [rear, front]:
			player["finished"] = false
			player["spectator"] = false
			player["ready"] = false
			player["progress"] = track.initial_progress()
			player["last_input_at"] = Time.get_ticks_msec()
			player["vehicle"].reset_at(spawn)
			player["epoch"] = 0
		front["vehicle"].global_position += forward * 1.95
		rear["vehicle"].velocity = forward * 20.0
		front["finished"] = scenario == "finished"
		front["spectator"] = scenario == "spectator"
		await physics_frame
		await process_frame
		worker.step_requested = true
		await physics_frame
		await process_frame
		var rear_speed: float = rear["vehicle"].velocity.dot(forward)
		var front_speed: float = front["vehicle"].velocity.dot(forward)
		_check(not worker.step_requested, "%s ran actual server tick" % scenario)
		if scenario == "active":
			_check(rear_speed < 19.0 and front_speed > 1.0, "server rear contact slows striker and accelerates target (%s / %s)" % [rear_speed, front_speed])
			_check(is_equal_approx(rear_speed + front_speed, 20.0), "worker contact transfers equal-mass forward momentum")
			_check(rear["combat"]["health"] < 100.0 and front["combat"]["health"] < 100.0, "hard contact damages both equal-mass racers")
			for player: Dictionary in [rear, front]:
				_check(worker.progress_positions.get(player["id"]) == player["vehicle"].global_position, "%s progress sees final contact-corrected pose" % player["id"])
				_check(player["progress"]["interval_valid"] and player["epoch"] == 0, "%s contact leaves route progress valid without recovery" % player["id"])
		else:
			_check(is_equal_approx(rear_speed, 20.0) and is_zero_approx(front_speed), "%s does not apply pair impulse" % scenario)
			if scenario in ["countdown", "results"]:
				_check(worker.progress_positions.is_empty(), "%s does not advance checkpoints" % scenario)
			else:
				_check(not worker.progress_positions.has("front"), "%s vehicle excluded from active progress" % scenario)
	# With no contact partner, stale throttle must become the braking neutral command.
	worker._players.erase("front")
	worker._phase = "racing"
	worker._countdown = 0
	rear["vehicle"].reset_at(spawn)
	rear["vehicle"].grounded = true
	rear["vehicle"].velocity = forward * 20.0
	rear["input"] = {"steering": 0.0, "throttle": 1.0, "brake": 0.0, "drift": false}
	rear["last_input_at"] = Time.get_ticks_msec() - 1000
	await physics_frame
	await process_frame
	worker.step_requested = true
	await physics_frame
	await process_frame
	var stale_speed: float = rear["vehicle"].velocity.dot(forward)
	_check(stale_speed < 19.6 and stale_speed > 19.0, "stale throttle applies braking without another active car")
	_check(rear["input"]["throttle"] == 1.0, "timeout test retains stale throttle rather than changing the supplied fixture input")
	worker.free()
	print("CONTACT_WORKER_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
