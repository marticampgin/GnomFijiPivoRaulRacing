extends SceneTree

const VISUAL_WIDTH: float = 2.18
const VISUAL_LENGTH: float = 2.696

class TestVisual extends Node3D:
	func update_visual(_delta: float, _speed: float, _steering: float, _drifting: bool, _boost: float) -> void:
		pass

class TestClient extends "res://app/prototype.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var client := TestClient.new()
	root.add_child(client)
	client._local = client._create_vehicle(0, false)
	client._local.global_position = Vector3(0.0, 10.0, 0.0)
	# Current authoritative poses are outside the complete visible kart envelope.
	# Only presentation delay changes between the stationary/moving fixtures.
	for scenario: String in ["stationary", "rear", "side"]:
		var current := Transform3D(Basis.IDENTITY, Vector3(0.0, 10.0, -(VISUAL_LENGTH + 0.04)))
		var velocity := Vector3.ZERO
		if scenario == "rear":
			velocity = Vector3(0.0, 0.0, -20.0)
		elif scenario == "side":
			current.origin = Vector3(VISUAL_WIDTH + 0.04, 10.0, 0.0)
			velocity = Vector3(20.0, 0.0, 0.0)
		var old: Transform3D = current
		old.origin -= velocity * 0.1
		var visual := TestVisual.new()
		client.add_child(visual)
		visual.global_transform = current
		var now: int = Time.get_ticks_msec()
		client._remotes = {"other": {"node": visual, "samples": [
			_sample(now - 100, old, velocity), _sample(now, current, velocity),
		]}}
		client._interpolate_remotes(1.0 / 60.0)
		var relative: Vector3 = visual.global_position - client._local.global_position
		var overlap_x: float = maxf(0.0, VISUAL_WIDTH - absf(relative.x))
		var overlap_z: float = maxf(0.0, VISUAL_LENGTH - absf(relative.z))
		print("CONTACT_PRESENTATION %s overlap_width=%.3f overlap_length=%.3f" % [scenario, overlap_x, overlap_z])
		_check(overlap_x <= 0.02 or overlap_z <= 0.02, "%s: remote interpolation must not visibly penetrate the predicted local kart" % scenario)
		visual.free()
	for scenario: String in ["far", "bounded", "pending"]:
		var visual := TestVisual.new()
		client.add_child(visual)
		var current := Transform3D(Basis.IDENTITY, Vector3(32.0 if scenario == "far" else 5.0, 10.0, 0.0))
		var old: Transform3D = current
		old.origin.x -= 2.0
		var now: int = Time.get_ticks_msec()
		var age_ms: int = 1000 if scenario == "bounded" else 0
		client._pending.clear()
		if scenario == "pending":
			for index: int in 6:
				client._pending.append({"sequence": index + 1})
		client._remotes = {"other": {"node": visual, "samples": [
			_sample(now - age_ms - 100, old, Vector3(20.0, 0.0, 0.0)),
			_sample(now - age_ms, current, Vector3(20.0, 0.0, 0.0)),
		]}}
		var local_pose: Transform3D = client._local.global_transform
		var local_velocity: Vector3 = client._local.velocity
		client._interpolate_remotes(1.0 / 60.0)
		var expected_x: float = 30.0 if scenario == "far" else 7.0
		_check(absf(visual.global_position.x - expected_x) < 0.04, "%s respects far interpolation or capped predicted timeline" % scenario)
		_check(client._local.global_transform == local_pose and client._local.velocity == local_velocity, "%s presentation does not mutate local physics" % scenario)
		visual.free()
	client._remotes.clear()
	client.free()
	print("CONTACT_PRESENTATION_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _sample(at: int, pose: Transform3D, velocity: Vector3) -> Dictionary:
	return {"at": at, "transform": pose, "velocity": velocity, "speed": velocity.length(), "steering": 0.0, "drifting": false, "boost": 0.0}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
