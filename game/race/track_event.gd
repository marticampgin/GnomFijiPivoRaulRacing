extends RefCounted

const Baker = preload("res://track/track_baker.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const WARNING_SECONDS: float = 3.0
const APPROACH_SECONDS: float = 0.75
const OBSTACLE_COUNT: int = 2
const DISTANCES: Array[float] = [430.0, 470.0]
const LATERALS: Array[float] = [-2.8, 2.8]
const OBSTACLE_SIZE: Vector3 = Vector3(3.0, 1.8, 2.0)

var _phase: String = "idle"
var _remaining: float = 0.0
var _active: Array[bool] = [false, false]
var _trigger_tick: int = 0


func reset() -> void:
	_phase = "idle"
	_remaining = 0.0
	_active = [false, false]
	_trigger_tick = 0


func snapshot() -> Dictionary:
	return {"phase": _phase, "remaining": _remaining, "active": _active.duplicate(), "trigger_tick": _trigger_tick}


func step(players: Dictionary, track: Node3D, delta: float, tick: int = 0) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if _phase == "idle":
		for player: Dictionary in players.values():
			if not player.get("spectator", false) and not player.get("finished", false) and int(player.get("progress", {}).get("lap", 0)) >= 2:
				_phase = "warning"
				_remaining = WARNING_SECONDS
				_trigger_tick = maxi(0, tick)
				break
		return
	if _phase == "warning":
		_remaining = maxf(0.0, _remaining - delta)
		if _remaining > 0.0:
			return
		_phase = "active"
	var obstacles: Array = definitions(track)
	for index: int in OBSTACLE_COUNT:
		if not _active[index] and _clear(obstacles[index], players):
			_active[index] = true


static func definitions(track: Node3D) -> Array:
	var result: Array = []
	for index: int in OBSTACLE_COUNT:
		var sample: Dictionary = track.sample_at(DISTANCES[index])
		var forward: Vector3 = Baker.vector(sample.tangent).normalized()
		var basis: Basis = Basis.looking_at(forward, Vector3.UP)
		var origin: Vector3 = Baker.vector(sample.position) + basis.x * LATERALS[index] + basis.y * OBSTACLE_SIZE.y * 0.5
		result.append({"transform": Transform3D(basis, origin), "size": OBSTACLE_SIZE,
			"s": DISTANCES[index], "lateral": LATERALS[index]})
	return result


static func validate_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 4 or not value.has_all(["phase", "remaining", "active", "trigger_tick"]):
		return false
	if value.phase not in ["idle", "warning", "active"] or not value.active is Array or value.active.size() != OBSTACLE_COUNT:
		return false
	if not (value.remaining is float or value.remaining is int) or not is_finite(float(value.remaining)):
		return false
	if not (value.trigger_tick is float or value.trigger_tick is int) or not is_finite(float(value.trigger_tick)) or float(value.trigger_tick) < 0.0 or float(value.trigger_tick) > 2147483647.0 or floorf(float(value.trigger_tick)) != float(value.trigger_tick):
		return false
	for enabled: Variant in value.active:
		if not enabled is bool:
			return false
	if value.phase == "warning":
		return float(value.remaining) > 0.0 and float(value.remaining) <= WARNING_SECONDS and not value.active.has(true)
	if float(value.remaining) != 0.0:
		return false
	return value.phase == "active" or (not value.active.has(true) and value.trigger_tick == 0)


static func _clear(obstacle: Dictionary, players: Dictionary) -> bool:
	var inverse: Transform3D = obstacle.transform.affine_inverse()
	# An orientation-independent kart sphere makes the sweep conservative even while turning.
	var radius: float = Vehicle.COLLISION_SIZE.length() * 0.5 + 0.3
	var half: Vector3 = obstacle.size * 0.5 + Vector3.ONE * radius
	for player: Dictionary in players.values():
		var vehicle: CharacterBody3D = player.get("vehicle")
		if not is_instance_valid(vehicle):
			continue
		var position: Vector3 = vehicle.global_position
		var velocity: Vector3 = vehicle.velocity
		if not position.is_finite() or not velocity.is_finite():
			return false
		if _intersects(inverse * position, inverse * (position + velocity * APPROACH_SECONDS), half):
			return false
	return true


static func _intersects(start: Vector3, finish: Vector3, half: Vector3) -> bool:
	var direction: Vector3 = finish - start
	var enter: float = 0.0
	var leave: float = 1.0
	for axis: int in 3:
		if absf(direction[axis]) < 0.000001:
			if absf(start[axis]) > half[axis]:
				return false
			continue
		var a: float = (-half[axis] - start[axis]) / direction[axis]
		var b: float = (half[axis] - start[axis]) / direction[axis]
		enter = maxf(enter, minf(a, b))
		leave = minf(leave, maxf(a, b))
		if enter > leave:
			return false
	return true
