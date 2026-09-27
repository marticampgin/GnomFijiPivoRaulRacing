extends RefCounted

const BALANCE_VERSION: int = 1
const START_WINDOW_EARLY: float = 0.65
const START_WINDOW_LATE: float = 0.15
const START_BOOST_SECONDS: float = 1.0
const SLIP_MIN_DISTANCE: float = 3.0
const SLIP_MAX_DISTANCE: float = 18.0
const SLIP_MAX_LATERAL: float = 2.4
const SLIP_MAX_HEIGHT: float = 2.2
const SLIP_MIN_HEADING_DOT: float = 0.9
const SLIP_MIN_SPEED: float = 8.0
const SLIP_DWELL_SECONDS: float = 1.2
const SLIP_BOOST_SECONDS: float = 1.0
const SLIP_COOLDOWN_SECONDS: float = 3.0


static func new_state() -> Dictionary:
	return {"start_pressed": false, "start_armed": false, "start_boost_remaining": 0.0,
		"slipstream_charge": 0.0, "slipstream_boost_remaining": 0.0,
		"slipstream_cooldown": 0.0, "slipstream_target": ""}


static func presentation(player: Dictionary) -> Dictionary:
	var state: Dictionary = player.get("driving", new_state())
	var result: Dictionary = {}
	for key: String in ["start_boost_remaining", "slipstream_charge", "slipstream_boost_remaining", "slipstream_target"]:
		result[key] = state[key]
	return result


func countdown(player: Dictionary, command: Dictionary, seconds_left: float, at_start: bool) -> void:
	var state: Dictionary = player.driving
	var pressed: bool = float(command.get("throttle", 0.0)) >= 0.5 and float(command.get("brake", 0.0)) < 0.1 and not bool(command.get("drive_blocked", false))
	if not _eligible(player):
		pressed = false
	if pressed and not state.start_pressed:
		state.start_armed = seconds_left >= START_WINDOW_LATE and seconds_left <= START_WINDOW_EARLY
	if not pressed:
		state.start_armed = false
	state.start_pressed = pressed
	if at_start:
		if state.start_armed and pressed:
			_grant(player, START_BOOST_SECONDS)
			state.start_boost_remaining = START_BOOST_SECONDS
		state.start_armed = false


func step(players: Dictionary, delta: float) -> void:
	# Snapshot every racer before any body moves; dictionary iteration cannot change eligibility.
	var poses: Dictionary = {}
	for id: String in players:
		var player: Dictionary = players[id]
		var vehicle: CharacterBody3D = player.vehicle
		if _eligible(player) and vehicle.grounded:
			poses[id] = {"position": vehicle.global_position, "forward": -vehicle.global_basis.z,
				"up": vehicle.up_direction, "speed": vehicle.velocity.dot(-vehicle.global_basis.z)}
	for id: String in players:
		var player: Dictionary = players[id]
		var state: Dictionary = player.driving
		state.start_boost_remaining = maxf(0.0, state.start_boost_remaining - delta)
		state.slipstream_boost_remaining = maxf(0.0, state.slipstream_boost_remaining - delta)
		state.slipstream_cooldown = maxf(0.0, state.slipstream_cooldown - delta)
		var target: String = _target(id, poses) if state.slipstream_cooldown <= 0.0 else ""
		if target.is_empty():
			state.slipstream_charge = 0.0
			state.slipstream_target = ""
			continue
		if state.slipstream_target != target:
			state.slipstream_charge = 0.0
		state.slipstream_target = target
		state.slipstream_charge = minf(1.0, state.slipstream_charge + delta / SLIP_DWELL_SECONDS)
		if state.slipstream_charge >= 1.0 - 0.000001:
			_grant(player, SLIP_BOOST_SECONDS)
			state.slipstream_boost_remaining = SLIP_BOOST_SECONDS
			state.slipstream_cooldown = SLIP_COOLDOWN_SECONDS
			state.slipstream_charge = 0.0
			state.slipstream_target = ""


func _target(id: String, poses: Dictionary) -> String:
	if not poses.has(id) or poses[id].speed < SLIP_MIN_SPEED:
		return ""
	var self_pose: Dictionary = poses[id]
	var nearest: float = INF
	var result: String = ""
	for other_id: String in poses:
		if other_id == id:
			continue
		var other: Dictionary = poses[other_id]
		if other.speed < SLIP_MIN_SPEED or self_pose.forward.dot(other.forward) < SLIP_MIN_HEADING_DOT or self_pose.up.dot(other.up) < SLIP_MIN_HEADING_DOT:
			continue
		var offset: Vector3 = other.position - self_pose.position
		var distance: float = offset.dot(self_pose.forward)
		var height: float = absf(offset.dot(self_pose.up))
		var lateral: float = absf(offset.dot(self_pose.forward.cross(self_pose.up)))
		if distance < SLIP_MIN_DISTANCE or distance > SLIP_MAX_DISTANCE or height > SLIP_MAX_HEIGHT or lateral > SLIP_MAX_LATERAL:
			continue
		if distance < nearest or (is_equal_approx(distance, nearest) and other_id < result):
			nearest = distance
			result = other_id
	return result


func _eligible(player: Dictionary) -> bool:
	return not player.get("finished", false) and not player.get("spectator", false) and not player.get("expired", false) and bool(player.get("connected", true)) and float(player.combat.get("destroyed_remaining", 0.0)) <= 0.0 and float(player.combat.get("health", 100.0)) > 0.0


func _grant(player: Dictionary, duration: float) -> void:
	player.vehicle.boost_remaining = maxf(player.vehicle.boost_remaining, duration)
