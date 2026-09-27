extends Node3D

const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Track = preload("res://track/authored_track.gd")
const Protocol = preload("res://net/prototype_protocol.gd")
const Transport = preload("res://net/prototype_socket_server.gd")
const Driver = preload("res://input/driver_input.gd")
const BotDriver = preload("res://ai/racing_bot_driver.gd")
const HERO_COLOR: Color = Color("2e9d99")
const MAX_PLAYERS: int = 10
const PHYSICS_DT: float = 1.0 / 60.0
const INPUT_TIMEOUT_MS: int = 250
const RECONNECT_MS: int = 30000
const INTERPOLATION_DELAY_MS: int = 100
const RACE_LAPS: int = 3

var _worker: bool = false
var _track: Node3D
var _kart_script: Script
var _server: Node
var _secret: String = ""
var _players: Dictionary = {}
var _peer_players: Dictionary = {}
var _used_tickets: Dictionary = {}
var _tick: int = 0
var _countdown: int = -1
var _finish_count: int = 0
var _race_id: int = 0
var _phase: String = "waiting"
var _race_elapsed: float = 0.0
var _finish_remaining: float = -1.0

var _socket: WebSocketPeer
var _ticket: String = ""
var _player_id: String = ""
var _sequence: int = 0
var _pending: Array[Dictionary] = []
var _queued_snapshot: Dictionary = {}
var _local: CharacterBody3D
var _local_visual: Node3D
var _remotes: Dictionary = {}
var _camera: Camera3D
var _race_camera: RefCounted
var _sun: DirectionalLight3D
var _quality: String = "standard"
var _reduced_effects: bool = false
var _bridge: JavaScriptObject
var _bridge_callback: JavaScriptObject
var _status: String = "ready"
var _hud: Dictionary = {}
var _input_enabled: bool = true
var _focused: bool = true
var _joined: bool = false
var _last_server_ms: int = 0
var _last_ping_ms: int = 0
var _last_hud_ms: int = 0
var _correction: float = 0.0
var _ping: float = 0.0
var _client_countdown: float = 0.0


func _ready() -> void:
	_worker = "--race-worker" in OS.get_cmdline_user_args()
	Engine.physics_ticks_per_second = 60
	_track = Track.new()
	add_child(_track)
	_track.build(not _worker)
	if Protocol.track_identity(_track.identity()).is_empty():
		push_error("Invalid authored track package")
		get_tree().quit(1)
		return
	if _worker:
		Engine.max_fps = 60
		_secret = OS.get_environment("RACE_TICKET_SECRET")
		if _secret.length() < 32:
			push_error("RACE_TICKET_SECRET must contain at least 32 characters")
			get_tree().quit(1)
			return
		_server = Transport.new()
		add_child(_server)
		_server.received.connect(_on_packet)
		_server.disconnected.connect(_on_disconnect)
		var port: int = int(OS.get_environment("RACE_PORT")) if OS.has_environment("RACE_PORT") else 9080
		if port < 1 or port > 65535 or _server.listen(port) != OK:
			push_error("Could not bind local race worker port")
			get_tree().quit(1)
			return
		print("RACE_WORKER_READY ws://127.0.0.1:%d protocol=%d physics=60 snapshots=20 track=%s" % [port, Protocol.WIRE_VERSION, _track.identity()["track_id"]])
		return
	_setup_view()
	if OS.has_feature("web"):
		_bridge = JavaScriptBridge.get_interface("GnomHost")
		if _bridge != null:
			_bridge_callback = JavaScriptBridge.create_callback(_on_host_message)
			_bridge.register(_bridge_callback)
	else:
		_local = _create_vehicle(0, true)
		_local.reset_at(_track.spawn_transform(0))
		_status = "practice"
	_publish_hud()


func _physics_process(delta: float) -> void:
	if _worker:
		_step_server(delta)
		return
	# A resumed browser may already have fresh packets waiting behind a stale clock.
	_poll_client()
	# CharacterBody3D replay must use the engine's fixed physics delta.
	if not _queued_snapshot.is_empty():
		var snapshot: Dictionary = _queued_snapshot
		_queued_snapshot = {}
		_apply_snapshot(snapshot)
	if _local != null and (_joined or _status == "practice"):
		var command: Dictionary = _sample_input()
		if _joined:
			if Time.get_ticks_msec() - _last_server_ms > 3000 or _pending.size() >= 120:
				_leave("connection_lost")
				return
			_sequence += 1
			command["type"] = "input"
			command["sequence"] = _sequence
			_pending.append(command)
			_send(command)
			if _local == null:
				return
		_local.step(command if _can_drive() else Protocol.NEUTRAL, delta)
		_client_countdown = maxf(0.0, _client_countdown - delta)
	_update_camera(delta)


func _process(delta: float) -> void:
	if _worker:
		return
	_poll_client()
	_interpolate_remotes(delta)
	if is_instance_valid(_local) and is_instance_valid(_local_visual):
		_local_visual.update_visual(delta, _local.speed_mps, _local.steering_amount, _local.is_drifting, minf(1.0, _local.boost_remaining))
	if _joined and Time.get_ticks_msec() - _last_ping_ms >= 1000:
		_last_ping_ms = Time.get_ticks_msec()
		_send({"type": "ping", "sent": _last_ping_ms})
	if Time.get_ticks_msec() - _last_hud_ms >= 100:
		_publish_hud()


func _create_vehicle(_slot: int, visuals: bool) -> CharacterBody3D:
	var vehicle: CharacterBody3D = Vehicle.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = Vehicle.create_collision_shape()
	vehicle.add_child(collider)
	# The initial network probe excludes car-to-car collision prediction.
	vehicle.collision_layer = 2
	vehicle.collision_mask = 1
	if visuals:
		_local_visual = _create_kart_visual()
		vehicle.add_child(_local_visual)
	add_child(vehicle)
	return vehicle


func _create_kart_visual() -> Node3D:
	if _kart_script == null:
		_kart_script = load("res://vehicle/authored_kart.gd")
	var visual: Node3D = _kart_script.create(HERO_COLOR)
	if visual.has_method("set_reduced_effects"):
		visual.set_reduced_effects(_reduced_effects)
	return visual


func _step_server(delta: float) -> void:
	_tick += 1
	if _countdown > 0:
		_countdown -= 1
		if _countdown == 0:
			_phase = "racing"
	if _phase == "racing":
		_race_elapsed += delta
		if _finish_remaining >= 0.0:
			_finish_remaining = maxf(0.0, _finish_remaining - delta)
	var now: int = Time.get_ticks_msec()
	for id: String in _players.keys():
		var player: Dictionary = _players[id]
		if not player["is_bot"] and not player["connected"] and now - int(player["disconnected_at"]) > RECONNECT_MS:
			player["expired"] = true
		var queue: Array = player["queue"]
		if not queue.is_empty():
			player["input"] = queue.pop_front()
			player["ack"] = int(player["input"]["sequence"])
		var command: Dictionary = player["input"]
		if player["is_bot"] and _phase == "racing" and not player["finished"]:
			command = player["driver"].sample(player["vehicle"], player["progress"], delta)
		if (not player["is_bot"] and (not player["connected"] or now - int(player["last_input_at"]) > INPUT_TIMEOUT_MS)) or _phase != "racing" or player["finished"] or player["spectator"]:
			command = Protocol.NEUTRAL
		player["previous_position"] = player["vehicle"].global_position
		player["vehicle"].step(command, delta)
		if _phase == "racing" and not player["finished"] and not player["spectator"]:
			player["elapsed"] += delta
			_update_progress(player)
		if _track.needs_recovery(player["vehicle"].global_position) or not bool(player["progress"]["interval_valid"]) or (player["is_bot"] and player["driver"].needs_recovery()):
			_recover(player)
	_remove_expired_waiters()
	if _human_count() == 0:
		for player: Dictionary in _players.values():
			player["vehicle"].queue_free()
		_players.clear()
		_countdown = -1
		_finish_count = 0
		_phase = "waiting"
	elif _phase == "racing":
		var all_done: bool = true
		for player: Dictionary in _players.values():
			if not player["spectator"] and not player["finished"]:
				all_done = false
		if all_done or _race_elapsed >= 180.0 or _finish_remaining == 0.0:
			_phase = "results"
			for player: Dictionary in _players.values():
				player["dnf"] = not player["spectator"] and not player["finished"]
				player["result_progress"] = _race_progress(player)
	elif _phase == "results":
		_try_repeat()
	if _tick % 3 == 0:
		_broadcast_snapshot()
	if _tick % 600 == 0:
		for jti: String in _used_tickets.keys():
			if int(_used_tickets[jti]) <= int(Time.get_unix_time_from_system()):
				_used_tickets.erase(jti)


func _on_packet(peer_id: int, data: Dictionary) -> void:
	if not _peer_players.has(peer_id):
		if data.get("type") != "join" or not data.get("ticket") is String:
			_server.close_peer(peer_id, "join_required")
			return
		if not Protocol.validate_hello(data, _track.identity()):
			_server.close_peer(peer_id, "update_required")
			return
		_join_server(peer_id, data["ticket"])
		return
	var player: Dictionary = _players[_peer_players[peer_id]]
	match data.get("type"):
		"input":
			var command: Dictionary = Protocol.validate_input(data)
			if command.is_empty() or int(command["sequence"]) <= int(player["accepted"]) or int(command["sequence"]) > int(player["accepted"]) + 120:
				_server.close_peer(peer_id, "invalid_input")
				return
			if player["queue"].size() >= 30:
				_server.close_peer(peer_id, "input_backlog")
				return
			player["accepted"] = int(command["sequence"])
			player["last_input_at"] = Time.get_ticks_msec()
			player["queue"].append(command)
		"ping":
			if data.size() != 2 or not Protocol._number(data.get("sent")):
				_server.close_peer(peer_id, "invalid_ping")
				return
			_server.send_to(peer_id, {"type": "pong", "sent": data["sent"]})
		"restart":
			if data.size() != 2 or not Protocol._number(data.get("race_id")) or data["race_id"] != _race_id or _phase != "results" or player["spectator"]:
				return
			player["ready"] = true
			_try_repeat()
		"recover":
			if data.size() != 1 or Time.get_ticks_msec() - int(player["last_recover_at"]) < 1000:
				return
			player["last_recover_at"] = Time.get_ticks_msec()
			if _phase == "racing" and not player["finished"] and not player["spectator"]:
				_recover(player)
		_:
			_server.close_peer(peer_id, "unknown_packet")


func _join_server(peer_id: int, ticket: String) -> void:
	var claims: Dictionary = Protocol.verify_ticket(ticket, _secret, int(Time.get_unix_time_from_system()), _track.identity())
	if claims.is_empty() or _used_tickets.has(claims.get("jti", "")):
		_server.close_peer(peer_id, "invalid_ticket")
		return
	var id: String = claims["player_id"]
	if id.begins_with("bot:"):
		_server.close_peer(peer_id, "invalid_ticket")
		return
	if (not _players.has(id) or _players[id].get("expired", false)) and _human_count() >= MAX_PLAYERS:
		_server.close_peer(peer_id, "lobby_full")
		return
	_used_tickets[claims["jti"]] = claims["expires_at"]
	if not _players.has(id):
		var spectator: bool = _phase in ["racing", "results"]
		_remove_expired_waiters()
		if not spectator:
			_remove_one_bot()
		var occupied: Array = []
		for other: Dictionary in _players.values():
			if not other["spectator"]:
				occupied.append(other["slot"])
		var slot: int = 0
		while slot in occupied:
			slot += 1
		_players[id] = _new_player(id, claims["display_name"], mini(slot, MAX_PLAYERS - 1), false)
		_players[id]["peer_id"] = peer_id
		_players[id]["spectator"] = spectator
		if _countdown < 0:
			_start_race()
	var player: Dictionary = _players[id]
	var previous_peer: int = int(player["peer_id"])
	if previous_peer != peer_id:
		_peer_players.erase(previous_peer)
		_server.close_peer(previous_peer, "replaced")
	player["peer_id"] = peer_id
	player["connected"] = true
	player["expired"] = false
	player["queue"].clear()
	player["input"] = Protocol.NEUTRAL.duplicate()
	player["accepted"] = player["ack"]
	player["last_input_at"] = Time.get_ticks_msec()
	_peer_players[peer_id] = id
	_server.authenticate(peer_id)
	_server.send_to(peer_id, {"type": "welcome", "player_id": id, "compatibility": Protocol.compatibility(_track.identity()), "ack": player["ack"]})
	_broadcast_snapshot()


func _on_disconnect(peer_id: int) -> void:
	if not _peer_players.has(peer_id):
		return
	var id: String = _peer_players[peer_id]
	_peer_players.erase(peer_id)
	if _players.has(id):
		var player: Dictionary = _players[id]
		player["connected"] = false
		player["disconnected_at"] = Time.get_ticks_msec()
		player["queue"].clear()
		player["input"] = Protocol.NEUTRAL.duplicate()


func _human_count() -> int:
	var count: int = 0
	for player: Dictionary in _players.values():
		if not player["is_bot"] and not player.get("expired", false):
			count += 1
	return count


func _new_player(id: String, display_name: String, slot: int, bot: bool) -> Dictionary:
	var vehicle: CharacterBody3D = _create_vehicle(slot, false)
	vehicle.reset_at(_track.spawn_transform(slot))
	return {"id": id, "name": display_name, "slot": slot, "vehicle": vehicle,
		"is_bot": bot, "driver": BotDriver.new(_track, slot) if bot else null,
		"spectator": false, "ready": bot, "dnf": false,
		"peer_id": 0, "connected": true, "disconnected_at": 0, "last_input_at": 0,
		"accepted": 0, "ack": 0, "queue": [], "input": Protocol.NEUTRAL.duplicate(),
		"lap": 1, "progress": _track.initial_progress(), "previous_position": vehicle.global_position,
		"finished": false, "finish_order": 0, "elapsed": 0.0, "last_recover_at": -1000, "epoch": 0}


func _remove_one_bot() -> void:
	# Vacant human slots take precedence over bot replacement during preparation.
	for id: String in _players.keys():
		if _players[id].get("expired", false):
			_players[id]["vehicle"].queue_free()
			_players.erase(id)
			return
	for id: String in _players.keys():
		if _players[id]["is_bot"]:
			_players[id]["vehicle"].queue_free()
			_players.erase(id)
			return


func _remove_expired_waiters() -> void:
	for id: String in _players.keys():
		if _players[id]["spectator"] and _players[id].get("expired", false):
			_players[id]["vehicle"].queue_free()
			_players.erase(id)


func _start_race() -> void:
	for id: String in _players.keys():
		if _players[id]["is_bot"] or _players[id].get("expired", false):
			_players[id]["vehicle"].queue_free()
			_players.erase(id)
	var slot: int = 0
	for player: Dictionary in _players.values():
		player["slot"] = slot
		player["spectator"] = false
		_reset_race(player)
		slot += 1
	while slot < MAX_PLAYERS:
		var id: String = "bot:%d" % slot
		_players[id] = _new_player(id, "Bot %02d" % (slot + 1), slot, true)
		slot += 1
	_race_id += 1
	_phase = "countdown"
	_countdown = 300
	_finish_count = 0
	_race_elapsed = 0.0
	_finish_remaining = -1.0


func _try_repeat() -> void:
	if _phase != "results":
		return
	var eligible: int = 0
	for player: Dictionary in _players.values():
		if player["is_bot"] or not player["connected"]:
			continue
		eligible += 1
		if not player["spectator"] and not player["ready"]:
			return
	if eligible > 0:
		_start_race()


func _update_progress(player: Dictionary) -> void:
	var events: Array = _track.advance_progress(player["progress"], player["previous_position"], player["vehicle"].global_position)
	player["lap"] = int(player["progress"]["lap"]) + 1
	for event: Dictionary in events:
		if event["type"] == "finish" and not player["finished"]:
			_finish_count += 1
			player["finished"] = true
			player["finish_order"] = _finish_count
			if _finish_remaining < 0.0:
				_finish_remaining = 30.0


func _recover(player: Dictionary) -> void:
	player["vehicle"].reset_at(_track.recovery_transform(player["progress"]))
	_track.mark_recovered(player["progress"])
	player["previous_position"] = player["vehicle"].global_position
	player["queue"].clear()
	player["input"] = Protocol.NEUTRAL.duplicate()
	player["ack"] = player["accepted"]
	player["epoch"] += 1
	if player["is_bot"]:
		player["driver"].reset()


func _reset_race(player: Dictionary) -> void:
	player["lap"] = 1
	player["progress"] = _track.initial_progress()
	player["finished"] = false
	player["finish_order"] = 0
	player["elapsed"] = 0.0
	player["dnf"] = false
	player["ready"] = player["is_bot"]
	_recover(player)
	player["vehicle"].reset_at(_track.spawn_transform(int(player["slot"])))
	player["previous_position"] = player["vehicle"].global_position


func _broadcast_snapshot() -> void:
	var standings: Array = _players.values().filter(func(player: Dictionary) -> bool: return not player["spectator"])
	standings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["finished"] or b["finished"]:
			return int(a["finish_order"]) < int(b["finish_order"]) if a["finished"] and b["finished"] else a["finished"]
		var distance_a: float = a.get("result_progress", 0.0) if _phase == "results" else _race_progress(a)
		var distance_b: float = b.get("result_progress", 0.0) if _phase == "results" else _race_progress(b)
		return int(a["slot"]) < int(b["slot"]) if is_equal_approx(distance_a, distance_b) else distance_a > distance_b)
	# Spectators receive an authoritative camera anchor but do not occupy race positions.
	standings.append_array(_players.values().filter(func(player: Dictionary) -> bool: return player["spectator"]))
	var entries: Array = []
	for index: int in standings.size():
		var player: Dictionary = standings[index]
		entries.append({"id": player["id"], "name": player["name"], "slot": player["slot"],
			"position": 0 if player["spectator"] else index + 1, "lap": mini(RACE_LAPS, int(player["lap"])), "finished": player["finished"],
			"is_bot": player["is_bot"], "spectator": player["spectator"], "ready": player["ready"], "dnf": player["dnf"],
			"connected": player["connected"], "elapsed": player["elapsed"], "ack": player["ack"], "epoch": player["epoch"],
			"state": Protocol.pack_state(player["vehicle"].capture_state())})
	var packet: Dictionary = {"type": "snapshot", "tick": _tick, "race_id": _race_id, "phase": _phase,
		"finish_remaining": _finish_remaining, "race_remaining": maxf(0.0, 180.0 - _race_elapsed),
		"countdown": maxf(0.0, float(_countdown) / 60.0), "players": entries}
	for peer_id: int in _peer_players:
		_server.send_to(peer_id, packet, true)


func _race_progress(player: Dictionary) -> float:
	return _track.standings_distance(player["progress"], player["vehicle"].global_position)


func _setup_view() -> void:
	# Warm client-only assets before networking clocks start; workers never load them.
	_kart_script = load("res://vehicle/authored_kart.gd")
	_kart_script.warm()
	get_viewport().msaa_3d = Viewport.MSAA_2X
	var environment: WorldEnvironment = WorldEnvironment.new()
	var settings: Environment = Environment.new()
	var sky: Sky = Sky.new()
	var sky_material: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://art/summer-sky.png")
	sky.sky_material = sky_material
	settings.background_mode = Environment.BG_SKY
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c1d9ec")
	settings.ambient_light_energy = 0.5
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_color = Color("fff1d8")
	sun.light_energy = 0.78
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	_sun = sun
	_camera = Camera3D.new()
	_camera.fov = 58.0
	_camera.far = 1200.0
	_camera.position = Vector3(95.0, 65.0, 65.0)
	add_child(_camera)
	_camera.look_at(Vector3(10.0, 0.0, 0.0))
	_camera.current = true
	_race_camera = load("res://view/race_camera.gd").new()
	_race_camera.configure(_camera)
	_apply_graphics_settings(_quality, _reduced_effects)


func _apply_graphics_settings(quality: String, reduced_effects: bool) -> void:
	if _worker or quality not in ["standard", "low"]:
		return
	_quality = quality
	_reduced_effects = reduced_effects
	var low: bool = quality == "low"
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = 0.75 if low else 1.0
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	if _sun != null:
		_sun.directional_shadow_max_distance = 45.0 if low else 120.0
	if _track != null:
		if _track.has_method("set_quality"):
			_track.set_quality(low)
		if _track.has_method("set_reduced_effects"):
			_track.set_reduced_effects(reduced_effects)
	if is_instance_valid(_local_visual) and _local_visual.has_method("set_reduced_effects"):
		_local_visual.set_reduced_effects(reduced_effects)
	for remote: Dictionary in _remotes.values():
		if remote["node"].has_method("set_reduced_effects"):
			remote["node"].set_reduced_effects(reduced_effects)


func _sample_input() -> Dictionary:
	if not _focused or not _input_enabled:
		return Protocol.NEUTRAL.duplicate()
	var command: Dictionary = Driver.sample()
	for key: String in ["use_item_1", "use_item_2", "look_back"]:
		command.erase(key)
	return command


func _on_host_message(arguments: Array) -> void:
	if arguments.is_empty():
		return
	var parsed: Variant = JSON.parse_string(str(arguments[0]))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	match data.get("type"):
		"graphics":
			if data.get("quality") is String and data.get("reduced_effects") is bool:
				_apply_graphics_settings(data["quality"], data["reduced_effects"])
		"join":
			if not data.get("compatibility") is Dictionary or not Protocol.compatible(data["compatibility"], _track.identity()):
				_leave("update_required")
			elif data.get("url") is String and data.get("ticket") is String:
				_connect_client(data["url"], data["ticket"])
		"leave":
			_leave("ready")
		"focus":
			_focused = bool(data.get("visible", true))
			if not _focused:
				_release_inputs()
		"input_enabled":
			_input_enabled = bool(data.get("enabled", true))
			if not _input_enabled:
				_release_inputs()
		"recover", "restart":
			if _joined:
				if data["type"] == "restart":
					_send({"type": "restart", "race_id": data.get("race_id", -1)})
				else:
					_send({"type": "recover"})


func _connect_client(url: String, ticket: String) -> void:
	_leave("connecting")
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = 1048576
	_socket.max_queued_packets = 256
	_ticket = ticket
	_last_server_ms = Time.get_ticks_msec()
	if _socket.connect_to_url(url) != OK:
		_leave("connection_failed")


func _release_inputs() -> void:
	for action: String in ["drive_left", "drive_right", "drive_accelerate", "drive_brake", "drive_drift", "look_back"]:
		Input.action_release(action)


func _poll_client() -> void:
	if _socket == null:
		return
	_socket.poll()
	var state: int = _socket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_leave("update_required" if _socket.get_close_reason() == "update_required" else "disconnected")
		return
	if state != WebSocketPeer.STATE_OPEN:
		if Time.get_ticks_msec() - _last_server_ms > 6000:
			_leave("connection_timeout")
		return
	if not _ticket.is_empty():
		_send({"type": "join", "ticket": _ticket, "compatibility": Protocol.compatibility(_track.identity())})
		_ticket = ""
	while _socket != null and _socket.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		if not parsed is Dictionary:
			continue
		_last_server_ms = Time.get_ticks_msec()
		match parsed.get("type"):
			"welcome":
				if not Protocol.validate_welcome(parsed, _track.identity()):
					_leave("update_required")
					return
				_player_id = str(parsed.get("player_id", ""))
				_sequence = int(parsed.get("ack", 0))
				_joined = true
				_status = "connected"
			"snapshot":
				_queue_snapshot(parsed)
			"pong":
				_ping = maxf(0.0, float(Time.get_ticks_msec()) - float(parsed.get("sent", 0)))
	if _socket != null and Time.get_ticks_msec() - _last_server_ms > 6000:
		_leave("connection_timeout")


func _queue_snapshot(packet: Dictionary) -> void:
	var server_tick: int = int(packet.get("tick", 0))
	if server_tick <= _tick or server_tick <= int(_queued_snapshot.get("tick", 0)):
		return
	_queued_snapshot = packet


func _apply_snapshot(packet: Dictionary) -> void:
	assert(Engine.is_in_physics_frame(), "Reconciliation requires the fixed physics tick")
	if not _joined or not packet.get("players") is Array:
		return
	var server_tick: int = int(packet.get("tick", 0))
	if server_tick <= _tick:
		return
	_tick = server_tick
	var generation_changed: bool = _race_id != int(packet.get("race_id", 0))
	_race_id = int(packet.get("race_id", 0))
	_phase = str(packet.get("phase", "waiting"))
	_finish_remaining = float(packet.get("finish_remaining", -1.0))
	_race_elapsed = 180.0 - float(packet.get("race_remaining", 180.0))
	_client_countdown = float(packet.get("countdown", 0.0))
	var public_players: Array = []
	var seen: Array[String] = []
	for entry: Variant in packet["players"]:
		if not entry is Dictionary or not entry.get("state") is Dictionary:
			continue
		var state: Dictionary = Protocol.unpack_state(entry["state"])
		if state.is_empty():
			continue
		var id: String = str(entry.get("id", ""))
		if entry.get("spectator", false) and id != _player_id:
			continue
		seen.append(id)
		var location: Vector3 = state["transform"].origin
		if not entry.get("spectator", false):
			public_players.append({"id": id, "name": entry.get("name", ""), "lap": entry.get("lap", 1), "position": entry.get("position", 1), "connected": entry.get("connected", true), "worldPosition": [location.x, location.y, location.z],
				"isBot": entry.get("is_bot", false), "ready": entry.get("ready", false), "dnf": entry.get("dnf", false), "finished": entry.get("finished", false), "elapsed": entry.get("elapsed", 0.0)})
		if id == _player_id:
			if _local == null:
				_local = _create_vehicle(int(entry.get("slot", 0)), true)
			var before: Vector3 = _local.global_position
			var ack: int = int(entry.get("ack", 0))
			_pending = _pending.filter(func(command: Dictionary) -> bool: return int(command["sequence"]) > ack)
			_local.restore_state(state)
			var epoch_changed: bool = int(_hud.get("epoch", -1)) != int(entry.get("epoch", 0))
			if epoch_changed:
				_pending.clear()
			for command: Dictionary in _pending:
				_local.step(command if _phase == "racing" and not entry.get("finished", false) and not entry.get("spectator", false) else Protocol.NEUTRAL, PHYSICS_DT)
			if epoch_changed and _race_camera != null:
				_race_camera.reset(_local)
			_correction = before.distance_to(_local.global_position)
			_hud = entry.duplicate()
			_hud.erase("state")
			_status = "spectating" if entry.get("spectator", false) else ("finished" if entry.get("finished", false) else ("results" if _phase == "results" else _phase))
		else:
			if not _remotes.has(id):
				var visual: Node3D = _create_kart_visual()
				add_child(visual)
				visual.global_transform = state["transform"]
				_remotes[id] = {"node": visual, "samples": []}
			var samples: Array = _remotes[id]["samples"]
			if generation_changed or int(_remotes[id].get("epoch", -1)) != int(entry.get("epoch", 0)):
				samples.clear()
				_remotes[id]["node"].global_transform = state["transform"]
			_remotes[id]["epoch"] = int(entry.get("epoch", 0))
			samples.append({"at": Time.get_ticks_msec(), "transform": state["transform"],
				"speed": state["velocity"].slide(state["up_direction"]).length(), "steering": state["steering_amount"],
				"drifting": state["is_drifting"], "boost": state["boost_remaining"]})
			while samples.size() > 12:
				samples.pop_front()
	for id: String in _remotes.keys():
		if id not in seen:
			_remotes[id]["node"].queue_free()
			_remotes.erase(id)
	_hud["players"] = public_players


func _can_drive() -> bool:
	return _status == "practice" or (_phase == "racing" and not _hud.get("finished", false) and not _hud.get("spectator", false))


func _interpolate_remotes(delta: float) -> void:
	var target: int = Time.get_ticks_msec() - INTERPOLATION_DELAY_MS
	for remote: Dictionary in _remotes.values():
		var samples: Array = remote["samples"]
		while samples.size() > 2 and int(samples[1]["at"]) <= target:
			samples.pop_front()
		if samples.is_empty():
			continue
		var result: Transform3D = samples[0]["transform"]
		if samples.size() > 1:
			var weight: float = clampf(float(target - int(samples[0]["at"])) / maxf(1.0, float(int(samples[1]["at"]) - int(samples[0]["at"]))), 0.0, 1.0)
			result = result.interpolate_with(samples[1]["transform"], weight)
		remote["node"].global_transform = result
		var motion: Dictionary = samples[0]
		remote["node"].update_visual(delta, motion["speed"], motion["steering"], motion["drifting"], minf(1.0, motion["boost"]))


func _update_camera(delta: float) -> void:
	if _race_camera == null or _local == null:
		return
	_race_camera.update(_local, delta, _input_enabled and _focused and Input.is_action_pressed("look_back"))


func _send(packet: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if _socket.get_current_outbound_buffered_amount() > 65536:
			_leave("connection_lost")
			return
		if _socket.send_text(JSON.stringify(packet)) != OK:
			_leave("connection_lost")


func _leave(status: String) -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_ticket = ""
	_joined = false
	_pending.clear()
	_queued_snapshot.clear()
	_player_id = ""
	_sequence = 0
	_tick = 0
	_race_id = 0
	_phase = "waiting"
	_client_countdown = 0.0
	_hud.clear()
	_status = status
	if _local != null:
		_local.queue_free()
		_local = null
		_local_visual = null
	for remote: Dictionary in _remotes.values():
		remote["node"].queue_free()
	_remotes.clear()
	_publish_hud()


func _publish_hud() -> void:
	_last_hud_ms = Time.get_ticks_msec()
	var location: Vector3 = Vector3.ZERO if _local == null else _local.global_position
	var forward: Vector3 = Vector3.FORWARD if _local == null else -_local.global_basis.z
	var data: Dictionary = {"status": _status, "playerId": _player_id, "players": _hud.get("players", []),
		"raceId": _race_id, "phase": _phase, "spectating": _hud.get("spectator", false),
		"repeatReady": _hud.get("ready", false), "dnf": _hud.get("dnf", false),
		"canRestart": _phase == "results" and not _hud.get("ready", false) and not _hud.get("spectator", false),
		"finishRemaining": _finish_remaining, "raceRemaining": maxf(0.0, 180.0 - _race_elapsed),
		"graphics": {"quality": _quality, "reducedEffects": _reduced_effects, "renderScale": get_viewport().scaling_3d_scale},
		"track": _track.descriptor() if _track != null else {},
		"worldPosition": [location.x, location.y, location.z],
		"forward": [forward.x, forward.y, forward.z],
		"position": _hud.get("position", 1), "speed": 0.0 if _local == null else _local.speed_mps * 3.6,
		"drift": 0.0 if _local == null else _local.drift_charge, "boost": 0.0 if _local == null else _local.boost_remaining,
		"lap": _hud.get("lap", 1), "finished": _hud.get("finished", false), "elapsed": _hud.get("elapsed", 0.0),
		"countdown": _client_countdown, "ping": _ping, "correction": _correction, "serverTick": _tick,
		"pendingInputs": _pending.size(), "fps": Engine.get_frames_per_second()}
	if _bridge != null:
		_bridge.update(JSON.stringify(data))
