extends SceneTree

class Visual extends Node3D:
	func update_visual(_delta: float, _speed: float, _steering: float, _drifting: bool, _boost: float) -> void:
		pass

class Client extends "res://app/prototype.gd":
	var clock: int = 1000

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

	func _presentation_time_msec() -> int:
		return clock

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for scenario: String in ["constant", "ack_jitter", "arrival_jitter", "contact", "turn", "cohort"]:
		var client := Client.new()
		root.add_child(client)
		client._local = client._create_vehicle(0, false)
		var visual := Visual.new()
		client.add_child(visual)
		var samples: Array = []
		client._remotes = {"other": {"node": visual, "samples": samples}}
		var previous: float = 0.0
		var previous_displacement: float = 0.0
		var max_error: float = 0.0
		var max_step_change: float = 0.0
		var minimum_step: float = 10.0
		var max_lag: float = 0.0
		var previous_yaw: float = 0.0
		var max_yaw_step_error: float = 0.0
		var max_yaw_lag: float = 0.0
		var minimum_clearance: float = 10.0
		for frame: int in 120:
			var t: float = frame / 60.0
			client.clock = 1000 + roundi(t * 1000.0)
			var position: float = 20.0 * t if scenario != "contact" or frame < 60 else 20.0 + 5.0 * (t - 1.0)
			client._local.global_position = Vector3(position, 10.0, 4.0)
			if scenario == "cohort":
				client._local.global_position = Vector3(position - 2.22, 10.0, 0.0)
			if frame % 3 == 0:
				var velocity: float = 5.0 if scenario == "contact" and frame >= 60 else 20.0
				var sample_position: float = position
				if scenario == "arrival_jitter":
					sample_position -= 20.0 * (0.015 if frame % 6 == 0 else 0.0)
				samples.append({"at": client.clock, "tick": frame, "transform": Transform3D(Basis(Vector3.UP, t if scenario == "turn" else 0.0), Vector3(sample_position, 10.0, 0.0)), "velocity": Vector3(velocity, 0.0, 0.0), "speed": velocity, "steering": 0.0, "drifting": false, "boost": 0.0})
			client._pending.clear()
			var count: int = (1 if frame % 6 < 3 else 4) + frame % 3 if scenario == "ack_jitter" else 0
			for sequence: int in count:
				client._pending.append({"sequence": sequence})
			client._interpolate_remotes(1.0 / 60.0)
			var rendered: float = visual.global_position.x
			if scenario == "cohort":
				minimum_clearance = minf(minimum_clearance, rendered - client._local.global_position.x - 2.18)
			var displacement: float = rendered - previous
			var yaw: float = visual.global_basis.get_euler().y
			if frame > 6:
				var expected: float = (5.0 if scenario == "contact" and frame > 60 else 20.0) / 60.0
				max_error = maxf(max_error, absf(displacement - expected))
				max_step_change = maxf(max_step_change, absf(displacement - previous_displacement))
				minimum_step = minf(minimum_step, displacement)
				max_lag = maxf(max_lag, position - rendered)
				if scenario == "turn":
					max_yaw_step_error = maxf(max_yaw_step_error, absf(yaw - previous_yaw - 1.0 / 60.0))
					max_yaw_lag = maxf(max_yaw_lag, t - yaw)
			previous = rendered
			previous_displacement = displacement
			previous_yaw = yaw
		print("CONTACT_MOTION %s max_step_error=%.3f max_step_change=%.3f min_step=%.3f max_lag=%.3f" % [scenario, max_error, max_step_change, minimum_step, max_lag])
		_check(minimum_step >= -0.01, "%s does not jerk backwards" % scenario)
		_check(max_error < (0.27 if scenario == "contact" else 0.16), "%s avoids snapshot-sized displacement jumps" % scenario)
		_check(max_lag < 0.7, "%s does not restore deliberate 100 ms presentation lag" % scenario)
		if scenario == "turn":
			print("CONTACT_MOTION turn max_yaw_step_error=%.4f max_yaw_lag=%.4f" % [max_yaw_step_error, max_yaw_lag])
			_check(max_yaw_step_error < 0.01 and max_yaw_lag < 0.04, "turn orientation advances between snapshots without delayed steering")
		if scenario == "cohort":
			_check(minimum_clearance >= 0.0, "side-by-side moving cohort retains visible kart envelope separation")
		client.free()
	print("CONTACT_MOTION_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
