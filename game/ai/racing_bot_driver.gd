class_name RacingBotDriver
extends RefCounted

const Baker = preload("res://track/track_baker.gd")
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]
const PROFILES: Dictionary = {
	"easy": {"cruise": 0.83, "corner": 0.65, "reaction": 0.16, "aim": 0.07, "item_ticks": 240},
	"normal": {"cruise": 1.0, "corner": 0.8, "reaction": 0.0, "aim": 0.0, "item_ticks": 120},
	"hard": {"cruise": 1.10, "corner": 0.85, "reaction": 0.0, "aim": 0.0, "item_ticks": 45},
}

var _track: Node3D
var _lane: float
var _cruise_speed: float
var _stalled_seconds: float = 0.0
var difficulty: String = "normal"
var _reaction_remaining: float = 0.0
var _held_command: Dictionary = {}
var _driving_time: float = 0.0
var _slot: int


func _init(track: Node3D, slot: int, level: String = "normal") -> void:
	_track = track
	_slot = slot
	difficulty = level if level in DIFFICULTIES else "normal"
	_lane = float(slot % 3 - 1) * 1.1
	_cruise_speed = 22.0 + float(slot % 5) * 0.5


func reset() -> void:
	_stalled_seconds = 0.0
	_reaction_remaining = 0.0
	_held_command.clear()
	_driving_time = 0.0


func needs_recovery() -> bool:
	return _stalled_seconds >= 4.0


func sample_countdown(seconds_left: float) -> Dictionary:
	# Timing is a pedal decision; the shared countdown judge still grants or rejects it.
	var press_at: float = 0.85 - float(_slot % 3) * 0.15 if difficulty == "easy" else (0.7 - float(_slot % 4) * 0.12 if difficulty == "normal" else 0.45 - float(_slot % 3) * 0.05)
	return {"steering": 0.0, "throttle": 1.0 if seconds_left <= press_at else 0.0, "brake": 0.0, "drift": false}


func sample(vehicle: CharacterBody3D, progress: Dictionary, delta: float) -> Dictionary:
	if bool(progress.get("finished", false)):
		return {"steering": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false, "drive_blocked": true}
	var speed: float = vehicle.speed_mps
	var profile: Dictionary = PROFILES[difficulty]
	_driving_time += maxf(0.0, delta)
	_reaction_remaining -= maxf(0.0, delta)
	if _reaction_remaining > 0.0 and not _held_command.is_empty():
		if speed < 1.0:
			_held_command.brake = 0.0
		return _held_command.duplicate()
	_reaction_remaining = float(profile.reaction)
	_stalled_seconds = _stalled_seconds + maxf(delta, 0.0) if speed < 1.0 else 0.0
	# Confirmed checkpoints constrain projection, so bridges cannot select another road below.
	var distance: float = _track.standings_distance(progress, vehicle.global_position)
	var look_ahead: float = 8.0 + minf(speed, 30.0) * 0.26
	var target: Vector3 = _point(distance + look_ahead)
	var direction: Vector3 = (target - vehicle.global_position).slide(Vector3.UP)
	var forward: Vector3 = (-vehicle.global_basis.z).slide(Vector3.UP).normalized()
	var error: float = -forward.signed_angle_to(direction.normalized(), Vector3.UP)
	error += sin(_driving_time * 0.8 + float(_slot)) * float(profile.aim)
	var first: Vector3 = (_point(distance + 16.0) - _point(distance + 6.0)).slide(Vector3.UP).normalized()
	var second: Vector3 = (_point(distance + 26.0) - _point(distance + 16.0)).slide(Vector3.UP).normalized()
	var curvature: float = absf(first.signed_angle_to(second, Vector3.UP)) / 10.0
	var turn_rate: float = 1.32 * float(vehicle.stats.handling)
	# These are pedal/line decisions, never a modification of the vehicle's stats.
	var target_speed: float = clampf(turn_rate * float(profile.corner) / maxf(0.001, curvature), 11.0 if difficulty == "easy" else 13.0, _cruise_speed * float(profile.cruise))
	if absf(error) > 0.55:
		target_speed = minf(target_speed, 14.0)
	var steering: float = clampf(2.0 * maxf(speed, 5.0) * sin(error) / maxf(2.0, direction.length()) / turn_rate, -1.0, 1.0)
	_held_command = {"steering": steering, "throttle": 1.0 if speed < target_speed - 0.3 else 0.0,
		"brake": 1.0 if speed > target_speed + 1.5 else 0.0, "drift": false}
	return _held_command.duplicate()


func item_slots(player: Dictionary, players: Dictionary, tick: int) -> Array[int]:
	var result: Array[int] = []
	if (tick + int(player.slot) * 13) % int(PROFILES[difficulty].item_ticks) != 0:
		return result
	if player.get("finished", false) or float(player.combat.health) <= 0.0:
		return result
	for slot: int in 2:
		var item: String = player.combat.slots[slot]
		if item.is_empty():
			continue
		var health: float = float(player.combat.health)
		if item in ["mermaid_rum", "ice_rum"]:
			var threshold: float = 85.0
			if difficulty == "hard":
				threshold = 50.0 if item == "mermaid_rum" else 85.0
			if health > threshold:
				continue
		if difficulty == "hard":
			if player.combat.effects.has(item):
				continue
			if item in ["stroh80", "bfg10k", "seeker"] and not _target_ahead(player, players, 25.0 if item == "stroh80" else 50.0):
				continue
			if item == "fanta" and absf(float(_held_command.get("steering", 0.0))) > 0.4:
				continue
		result.append(slot)
	return result


func _target_ahead(player: Dictionary, players: Dictionary, reach: float) -> bool:
	var forward: Vector3 = -player.vehicle.global_basis.z
	for other: Dictionary in players.values():
		if other.id == player.id or other.get("finished", false) or other.get("spectator", false) or float(other.combat.health) <= 0.0:
			continue
		var offset: Vector3 = other.vehicle.global_position - player.vehicle.global_position
		if offset.length() <= reach and offset.length() > 0.1 and forward.dot(offset.normalized()) >= 0.97:
			return true
	return false


func _point(distance: float) -> Vector3:
	var sample_point: Dictionary = _track.sample_at(distance)
	var tangent: Vector3 = Baker.vector(sample_point.tangent)
	var lane: float = _track.event_lane(distance, _lane) if _track.has_method("event_lane") else _lane
	return Baker.vector(sample_point.position) + tangent.cross(Vector3.UP).normalized() * lane
