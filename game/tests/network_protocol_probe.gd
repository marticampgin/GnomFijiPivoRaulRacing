extends SceneTree

const Protocol = preload("res://net/prototype_protocol.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Prototype = preload("res://app/prototype.gd")
const Track = preload("res://track/authored_track.gd")
const Baker = preload("res://track/track_baker.gd")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var item_command: Dictionary = {"type": "use_item", "sequence": 1, "race_id": 1, "epoch": 0, "slot": 0}
	_check(not Protocol.validate_item_command(item_command).is_empty(), "valid item command")
	var second_slot: Dictionary = item_command.duplicate()
	second_slot["slot"] = 1.0
	_check(not Protocol.validate_item_command(second_slot).is_empty(), "JSON integral slot one accepted")
	for key: String in ["sequence", "race_id", "epoch", "slot"]:
		for invalid: Variant in [NAN, INF, -INF, "1", null, true, -1, 0.5, 2147483648]:
			var broken: Dictionary = item_command.duplicate()
			broken[key] = invalid
			_check(Protocol.validate_item_command(broken).is_empty(), "reject item %s:%s" % [key, str(invalid)])
	for changes: Dictionary in [{"sequence": 0}, {"race_id": 0}, {"slot": 2}, {"type": "grant_item"}, {"extra": 1}]:
		var broken: Dictionary = item_command.duplicate()
		broken.merge(changes, true)
		_check(Protocol.validate_item_command(broken).is_empty(), "reject item shape/range %s" % str(changes))
	for key: String in item_command:
		var broken: Dictionary = item_command.duplicate()
		broken.erase(key)
		_check(Protocol.validate_item_command(broken).is_empty(), "reject missing item field %s" % key)
	var combat: Dictionary = {"health": 100.0, "max_health": 100.0, "slots": ["", "fanta"], "effects": {}, "destroyed_remaining": 0.0, "invulnerable_remaining": 0.0, "item_ack": 0, "shards": 0}
	_check(not Protocol.validate_combat(combat).is_empty(), "valid combat state")
	for item_id: String in ["fanta", "mermaid_rum", "ice_rum", "stroh80", "lays_crab", "bfg10k", "crystal_shield", "seeker", "rear_trap"]:
		var equipped: Dictionary = combat.duplicate(true)
		equipped["slots"] = [item_id, item_id]
		_check(not Protocol.validate_combat(equipped).is_empty(), "valid inventory item %s" % item_id)
	var active_combat: Dictionary = combat.duplicate(true)
	for effect_id: String in ["fanta", "mermaid_rum", "ice_rum", "lays_crab"]:
		active_combat["effects"][effect_id] = {"remaining": 8.0}
	active_combat["effects"]["burn"] = {"remaining": 4.0, "damage": 5.75}
	active_combat["effects"]["crystal_shield"] = {"remaining": 5.0}
	active_combat["effects"]["weapon_guard"] = {"remaining": 0.75}
	_check(not Protocol.validate_combat(active_combat).is_empty(), "bounded simultaneous effects accepted")
	for key: String in ["health", "max_health", "destroyed_remaining", "invulnerable_remaining", "item_ack"]:
		for invalid: Variant in [NAN, INF, -INF, true, "1", null, -1, 2147483648]:
			var broken: Dictionary = combat.duplicate(true)
			broken[key] = invalid
			_check(Protocol.validate_combat(broken).is_empty(), "reject combat %s:%s" % [key, str(invalid)])
	for changes: Dictionary in [{"health": 101}, {"max_health": 99}, {"slots": [""]}, {"slots": ["", "", ""]}, {"slots": [0, ""]}, {"slots": ["cheat", ""]}, {"effects": []}, {"effects": {"cheat": {"remaining": 1}}}, {"effects": {"fanta": {"remaining": 9}}}, {"effects": {"burn": {"remaining": 4, "damage": 6}}}, {"effects": {"burn": {"remaining": 4}}}, {"effects": {"fanta": {"remaining": 2, "damage": 2}}}, {"effects": {"fanta": {"remaining": NAN}}}, {"destroyed_remaining": 3}, {"invulnerable_remaining": 3}, {"item_ack": 0.5}, {"extra": 1}]:
		var broken: Dictionary = combat.duplicate(true)
		broken.merge(changes, true)
		_check(Protocol.validate_combat(broken).is_empty(), "reject combat structure/range %s" % str(changes))
	for key: String in combat:
		var broken: Dictionary = combat.duplicate(true)
		broken.erase(key)
		_check(Protocol.validate_combat(broken).is_empty(), "reject missing combat field %s" % key)
	_check(Protocol.validate_combat(null).is_empty(), "reject absent combat state")
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
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://track/baked/castle_waterfalls.json"))
	var compatibility: Dictionary = Protocol.compatibility(manifest)
	_check(not compatibility.is_empty(), "actual baked simulation has a valid compatibility descriptor")
	var claims: Dictionary = {"v": Protocol.TICKET_VERSION, "style_id": "handling", "match_id": "prototype-1", "expires_at": now + 60, "player_id": "test-player", "display_name": "Test Racer", "jti": "test-once"}
	claims.merge(compatibility)
	var ticket: String = _sign(claims, secret)
	_check(not Protocol.verify_ticket(ticket, secret, now, manifest).is_empty(), "valid signed ticket")
	for style: String in ["handling", "acceleration", "speed", "drift"]:
		var styled: Dictionary = claims.duplicate(true)
		styled["style_id"] = style
		_check(Protocol.verify_ticket(_sign(styled, secret), secret, now, manifest).get("style_id") == style, "signed style %s" % style)
	var invalid_style: Dictionary = claims.duplicate(true)
	invalid_style["style_id"] = "cheat"
	_check(Protocol.verify_ticket(_sign(invalid_style, secret), secret, now, manifest).is_empty(), "unknown style rejected")
	invalid_style.erase("style_id")
	_check(Protocol.verify_ticket(_sign(invalid_style, secret), secret, now, manifest).is_empty(), "missing style rejected")
	_check(Protocol.verify_ticket(ticket, "wrong-secret-that-is-also-over-32-chars", now, manifest).is_empty(), "wrong signature")
	_check(Protocol.verify_ticket(ticket, secret, now + 60, manifest).is_empty(), "expired ticket")
	_check(Protocol.verify_ticket(ticket + "=", secret, now, manifest).is_empty(), "noncanonical signature")
	_check(Protocol.verify_ticket(ticket, "short", now, manifest).is_empty(), "short secret")
	for changes: Dictionary in [{"v": 1}, {"protocol_version": 1}, {"vehicle_state_version": 2}, {"match_id": "other"}, {"loadout_hash": "prototype-v1"}, {"loadout_hash": "other"}, {"expires_at": now + 121}, {"expires_at": now + 1.5}, {"player_id": ""}, {"jti": ""}, {"display_name": "x".repeat(129)}]:
		var broken: Dictionary = claims.duplicate()
		broken.merge(changes, true)
		_check(Protocol.verify_ticket(_sign(broken, secret), secret, now, manifest).is_empty(), "reject claims %s" % str(changes))
	var hello: Dictionary = {"type": "join", "ticket": ticket, "compatibility": compatibility}
	var welcome: Dictionary = {"type": "welcome", "player_id": "test-player", "ack": 42, "compatibility": compatibility}
	var sharp_box: Dictionary = claims.duplicate(true)
	sharp_box["loadout_hash"] = "prototype-v2"
	_check(Protocol.verify_ticket(_sign(sharp_box, secret), secret, now, manifest).is_empty(), "reject signed sharp-box simulation")
	var old_hello: Dictionary = hello.duplicate(true)
	old_hello["compatibility"]["loadout_hash"] = "prototype-v2"
	_check(not Protocol.validate_hello(old_hello, manifest), "reject sharp-box client")
	_check(Protocol.validate_hello(hello, manifest), "current hello compatibility")
	_check(Protocol.validate_welcome(welcome, manifest), "compatible reconnect welcome preserves acknowledged sequence")
	_check(not Protocol.validate_hello({"type": "join", "ticket": ticket}, manifest), "legacy hello rejected")
	_check(not Protocol.validate_welcome({"type": "welcome", "player_id": "test-player", "ack": 42, "protocol_version": 1}, manifest), "legacy welcome rejected")
	for changes: Dictionary in [{"track_id": "other"}, {"schema_version": 2}, {"simulation_revision": int(manifest["simulation_revision"]) + 1}, {"simulation_hash": "a".repeat(64)}, {"simulation_hash": "invalid"}, {"art_revision": 0}]:
		var broken: Dictionary = claims.duplicate(true)
		broken["track"].merge(changes, true)
		_check(Protocol.verify_ticket(_sign(broken, secret), secret, now, manifest).is_empty(), "reject signed incompatible track %s" % str(changes))
		var broken_hello: Dictionary = hello.duplicate(true)
		broken_hello["compatibility"]["track"].merge(changes, true)
		_check(not Protocol.validate_hello(broken_hello, manifest), "reject stale client track %s" % str(changes))
		var broken_welcome: Dictionary = welcome.duplicate(true)
		broken_welcome["compatibility"]["track"].merge(changes, true)
		_check(not Protocol.validate_welcome(broken_welcome, manifest), "reject incompatible worker track %s" % str(changes))
	for key: String in ["protocol_version", "vehicle_state_version"]:
		var broken: Dictionary = hello.duplicate(true)
		broken["compatibility"][key] = 999
		_check(not Protocol.validate_hello(broken, manifest), "reject unsupported %s before joining" % key)
	var art_only: Dictionary = claims.duplicate(true)
	art_only["track"]["art_revision"] = int(manifest["art_revision"]) + 1
	_check(not Protocol.verify_ticket(_sign(art_only, secret), secret, now, manifest).is_empty(), "art-only revisions remain simulation-compatible")
	var missing: Dictionary = claims.duplicate()
	missing.erase("track")
	_check(Protocol.verify_ticket(_sign(missing, secret), secret, now, manifest).is_empty(), "missing signed track fails closed")
	var vehicle: CharacterBody3D = Vehicle.new()
	root.add_child(vehicle)
	vehicle.global_transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(4.0, 3.0, -2.0))
	vehicle.velocity = Vector3(2.0, -1.0, 7.0)
	vehicle.drift_charge = 0.75
	vehicle.boost_remaining = 1.25
	var state: Dictionary = JSON.parse_string(JSON.stringify(Protocol.pack_state(vehicle.capture_state())))
	var unpacked: Dictionary = Protocol.unpack_state(state)
	var sharp_box_state: Dictionary = state.duplicate(true)
	sharp_box_state["balance_version"] = "vehicle-prototype-v2"
	_check(Protocol.unpack_state(sharp_box_state).is_empty(), "reject sharp-box snapshot")
	_check(not unpacked.is_empty(), "state JSON roundtrip")
	_check(Protocol.WIRE_VERSION != Vehicle.STATE_VERSION and state["version"] == Vehicle.STATE_VERSION, "wire update does not change vehicle state schema")
	_check(unpacked["transform"].is_equal_approx(vehicle.global_transform) and unpacked["velocity"].is_equal_approx(vehicle.velocity), "snapshot preserves transform and velocity")
	_check(unpacked["drift_charge"] == 0.75 and unpacked["boost_remaining"] == 1.25, "snapshot preserves drift and boost")
	for changes: Dictionary in [{"version": 2}, {"position": [NAN, 0.0, 0.0]}, {"velocity": [0.0, INF, 0.0]}, {"position": [1000001.0, 0.0, 0.0]}, {"drift_charge": NAN}, {"boost_remaining": 3.0}, {"grounded": 1}, {"balance_version": "vehicle-prototype-v1"}, {"balance_version": "other"}, {"basis": [[0, 0, 0], [0, 0, 0], [0, 0, 0]]}]:
		var broken: Dictionary = state.duplicate(true)
		broken.merge(changes, true)
		_check(Protocol.unpack_state(broken).is_empty(), "reject malformed state %s" % str(changes))
	var app: Node3D = Prototype.new()
	var track: Node3D = Track.new()
	app._track = track
	var player: Dictionary = {"vehicle": vehicle, "lap": 1, "progress": track.initial_progress(), "finished": false, "finish_order": 0}
	vehicle.global_transform = track.spawn_transform(0)
	player["previous_position"] = vehicle.global_position
	app._update_progress(player)
	_check(player["lap"] == 1 and player["progress"]["expected_gate"] == 0, "initial grid does not finish lap")
	var grid_progress: float = app._race_progress(player)
	_move_player(app, player, Baker.vector(track.data.samples[1].position) + Vector3.UP * 0.65)
	var line_progress: float = app._race_progress(player)
	_check(grid_progress < line_progress, "crossing start ranks ahead of waiting grid")
	_move_player(app, player, Baker.vector(track.data.gates[4].position) + Vector3.UP * 0.65)
	_check(player["progress"]["expected_gate"] == 1, "skipped checkpoints do not advance")
	_check(app._race_progress(player) <= float(track.data.gates[1].s), "unverified neighboring road cannot inflate standings")
	player["progress"] = track.initial_progress()
	vehicle.global_transform = track.spawn_transform(0)
	_move_player(app, player, Baker.vector(track.data.samples[1].position) + Vector3.UP * 0.65)
	for lap_index: int in 3:
		for sample_index: int in range(2, track.data.samples.size()):
			_move_player(app, player, Baker.vector(track.data.samples[sample_index].position) + Vector3.UP * 0.65)
		_move_player(app, player, Baker.vector(track.data.samples[1].position) + Vector3.UP * 0.65)
		_check(player["lap"] == lap_index + 2, "ordered checkpoints complete lap %d" % (lap_index + 1))
	_check(player["finished"] and player["finish_order"] == 1, "three server-counted laps finish race")
	_move_player(app, player, Baker.vector(track.data.samples[0].position) + Vector3.UP * 0.65)
	_move_player(app, player, Baker.vector(track.data.samples[1].position) + Vector3.UP * 0.65)
	_check(player["finish_order"] == 1 and app._finish_count == 1, "finished route never issues a second finish")
	app.free()
	track.free()
	vehicle.free()
	print("NETWORK_PROTOCOL_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _move_player(app: Node3D, player: Dictionary, position: Vector3) -> void:
	player["previous_position"] = player["vehicle"].global_position
	player["vehicle"].global_position = position
	app._update_progress(player)


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
