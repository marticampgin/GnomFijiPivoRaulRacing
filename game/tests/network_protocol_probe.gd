extends SceneTree

const Protocol = preload("res://net/prototype_protocol.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Prototype = preload("res://app/prototype.gd")
const Track = preload("res://track/prototype_track.gd")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var input: Dictionary = {"type": "input", "sequence": 1, "steering": -1.0, "throttle": 1.0, "brake": 0.0, "drift": true}
	_check(not Protocol.validate_input(input).is_empty(), "valid input")
	for key: String in ["sequence", "steering", "throttle", "brake"]:
		for invalid: Variant in [NAN, INF, -INF, "1", null, true]:
			var broken: Dictionary = input.duplicate()
			broken[key] = invalid
			_check(Protocol.validate_input(broken).is_empty(), "reject %s:%s" % [key, str(invalid)])
	for changes: Dictionary in [{"sequence": 0}, {"sequence": 1.5}, {"sequence": 2147483648}, {"steering": 1.01}, {"brake": -0.1}, {"drift": 1}, {"type": "position"}, {"extra": 1}]:
		var broken: Dictionary = input.duplicate()
		broken.merge(changes, true)
		_check(Protocol.validate_input(broken).is_empty(), "reject invalid input shape/range %s" % str(changes))
	var secret: String = "test-only-network-secret-at-least-32-chars"
	var now: int = 1800000000
	var claims: Dictionary = {"v": 1, "protocol_version": 1, "match_id": "prototype-1", "loadout_hash": "prototype-v1", "expires_at": now + 60, "player_id": "test-player", "display_name": "Test Racer", "jti": "test-once"}
	var ticket: String = _sign(claims, secret)
	_check(not Protocol.verify_ticket(ticket, secret, now).is_empty(), "valid signed ticket")
	_check(Protocol.verify_ticket(ticket, "wrong-secret-that-is-also-over-32-chars", now).is_empty(), "wrong signature")
	_check(Protocol.verify_ticket(ticket, secret, now + 60).is_empty(), "expired ticket")
	_check(Protocol.verify_ticket(ticket + "=", secret, now).is_empty(), "noncanonical signature")
	_check(Protocol.verify_ticket(ticket, "short", now).is_empty(), "short secret")
	for changes: Dictionary in [{"v": 2}, {"protocol_version": 2}, {"match_id": "other"}, {"loadout_hash": "other"}, {"expires_at": now + 121}, {"expires_at": now + 1.5}, {"player_id": ""}, {"jti": ""}, {"display_name": "x".repeat(129)}]:
		var broken: Dictionary = claims.duplicate()
		broken.merge(changes, true)
		_check(Protocol.verify_ticket(_sign(broken, secret), secret, now).is_empty(), "reject claims %s" % str(changes))
	var vehicle: CharacterBody3D = Vehicle.new()
	root.add_child(vehicle)
	var state: Dictionary = Protocol.pack_state(vehicle.capture_state())
	_check(not Protocol.unpack_state(state).is_empty(), "state JSON roundtrip")
	for changes: Dictionary in [{"position": [NAN, 0.0, 0.0]}, {"velocity": [0.0, INF, 0.0]}, {"position": [1000001.0, 0.0, 0.0]}, {"drift_charge": NAN}, {"boost_remaining": 3.0}, {"grounded": 1}, {"balance_version": "other"}, {"basis": [[0, 0, 0], [0, 0, 0], [0, 0, 0]]}]:
		var broken: Dictionary = state.duplicate(true)
		broken.merge(changes, true)
		_check(Protocol.unpack_state(broken).is_empty(), "reject malformed state %s" % str(changes))
	var app: Node3D = Prototype.new()
	var track: Node3D = Track.new()
	app._track = track
	var player: Dictionary = {"vehicle": vehicle, "lap": 1, "next_sector": 1, "checkpoint": 0, "finished": false, "finish_order": 0}
	vehicle.global_position = Vector3(Track.RADIUS_X, 0.65, 0.0)
	app._update_progress(player)
	_check(player["lap"] == 1 and player["next_sector"] == 1, "initial start line does not finish lap")
	var line_progress: float = app._race_progress(player)
	vehicle.global_transform = track.spawn_transform(0)
	_check(app._race_progress(player) < line_progress, "crossing start ranks ahead of waiting grid")
	vehicle.global_position = Vector3(0.0, 0.65, Track.RADIUS_Z)
	app._update_progress(player)
	_check(player["next_sector"] == 1, "skipped checkpoints do not advance")
	_check(app._race_progress(player) <= 1.0, "unverified sector angle cannot inflate standings")
	for lap_index: int in 3:
		for sector_index: int in 16:
			var sector: int = (sector_index + 1) % 16
			var angle: float = (float(sector) + 0.1) * TAU / 16.0
			vehicle.global_position = Vector3(Track.RADIUS_X * cos(angle), 0.65, Track.RADIUS_Z * sin(angle))
			app._update_progress(player)
		_check(player["lap"] == lap_index + 2, "ordered checkpoints complete lap %d" % (lap_index + 1))
	_check(player["finished"] and player["finish_order"] == 1, "three server-counted laps finish race")
	app.free()
	track.free()
	vehicle.free()
	print("NETWORK_PROTOCOL_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _sign(claims: Dictionary, secret: String) -> String:
	var payload: String = _base64url(JSON.stringify(claims).to_utf8_buffer())
	var context: HMACContext = HMACContext.new()
	context.start(HashingContext.HASH_SHA256, secret.to_utf8_buffer())
	context.update(payload.to_utf8_buffer())
	return payload + "." + _base64url(context.finish())


func _base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
