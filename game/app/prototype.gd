extends Node3D

const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Track = preload("res://track/prototype_track.gd")
const Kart = preload("res://vehicle/prototype_kart.gd")
const Protocol = preload("res://net/prototype_protocol.gd")
const Transport = preload("res://net/prototype_socket_server.gd")
const Driver = preload("res://input/driver_input.gd")
const COLORS: Array[Color] = [Color("63e5dc"), Color("ff826d"), Color("e5ff58"), Color("de93df"), Color("f4eff4")]
const MAX_PLAYERS: int = 10
const PHYSICS_DT: float = 1.0 / 60.0
const INPUT_TIMEOUT_MS: int = 250
const RECONNECT_MS: int = 30000
const INTERPOLATION_DELAY_MS: int = 100
const RACE_LAPS: int = 3

var _worker: bool = false
var _track: Node3D
var _server: Node
var _secret: String = ""
var _players: Dictionary = {}
var _peer_players: Dictionary = {}
var _used_tickets: Dictionary = {}
var _tick: int = 0
var _countdown: int = -1
var _finish_count: int = 0

var _socket: WebSocketPeer
var _ticket: String = ""
var _player_id: String = ""
var _sequence: int = 0
var _pending: Array[Dictionary] = []
var _queued_snapshot: Dictionary = {}
var _local: CharacterBody3D
var _remotes: Dictionary = {}
var _camera: Camera3D
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
		print("RACE_WORKER_READY ws://127.0.0.1:%d protocol=1 physics=60 snapshots=20" % port)
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
		_local.step(command if _client_countdown <= 0.0 and not _hud.get("finished", false) else Protocol.NEUTRAL, delta)
		_client_countdown = maxf(0.0, _client_countdown - delta)
	_update_camera(delta)


func _process(delta: float) -> void:
	if _worker:
		return
	_poll_client()
	_interpolate_remotes(delta)
	if _joined and Time.get_ticks_msec() - _last_ping_ms >= 1000:
		_last_ping_ms = Time.get_ticks_msec()
		_send({"type": "ping", "sent": _last_ping_ms})
	if Time.get_ticks_msec() - _last_hud_ms >= 100:
		_publish_hud()


func _create_vehicle(slot: int, visuals: bool) -> CharacterBody3D:
	var vehicle: CharacterBody3D = Vehicle.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1.25, 0.7, 2.1)
	collider.shape = shape
	vehicle.add_child(collider)
	# The initial network probe excludes car-to-car collision prediction.
	vehicle.collision_layer = 2
	vehicle.collision_mask = 1
	if visuals:
		vehicle.add_child(Kart.create(COLORS[slot % COLORS.size()]))
	add_child(vehicle)
	return vehicle


func _step_server(delta: float) -> void:
	_tick += 1
	if _countdown > 0:
		_countdown -= 1
	var now: int = Time.get_ticks_msec()
	for id: String in _players.keys():
		var player: Dictionary = _players[id]
		if not player["connected"] and now - int(player["disconnected_at"]) > RECONNECT_MS:
			player["vehicle"].queue_free()
			_players.erase(id)
			continue
		var queue: Array = player["queue"]
		if not queue.is_empty():
			player["input"] = queue.pop_front()
			player["ack"] = int(player["input"]["sequence"])
		var command: Dictionary = player["input"]
		if not player["connected"] or now - int(player["last_input_at"]) > INPUT_TIMEOUT_MS or _countdown > 0 or player["finished"]:
			command = Protocol.NEUTRAL
		player["vehicle"].step(command, delta)
		if _countdown == 0 and not player["finished"]:
			player["elapsed"] += delta
			_update_progress(player)
		if player["vehicle"].global_position.y < -8.0:
			_recover(player)
	if _players.is_empty():
		_countdown = -1
		_finish_count = 0
	if _tick % 3 == 0:
		_broadcast_snapshot()
	if _tick % 600 == 0:
		for jti: String in _used_tickets.keys():
			if int(_used_tickets[jti]) <= int(Time.get_unix_time_from_system()):
				_used_tickets.erase(jti)


func _on_packet(peer_id: int, data: Dictionary) -> void:
	if not _peer_players.has(peer_id):
		if data.get("type") != "join" or data.size() != 2 or not data.get("ticket") is String:
			_server.close_peer(peer_id, "join_required")
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
		"recover", "restart":
			if data.size() != 1 or Time.get_ticks_msec() - int(player["last_recover_at"]) < 1000:
				return
			player["last_recover_at"] = Time.get_ticks_msec()
			if data["type"] == "restart":
				_reset_race(player)
			else:
				_recover(player)
		_:
			_server.close_peer(peer_id, "unknown_packet")


func _join_server(peer_id: int, ticket: String) -> void:
	var claims: Dictionary = Protocol.verify_ticket(ticket, _secret, int(Time.get_unix_time_from_system()))
	if claims.is_empty() or _used_tickets.has(claims.get("jti", "")):
		_server.close_peer(peer_id, "invalid_ticket")
		return
	var id: String = claims["player_id"]
	if not _players.has(id) and _players.size() >= MAX_PLAYERS:
		_server.close_peer(peer_id, "lobby_full")
		return
	_used_tickets[claims["jti"]] = claims["expires_at"]
	if not _players.has(id):
		var occupied: Array = []
		for other: Dictionary in _players.values():
			occupied.append(other["slot"])
		var slot: int = 0
		while slot in occupied:
			slot += 1
		var vehicle: CharacterBody3D = _create_vehicle(slot, false)
		_players[id] = {"id": id, "name": claims["display_name"], "slot": slot, "vehicle": vehicle,
			"peer_id": peer_id, "connected": true, "disconnected_at": 0, "last_input_at": 0,
			"accepted": 0, "ack": 0, "queue": [], "input": Protocol.NEUTRAL.duplicate(),
			"lap": 1, "next_sector": 1, "checkpoint": 0, "finished": false, "finish_order": 0,
			"elapsed": 0.0, "last_recover_at": -1000, "epoch": 0}
		vehicle.reset_at(_track.spawn_transform(slot))
		if _countdown < 0:
			_countdown = 180
	var player: Dictionary = _players[id]
	var previous_peer: int = int(player["peer_id"])
	if previous_peer != peer_id:
		_peer_players.erase(previous_peer)
		_server.close_peer(previous_peer, "replaced")
	player["peer_id"] = peer_id
	player["connected"] = true
	player["queue"].clear()
	player["input"] = Protocol.NEUTRAL.duplicate()
	player["accepted"] = player["ack"]
	player["last_input_at"] = Time.get_ticks_msec()
	_peer_players[peer_id] = id
	_server.authenticate(peer_id)
	_server.send_to(peer_id, {"type": "welcome", "player_id": id, "protocol_version": Protocol.VERSION, "ack": player["ack"]})
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


func _update_progress(player: Dictionary) -> void:
	var sector: int = _track.sector_at(player["vehicle"].global_position)
	if sector != int(player["next_sector"]):
		return
	player["checkpoint"] = sector
	player["next_sector"] = (sector + 1) % Track.SECTORS
	if sector == 0:
		player["lap"] += 1
		if int(player["lap"]) > RACE_LAPS:
			_finish_count += 1
			player["finished"] = true
			player["finish_order"] = _finish_count


func _recover(player: Dictionary) -> void:
	var angle: float = (float(player["checkpoint"]) + 0.1) * TAU / Track.SECTORS
	var tangent: Vector3 = Vector3(-Track.RADIUS_X * sin(angle), 0.0, Track.RADIUS_Z * cos(angle)).normalized()
	var pose: Transform3D = Transform3D(Basis.looking_at(tangent, Vector3.UP), Vector3(Track.RADIUS_X * cos(angle), 0.65, Track.RADIUS_Z * sin(angle)))
	player["vehicle"].reset_at(pose)
	player["queue"].clear()
	player["input"] = Protocol.NEUTRAL.duplicate()
	player["ack"] = player["accepted"]
	player["epoch"] += 1


func _reset_race(player: Dictionary) -> void:
	player["lap"] = 1
	player["next_sector"] = 1
	player["checkpoint"] = 0
	player["finished"] = false
	player["finish_order"] = 0
	player["elapsed"] = 0.0
	_recover(player)
	player["vehicle"].reset_at(_track.spawn_transform(int(player["slot"])))


func _broadcast_snapshot() -> void:
	var standings: Array = _players.values()
	standings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["finished"] or b["finished"]:
			return int(a["finish_order"]) < int(b["finish_order"]) if a["finished"] and b["finished"] else a["finished"]
		return _race_progress(a) > _race_progress(b))
	var entries: Array = []
	for index: int in standings.size():
		var player: Dictionary = standings[index]
		entries.append({"id": player["id"], "name": player["name"], "slot": player["slot"],
			"position": index + 1, "lap": mini(RACE_LAPS, int(player["lap"])), "finished": player["finished"],
			"connected": player["connected"], "elapsed": player["elapsed"], "ack": player["ack"], "epoch": player["epoch"],
			"state": Protocol.pack_state(player["vehicle"].capture_state())})
	var packet: Dictionary = {"type": "snapshot", "tick": _tick, "countdown": maxf(0.0, float(_countdown) / 60.0), "players": entries}
	for peer_id: int in _peer_players:
		_server.send_to(peer_id, packet, true)


func _race_progress(player: Dictionary) -> float:
	var raw: float = _track.progress_at(player["vehicle"].global_position) * Track.SECTORS
	var checkpoint: int = int(player["checkpoint"])
	if checkpoint == 0 and raw > Track.SECTORS * 0.5:
		raw -= Track.SECTORS
	return float((int(player["lap"]) - 1) * Track.SECTORS + checkpoint) + clampf(raw - checkpoint, -1.0 if checkpoint == 0 else 0.0, 1.0)


func _setup_view() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	var settings: Environment = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("98d5dc")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("ddf4f1")
	settings.ambient_light_energy = 0.35
	environment.environment = settings
	add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 65.0
	_camera.far = 1200.0
	_camera.position = Vector3(95.0, 65.0, 65.0)
	add_child(_camera)
	_camera.look_at(Vector3(10.0, 0.0, 0.0))
	_camera.current = true


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
		"join":
			if data.get("url") is String and data.get("ticket") is String:
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
				_send({"type": data["type"]})


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
	for action: String in ["drive_left", "drive_right", "drive_accelerate", "drive_brake", "drive_drift"]:
		Input.action_release(action)


func _poll_client() -> void:
	if _socket == null:
		return
	_socket.poll()
	var state: int = _socket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_leave("disconnected")
		return
	if state != WebSocketPeer.STATE_OPEN:
		if Time.get_ticks_msec() - _last_server_ms > 6000:
			_leave("connection_timeout")
		return
	if not _ticket.is_empty():
		_send({"type": "join", "ticket": _ticket})
		_ticket = ""
	while _socket != null and _socket.get_available_packet_count() > 0:
		var parsed: Variant = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		if not parsed is Dictionary:
			continue
		_last_server_ms = Time.get_ticks_msec()
		match parsed.get("type"):
			"welcome":
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
		seen.append(id)
		var location: Vector3 = state["transform"].origin
		public_players.append({"id": id, "name": entry.get("name", ""), "lap": entry.get("lap", 1), "position": entry.get("position", 1), "connected": entry.get("connected", true), "worldPosition": [location.x, location.y, location.z]})
		if id == _player_id:
			if _local == null:
				_local = _create_vehicle(int(entry.get("slot", 0)), true)
			var before: Vector3 = _local.global_position
			var ack: int = int(entry.get("ack", 0))
			_pending = _pending.filter(func(command: Dictionary) -> bool: return int(command["sequence"]) > ack)
			_local.restore_state(state)
			if int(_hud.get("epoch", -1)) != int(entry.get("epoch", 0)):
				_pending.clear()
			for command: Dictionary in _pending:
				_local.step(command if _client_countdown <= 0.0 and not entry.get("finished", false) else Protocol.NEUTRAL, PHYSICS_DT)
			_correction = before.distance_to(_local.global_position)
			_hud = entry.duplicate()
			_hud.erase("state")
			_status = "finished" if entry.get("finished", false) else ("countdown" if _client_countdown > 0.0 else "racing")
		else:
			if not _remotes.has(id):
				var visual: Node3D = Kart.create(COLORS[int(entry.get("slot", 0)) % COLORS.size()])
				add_child(visual)
				visual.global_transform = state["transform"]
				_remotes[id] = {"node": visual, "samples": []}
			var samples: Array = _remotes[id]["samples"]
			samples.append({"at": Time.get_ticks_msec(), "transform": state["transform"]})
			while samples.size() > 12:
				samples.pop_front()
	for id: String in _remotes.keys():
		if id not in seen:
			_remotes[id]["node"].queue_free()
			_remotes.erase(id)
	_hud["players"] = public_players


func _interpolate_remotes(_delta: float) -> void:
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


func _update_camera(delta: float) -> void:
	if _camera == null or _local == null:
		return
	var behind: Vector3 = _local.global_basis.z
	var target: Vector3 = _local.global_position + behind * 8.0 + Vector3.UP * 4.5
	_camera.global_position = _camera.global_position.lerp(target, 1.0 - exp(-6.0 * delta))
	_camera.look_at(_local.global_position - behind * 6.0 + Vector3.UP)


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
	_hud.clear()
	_status = status
	if _local != null:
		_local.queue_free()
		_local = null
	for remote: Dictionary in _remotes.values():
		remote["node"].queue_free()
	_remotes.clear()
	_publish_hud()


func _publish_hud() -> void:
	_last_hud_ms = Time.get_ticks_msec()
	var location: Vector3 = Vector3.ZERO if _local == null else _local.global_position
	var data: Dictionary = {"status": _status, "playerId": _player_id, "players": _hud.get("players", []),
		"worldPosition": [location.x, location.y, location.z],
		"position": _hud.get("position", 1), "speed": 0.0 if _local == null else _local.speed_mps * 3.6,
		"drift": 0.0 if _local == null else _local.drift_charge, "boost": 0.0 if _local == null else _local.boost_remaining,
		"lap": _hud.get("lap", 1), "finished": _hud.get("finished", false), "elapsed": _hud.get("elapsed", 0.0),
		"countdown": _client_countdown, "ping": _ping, "correction": _correction, "serverTick": _tick,
		"pendingInputs": _pending.size(), "fps": Engine.get_frames_per_second()}
	if _bridge != null:
		_bridge.update(JSON.stringify(data))
