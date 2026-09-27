class_name RacingBotDriver
extends RefCounted

const Baker = preload("res://track/track_baker.gd")

var _track: Node3D
var _lane: float
var _cruise_speed: float
var _stalled_seconds: float = 0.0


func _init(track: Node3D, slot: int) -> void:
	_track = track
	_lane = float(slot % 3 - 1) * 1.1
	_cruise_speed = 22.0 + float(slot % 5) * 0.5


func reset() -> void:
	_stalled_seconds = 0.0


func needs_recovery() -> bool:
	return _stalled_seconds >= 4.0


func sample(vehicle: CharacterBody3D, progress: Dictionary, delta: float) -> Dictionary:
	if bool(progress.get("finished", false)):
		return {"steering": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false}
	var speed: float = vehicle.speed_mps
	_stalled_seconds = _stalled_seconds + maxf(delta, 0.0) if speed < 1.0 else 0.0
	# Confirmed checkpoints constrain projection, so bridges cannot select another road below.
	var distance: float = _track.standings_distance(progress, vehicle.global_position)
	var look_ahead: float = 8.0 + minf(speed, 30.0) * 0.26
	var target: Vector3 = _point(distance + look_ahead)
	var direction: Vector3 = (target - vehicle.global_position).slide(Vector3.UP)
	var forward: Vector3 = (-vehicle.global_basis.z).slide(Vector3.UP).normalized()
	var error: float = -forward.signed_angle_to(direction.normalized(), Vector3.UP)
	var first: Vector3 = (_point(distance + 16.0) - _point(distance + 6.0)).slide(Vector3.UP).normalized()
	var second: Vector3 = (_point(distance + 26.0) - _point(distance + 16.0)).slide(Vector3.UP).normalized()
	var curvature: float = absf(first.signed_angle_to(second, Vector3.UP)) / 10.0
	var turn_rate: float = 1.32 * float(vehicle.stats.handling)
	var target_speed: float = clampf(turn_rate * 0.8 / maxf(0.001, curvature), 13.0, _cruise_speed)
	if absf(error) > 0.55:
		target_speed = minf(target_speed, 14.0)
	var steering: float = clampf(2.0 * maxf(speed, 5.0) * sin(error) / maxf(2.0, direction.length()) / turn_rate, -1.0, 1.0)
	return {"steering": steering, "throttle": 1.0 if speed < target_speed - 0.3 else 0.0,
		"brake": 1.0 if speed > target_speed + 1.5 else 0.0, "drift": false}


func _point(distance: float) -> Vector3:
	var sample_point: Dictionary = _track.sample_at(distance)
	var tangent: Vector3 = Baker.vector(sample_point.tangent)
	return Baker.vector(sample_point.position) + tangent.cross(Vector3.UP).normalized() * _lane
