extends "res://race/race_session.gd"

const Track = preload("res://track/authored_track.gd")
const Transport = preload("res://net/prototype_socket_server.gd")
const Driver = preload("res://input/driver_input.gd")
const HERO_COLOR: Color = Color("2e9d99")
const PHYSICS_DT: float = 1.0 / 60.0
const INPUT_TIMEOUT_MS: int = 250
const RECONNECT_MS: int = 30000
const INTERPOLATION_DELAY_MS: int = 100
const MAX_UNACKED_INPUTS: int = 24

var _worker: bool = false
var _kart_script: Script
var _server: Node
var _secret: String = ""
var _peer_players: Dictionary = {}
var _used_tickets: Dictionary = {}
var _item_visuals: Node3D
var _item_sequence: int = 0
var _client_combat: Dictionary = {}

var _socket: WebSocketPeer
var _ticket: String = ""
var _player_id: String = ""
var _sequence: int = 0
var _input_ack: int = 0
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
var _local_race: Node3D
var _local_view: Node3D
var _local_layout: String = "side-by-side"


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
	_item_visuals = load("res://items/item_visuals.gd").new()
	add_child(_item_visuals)
	_item_visuals.set_quality(_quality)
	_item_visuals.set_reduced_effects(_reduced_effects)
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
	if is_instance_valid(_local_race):
		_local_race.step_local(delta)
		var commands: Dictionary = {}
		for seat: int in _local_race.inputs.assignments():
			commands[seat] = _local_race.command_for_seat(seat)
		_local_view.update_view(0.0 if _local_race.is_paused_local() else delta, commands)
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
			# Bound in-flight inputs below the server's 30-command queue, even after a batched delivery.
			# Item edges are sampled above; prediction must not invent unsent driving steps.
			if _sequence - _input_ack >= MAX_UNACKED_INPUTS:
				_update_camera(delta)
				return
			_sequence += 1
			command["type"] = "input"
			command["sequence"] = _sequence
			_pending.append(command)
			_send(command)
			if _local == null:
				return
		_step_local(command, delta)
		_client_countdown = maxf(0.0, _client_countdown - delta)
	_update_camera(delta)


func _process(delta: float) -> void:
	if _worker:
		return
	if is_instance_valid(_local_race):
		if Time.get_ticks_msec() - _last_hud_ms >= 100:
			_publish_hud()
		return
	_poll_client()
	_interpolate_remotes(delta)
	if is_instance_valid(_local) and is_instance_valid(_local_visual):
		_local_visual.update_visual(delta, _local.speed_mps, _local.steering_amount, _local.is_drifting, minf(1.0, _local.boost_remaining))
		_local_visual.visible = _combat_visible(_client_combat)
		if _local_visual.has_method("set_combat_visual"):
			_local_visual.set_combat_visual(_client_combat)
	if _joined and Time.get_ticks_msec() - _last_ping_ms >= 1000:
		_last_ping_ms = Time.get_ticks_msec()
		_send({"type": "ping", "sent": _last_ping_ms})
	if Time.get_ticks_msec() - _last_hud_ms >= 100:
		_publish_hud()


func _create_vehicle(_slot: int, visuals: bool) -> CharacterBody3D:
	var vehicle: CharacterBody3D = super._create_vehicle(_slot, false)
	if visuals:
		_local_visual = _create_kart_visual()
		vehicle.add_child(_local_visual)
	return vehicle


func _create_kart_visual() -> Node3D:
	if _kart_script == null:
		_kart_script = load("res://vehicle/authored_kart.gd")
	var visual: Node3D = _kart_script.create(HERO_COLOR)
	if visual.has_method("set_reduced_effects"):
		visual.set_reduced_effects(_reduced_effects)
	return visual


func _step_server(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for player: Dictionary in _players.values():
		if not player["is_bot"] and not player["connected"] and now - int(player["disconnected_at"]) > RECONNECT_MS:
			player["expired"] = true
	_step_session(delta)
	if _tick % 3 == 0:
		_broadcast_snapshot()
	if _tick % 600 == 0:
		for jti: String in _used_tickets.keys():
			if int(_used_tickets[jti]) <= int(Time.get_unix_time_from_system()):
				_used_tickets.erase(jti)


func _human_input_available(player: Dictionary) -> bool:
	return player["connected"] and Time.get_ticks_msec() - int(player["last_input_at"]) <= INPUT_TIMEOUT_MS


func _new_player(id: String, display_name: String, slot: int, bot: bool, style_id: String = Styles.DEFAULT_ID) -> Dictionary:
	var player: Dictionary = super._new_player(id, display_name, slot, bot, style_id)
	player.merge({"peer_id": 0, "disconnected_at": 0, "last_input_at": 0})
	return player


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
		"use_item":
			var item_command: Dictionary = Protocol.validate_item_command(data)
			if item_command.is_empty():
				_server.close_peer(peer_id, "invalid_item")
				return
			if item_command["race_id"] != _race_id or item_command["epoch"] != player["epoch"]:
				return
			var item_sequence: int = int(item_command["sequence"])
			if item_sequence <= int(player["item_accepted"]):
				return
			if item_sequence > int(player["item_accepted"]) + 120 or player["item_queue"].size() >= 16:
				_server.close_peer(peer_id, "invalid_item")
				return
			player["item_accepted"] = item_sequence
			if _phase == "racing" and not player["spectator"] and not player["finished"] and float(player["combat"]["health"]) > 0.0:
				player["item_queue"].append(item_command)
			else:
				player["combat"]["item_ack"] = item_sequence
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
			if _phase == "racing" and not player["finished"] and not player["spectator"] and float(player["combat"]["destroyed_remaining"]) <= 0.0:
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
		_players[id] = _new_player(id, claims["display_name"], mini(slot, MAX_PLAYERS - 1), false, claims["style_id"])
		_players[id]["peer_id"] = peer_id
		_players[id]["spectator"] = spectator
		if _countdown < 0:
			_start_race()
	var player: Dictionary = _players[id]
	# A fresh ticket may request the next build, never rewrite an active race.
	player["next_style_id"] = claims["style_id"]
	var previous_peer: int = int(player["peer_id"])
	if previous_peer != peer_id:
		_peer_players.erase(previous_peer)
		_server.close_peer(previous_peer, "replaced")
	player["peer_id"] = peer_id
	player["connected"] = true
	player["expired"] = false
	player["queue"].clear()
	player["item_queue"].clear()
	player["combat"]["item_ack"] = player["item_accepted"]
	player["input"] = Protocol.BLOCKED.duplicate()
	player["accepted"] = player["ack"]
	player["last_input_at"] = Time.get_ticks_msec()
	_peer_players[peer_id] = id
	_server.authenticate(peer_id)
	_server.send_to(peer_id, {"type": "welcome", "player_id": id, "compatibility": Protocol.compatibility(_track.identity()), "ack": player["ack"], "item_ack": player["combat"]["item_ack"]})
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
		player["item_queue"].clear()
		player["combat"]["item_ack"] = player["item_accepted"]
		player["input"] = Protocol.BLOCKED.duplicate()


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
			"combat": _items.player_state(player), "driving": Techniques.presentation(player),
			"style_id": player["style_id"], "next_style_id": player["next_style_id"],
			"position": 0 if player["spectator"] else index + 1, "lap": mini(RACE_LAPS, int(player["lap"])), "finished": player["finished"],
			"is_bot": player["is_bot"], "spectator": player["spectator"], "ready": player["ready"], "dnf": player["dnf"],
			"connected": player["connected"], "elapsed": player["elapsed"], "ack": player["ack"], "epoch": player["epoch"],
			"state": Protocol.pack_state(player["vehicle"].capture_state())})
	var packet: Dictionary = {"type": "snapshot", "tick": _tick, "race_id": _race_id, "phase": _phase,
		"track_event": _track_event.snapshot(),
		"items_world": _items.world_state(),
		"finish_remaining": _finish_remaining, "race_remaining": maxf(0.0, 180.0 - _race_elapsed),
		"countdown": maxf(0.0, float(_countdown) / 60.0), "players": entries}
	for peer_id: int in _peer_players:
		packet["items_world"] = _items.world_state(_peer_players[peer_id])
		_server.send_to(peer_id, packet, true)


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
	if is_instance_valid(_local_view):
		_local_view.set_quality(quality, reduced_effects)
	if is_instance_valid(_item_visuals):
		_item_visuals.set_quality(quality)
		_item_visuals.set_reduced_effects(reduced_effects)
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
	if command["use_item_1"]:
		_use_item(0)
	if command["use_item_2"]:
		_use_item(1)
	for key: String in ["use_item_1", "use_item_2", "look_back"]:
		command.erase(key)
	return command


func _use_item(slot: int) -> void:
	if not _joined or not _can_drive() or not _focused or not _input_enabled or slot not in [0, 1]:
		return
	_item_sequence += 1
	_send({"type": "use_item", "sequence": _item_sequence, "race_id": _race_id, "epoch": _hud.get("epoch", 0), "slot": slot})


func _step_local(command: Dictionary, delta: float) -> void:
	if not _client_combat.is_empty():
		_local.configure(_items.effects_stats({"combat": _client_combat}, Styles.stats_for(_hud.get("style_id", Styles.DEFAULT_ID))))
	if float(_client_combat.get("destroyed_remaining", 0.0)) > 0.0:
		_local.velocity = Vector3.ZERO
		_local.speed_mps = 0.0
	else:
		_local.step(command if _can_drive() and _focused and _input_enabled else Protocol.BLOCKED, delta)
	# Only duration-based movement is predicted. Health, inventory and revival stay authoritative.
	var effects: Dictionary = _client_combat.get("effects", {})
	for effect: String in effects.keys():
		effects[effect]["remaining"] = maxf(0.0, float(effects[effect]["remaining"]) - delta)
		if effects[effect]["remaining"] <= 0.0:
			effects.erase(effect)


func _combat_visible(combat: Dictionary) -> bool:
	if float(combat.get("destroyed_remaining", 0.0)) > 0.0:
		return false
	return _reduced_effects or float(combat.get("invulnerable_remaining", 0.0)) <= 0.0 or Time.get_ticks_msec() % 400 < 280


func _on_host_message(arguments: Array) -> void:
	if arguments.is_empty():
		return
	var parsed: Variant = JSON.parse_string(str(arguments[0]))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	if str(data.get("type", "")).begins_with("local_"):
		_on_local_message(data)
		return
	match data.get("type"):
		"use_item":
			if Protocol._integer(data.get("slot"), 0) and int(data["slot"]) <= 1:
				_use_item(int(data["slot"]))
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
			if is_instance_valid(_local_race):
				_local_race.set_focused(_focused)
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
	for action: String in ["drive_left", "drive_right", "drive_accelerate", "drive_brake", "drive_drift", "look_back", "use_item_1", "use_item_2"]:
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
				_input_ack = _sequence
				_item_sequence = int(parsed.get("item_ack", 0))
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
	var item_world: Dictionary = Protocol.validate_items_world(packet.get("items_world"))
	if item_world.is_empty() or not TrackEvent.validate_snapshot(packet.get("track_event")):
		_leave("update_required")
		return
	if int(packet.track_event.trigger_tick) > server_tick:
		_leave("update_required")
		return
	for entry: Variant in packet["players"]:
		if not entry is Dictionary or Protocol.validate_driving(entry.get("driving")).is_empty() or Protocol.validate_combat(entry.get("combat")).is_empty():
			_leave("update_required")
			return
	_tick = server_tick
	_track.apply_event(packet.track_event)
	var generation_changed: bool = _race_id != int(packet.get("race_id", 0))
	_race_id = int(packet.get("race_id", 0))
	_phase = str(packet.get("phase", "waiting"))
	_finish_remaining = float(packet.get("finish_remaining", -1.0))
	_race_elapsed = 180.0 - float(packet.get("race_remaining", 180.0))
	_client_countdown = float(packet.get("countdown", 0.0))
	if is_instance_valid(_item_visuals):
		if generation_changed:
			_item_visuals.clear()
		_item_visuals.apply_world(item_world)
	var public_players: Array = []
	var seen: Array[String] = []
	for entry: Variant in packet["players"]:
		if not entry is Dictionary or not entry.get("state") is Dictionary:
			continue
		if not Styles.is_valid(entry.get("style_id")):
			_leave("update_required")
			return
		if Protocol.validate_combat(entry.get("combat")).is_empty():
			_leave("update_required")
			return
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
			_client_combat = entry["combat"].duplicate(true)
			_item_sequence = maxi(_item_sequence, int(_client_combat["item_ack"]))
			var before: Vector3 = _local.global_position
			var ack: int = int(entry.get("ack", 0))
			_input_ack = maxi(_input_ack, mini(ack, _sequence))
			_pending = _pending.filter(func(command: Dictionary) -> bool: return int(command["sequence"]) > ack)
			_local.restore_state(state)
			var epoch_changed: bool = int(_hud.get("epoch", -1)) != int(entry.get("epoch", 0))
			if epoch_changed or generation_changed:
				_pending.clear()
			_hud = entry.duplicate(true)
			_hud.erase("state")
			for command: Dictionary in _pending:
				_step_local(command, PHYSICS_DT)
			_local.configure(_items.effects_stats({"combat": _client_combat}, Styles.stats_for(entry["style_id"])))
			if (epoch_changed or generation_changed) and _race_camera != null:
				_race_camera.reset(_local)
			_correction = before.distance_to(_local.global_position)
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
				_remotes[id].erase("near_pose")
				_remotes[id].erase("near_sample_at")
				_remotes[id].erase("near_lead")
				_remotes[id]["node"].global_transform = state["transform"]
			_remotes[id]["epoch"] = int(entry.get("epoch", 0))
			_remotes[id]["combat"] = entry["combat"].duplicate(true)
			samples.append({"at": Time.get_ticks_msec(), "tick": server_tick, "transform": state["transform"],
				"velocity": state["velocity"],
				"speed": state["velocity"].slide(state["up_direction"]).length(), "steering": state["steering_amount"],
				"drifting": state["is_drifting"], "boost": state["boost_remaining"]})
			while samples.size() > 12:
				samples.pop_front()
	for id: String in _remotes.keys():
		if id not in seen:
			_remotes[id]["node"].queue_free()
			_remotes.erase(id)
	_hud["players"] = public_players
	_hud["track_event"] = packet.track_event.duplicate(true)
	_hud["attack_warning"] = _attack_warning(item_world, _player_id, _local) if _can_drive() else ""


func _can_drive() -> bool:
	return _status == "practice" or (_phase == "racing" and not _hud.get("finished", false) and not _hud.get("spectator", false) and float(_client_combat.get("destroyed_remaining", 0.0)) <= 0.0)


func _presentation_time_msec() -> int:
	return Time.get_ticks_msec()


func _interpolate_remotes(delta: float) -> void:
	var now: int = _presentation_time_msec()
	var target: int = now - INTERPOLATION_DELAY_MS
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
		var motion: Dictionary = samples[0]
		if _local != null:
			var newest: Dictionary = samples.back()
			var current: Transform3D = newest["transform"]
			var distance: float = current.origin.distance_to(_local.global_position)
			var proximity: float = 1.0 - smoothstep(12.0, 20.0, distance)
			if proximity > 0.0:
				# Capture prediction lead once per snapshot; the live pending count has
				# an acknowledgement sawtooth that must never move remote visuals.
				var age: float = maxf(0.0, float(now - int(newest["at"])) / 1000.0)
				var sample_at: int = int(newest["at"])
				var measured_lead: float = minf(0.1, _pending.size() * PHYSICS_DT)
				if not remote.has("near_sample_at"):
					remote["near_lead"] = measured_lead
				elif int(remote["near_sample_at"]) != sample_at:
					var interval: float = maxf(0.0, float(sample_at - int(remote["near_sample_at"])) / 1000.0)
					remote["near_lead"] = lerpf(float(remote["near_lead"]), measured_lead, 1.0 - exp(-interval / 0.3))
				remote["near_sample_at"] = sample_at
				var horizon: float = minf(0.1, age + float(remote["near_lead"]))
				var velocity: Vector3 = newest.get("velocity", Vector3.ZERO)
				current.origin += velocity * horizon
				var angular_axis := Vector3.UP
				var angular_speed: float = 0.0
				if samples.size() > 1:
					var older: Dictionary = samples[-2]
					var seconds: float = float(int(newest.get("tick", 0)) - int(older.get("tick", 0))) * PHYSICS_DT
					if seconds > 0.0:
						var rotation_delta: Quaternion = current.basis.get_rotation_quaternion() * Transform3D(older["transform"]).basis.get_rotation_quaternion().inverse()
						if rotation_delta.w < 0.0:
							rotation_delta = -rotation_delta
						if rotation_delta.get_angle() > 0.0001:
							angular_axis = rotation_delta.get_axis()
							angular_speed = minf(6.0, rotation_delta.get_angle() / seconds)
				current.basis = Basis(Quaternion(angular_axis, angular_speed * horizon)) * current.basis
				if remote.has("near_pose"):
					var predicted: Transform3D = remote["near_pose"]
					# Feed forward motion and smooth only correction, avoiding positional
					# lerp lag. Unknown future impacts still remain server-authoritative.
					if age < 0.1:
						predicted.origin += velocity * delta
						predicted.basis = Basis(Quaternion(angular_axis, angular_speed * delta)) * predicted.basis
					if predicted.origin.distance_to(current.origin) < 4.0:
						current = predicted.interpolate_with(current, 1.0 - exp(-delta / 0.06))
				remote["near_pose"] = current
				result = result.interpolate_with(current, proximity)
				motion = newest
			else:
				remote.erase("near_pose")
				remote.erase("near_sample_at")
				remote.erase("near_lead")
		remote["node"].global_transform = result
		remote["node"].visible = _combat_visible(remote.get("combat", {}))
		if remote["node"].has_method("set_combat_visual"):
			remote["node"].set_combat_visual(remote.get("combat", {}))
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
	_track_event.reset()
	if is_instance_valid(_track):
		_track.apply_event(_track_event.snapshot())
	if is_instance_valid(_local_view):
		_local_view.free()
		_local_view = null
	if is_instance_valid(_local_race):
		_local_race.free()
		_local_race = null
	if is_instance_valid(_camera):
		_camera.current = true
	if _socket != null:
		_socket.close()
	_socket = null
	_ticket = ""
	_joined = false
	_pending.clear()
	_queued_snapshot.clear()
	_player_id = ""
	_sequence = 0
	_input_ack = 0
	_item_sequence = 0
	_client_combat.clear()
	if is_instance_valid(_item_visuals):
		_item_visuals.clear()
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
	if is_instance_valid(_local_race):
		var local_state: Dictionary = _local_hud_state()
		local_state["mode"] = "local"
		local_state["layout"] = _local_layout
		local_state["devices"] = _local_devices()
		local_state["sectors"] = _local_view.sectors()
		local_state["graphics"] = {"quality": _quality, "reducedEffects": _reduced_effects}
		local_state["fps"] = Engine.get_frames_per_second()
		if _bridge != null:
			_bridge.update(JSON.stringify(local_state))
		return
	var location: Vector3 = Vector3.ZERO if _local == null else _local.global_position
	var forward: Vector3 = Vector3.FORWARD if _local == null else -_local.global_basis.z
	var data: Dictionary = {"status": _status, "playerId": _player_id, "players": _hud.get("players", []),
		"trackEvent": _hud.get("track_event", _track_event.snapshot()),
		"items": _client_combat.get("slots", ["", ""]), "health": _client_combat.get("health", 100.0), "maxHealth": _client_combat.get("max_health", 100.0),
		"shards": _client_combat.get("shards", 0), "shardCap": _items.Catalog.SHARD_CAP,
		"driving": _hud.get("driving", {}),
		"attackWarning": _hud.get("attack_warning", "") if _can_drive() else "",
		"effects": _client_combat.get("effects", {}), "itemAck": _client_combat.get("item_ack", 0),
		"destroyedRemaining": _client_combat.get("destroyed_remaining", 0.0), "invulnerableRemaining": _client_combat.get("invulnerable_remaining", 0.0),
		"canUseItems": _joined and _can_drive() and _focused and _input_enabled,
		"blurIntensity": _blur_intensity(),
		"styleId": _hud.get("style_id", Styles.DEFAULT_ID), "nextStyleId": _hud.get("next_style_id", Styles.DEFAULT_ID),
		"raceId": _race_id, "phase": _phase, "spectating": _hud.get("spectator", false),
		"repeatReady": _hud.get("ready", false), "dnf": _hud.get("dnf", false),
		"canRestart": _phase == "results" and not _hud.get("ready", false) and not _hud.get("spectator", false),
		"finishRemaining": _finish_remaining, "raceRemaining": maxf(0.0, 180.0 - _race_elapsed),
		"graphics": {"quality": _quality, "reducedEffects": _reduced_effects, "renderScale": get_viewport().scaling_3d_scale},
		"track": _track.descriptor() if _track != null else {},
		"worldPosition": [location.x, location.y, location.z],
		"forward": [forward.x, forward.y, forward.z],
		"position": _hud.get("position", 1), "speed": 0.0 if _local == null else _local.speed_mps * 3.6,
		"reverse": _local != null and _local.velocity.dot(-_local.global_basis.z) < -0.1,
		"drift": 0.0 if _local == null else _local.drift_charge, "boost": 0.0 if _local == null else _local.boost_remaining,
		"driftLevel": 0 if _local == null else _local.drift_level(),
		"driftSegments": _drift_segments(0.0 if _local == null else _local.drift_charge),
		"lap": _hud.get("lap", 1), "finished": _hud.get("finished", false), "elapsed": _hud.get("elapsed", 0.0),
		"countdown": _client_countdown, "ping": _ping, "correction": _correction, "serverTick": _tick,
		"pendingInputs": _pending.size(), "fps": Engine.get_frames_per_second()}
	if _bridge != null:
		_bridge.update(JSON.stringify(data))


func _blur_intensity() -> float:
	return _items.blur_intensity(_client_combat)


func _drift_segments(charge: float) -> Array:
	var segments: Array = []
	var previous: float = 0.0
	for threshold: float in Vehicle.DRIFT_LEVEL_THRESHOLDS:
		segments.append(clampf((charge - previous) / (threshold - previous), 0.0, 1.0))
		previous = threshold
	return segments


func _attack_warning(world: Dictionary, player_id: String, vehicle: Node3D) -> String:
	if not is_instance_valid(vehicle):
		return ""
	var closest: float = INF
	var direction: String = ""
	for projectile: Dictionary in world.get("projectiles", []):
		if projectile.get("kind") != "seeker" or projectile.get("target", "") != player_id:
			continue
		var point: Array = projectile.position
		var offset: Vector3 = Vector3(point[0], point[1], point[2]) - vehicle.global_position
		if offset.length_squared() >= closest:
			continue
		closest = offset.length_squared()
		var forward: float = offset.dot(-vehicle.global_basis.z)
		var right: float = offset.dot(vehicle.global_basis.x)
		direction = ("front" if forward >= 0.0 else "rear") if absf(forward) >= absf(right) else ("right" if right >= 0.0 else "left")
	return direction


func _local_devices() -> Array:
	var devices: Array = [{"id": -1, "name": "Keyboard"}]
	for device: int in Input.get_connected_joypads():
		devices.append({"id": device, "name": Input.get_joy_name(device)})
	return devices


func _local_hud_state() -> Dictionary:
	var snapshot: Dictionary = _local_race.presentation()
	var players: Array = []
	var seats: Array = []
	for entry: Dictionary in snapshot.players:
		var vehicle: CharacterBody3D = _local_race._players[entry.id].vehicle
		var location: Vector3 = vehicle.global_position
		var row: Dictionary = {"id": entry.id, "name": entry.name, "rank": entry.position,
			"position": [location.x, location.z], "worldPosition": [location.x, location.y, location.z],
			"isBot": entry.is_bot, "finished": entry.finished, "dnf": entry.dnf,
			"elapsed": entry.elapsed, "ready": entry.ready, "seat": entry.slot}
		players.append(row)
		if entry.is_bot:
			continue
		var combat: Dictionary = entry.combat
		var seat: Dictionary = row.duplicate()
		seat.merge({"device": snapshot.devices[entry.slot], "styleId": entry.style_id,
			"controls": snapshot.controls[entry.slot],
			"attackWarning": _attack_warning(snapshot.items_world, entry.id, vehicle) if not entry.finished and float(combat.destroyed_remaining) <= 0.0 else "",
			"shards": combat.shards, "shardCap": _items.Catalog.SHARD_CAP, "driving": entry.driving,
			"speed": vehicle.speed_mps * 3.6, "lap": entry.lap, "laps": RACE_LAPS,
			"reverse": vehicle.velocity.dot(-vehicle.global_basis.z) < -0.1,
			"health": combat.health, "maxHealth": combat.max_health, "items": combat.slots,
			"effects": combat.effects, "drift": vehicle.drift_charge, "boost": vehicle.boost_remaining,
			"driftLevel": vehicle.drift_level(),
			"driftSegments": _drift_segments(vehicle.drift_charge),
			"epoch": entry.epoch, "lookBack": _local_race.command_for_seat(entry.slot).get("look_back", false),
			"canUseItems": snapshot.phase == "racing" and not snapshot.paused and not entry.finished and float(combat.destroyed_remaining) <= 0.0,
			"blurIntensity": _local_race._items.blur_intensity(combat),
			"destroyedRemaining": combat.destroyed_remaining, "invulnerableRemaining": combat.invulnerable_remaining})
		seats.append(seat)
	seats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.seat) < int(b.seat))
	return {"seats": seats, "players": players, "paused": snapshot.paused, "botDifficulty": snapshot.bot_difficulty,
		"trackEvent": snapshot.track_event,
		"tutorial": snapshot.get("tutorial", {}),
		"disconnected": snapshot.disconnected_seats, "pauseReason": snapshot.pause_reason,
		"countdown": snapshot.countdown, "status": snapshot.phase, "phase": snapshot.phase,
		"raceId": snapshot.race_id, "tick": snapshot.tick, "trackDescriptor": _track.descriptor()}


func _on_local_message(data: Dictionary) -> void:
	var action: String = str(data.get("type", ""))
	if action == "local_devices":
		if _bridge != null:
			_bridge.update(JSON.stringify({"mode": "local_devices", "devices": _local_devices()}))
		return
	if action == "local_start":
		if not data.get("seats") is Array or data.get("layout", "side-by-side") not in ["side-by-side", "stacked"]:
			return
		if not data.get("tutorial", false) is bool:
			return
		var candidate: Node3D = load("res://race/driving_tutorial.gd" if data.get("tutorial", false) else "res://race/local_race_session.gd").new()
		add_child(candidate)
		candidate.configure(_track)
		candidate.set_focused(_focused)
		if not candidate.start_local(data["seats"], null, str(data.get("botDifficulty", "normal"))):
			candidate.free()
			if _bridge != null:
				_bridge.update(JSON.stringify({"mode": "local_error", "error": "devices_unavailable"}))
			return
		_leave("ready")
		_local_race = candidate
		_local_layout = data.get("layout", "side-by-side")
		_local_view = load("res://view/local_race_view.gd").new()
		_local_race.add_child(_local_view)
		_camera.current = false
		_local_view.configure(_local_race, _local_layout)
		_local_view.set_quality(_quality, _reduced_effects)
		_publish_hud()
		return
	if action == "local_leave":
		_leave("ready")
		return
	if not is_instance_valid(_local_race):
		return
	var seat: int = int(data.get("seat", -1))
	match action:
		"local_controls":
			if _local_race.is_paused_local():
				_local_race.inputs.configure_profile(seat, data.get("controls", {}))
		"local_tutorial_retry":
			if _local_race.has_method("restart_lesson"):
				_local_race.restart_lesson()
		"local_pause":
			_local_race.pause_local()
		"local_resume":
			_local_race.resume_local()
		"local_recover":
			if _local_race.resume_local():
				_local_race.recover_seat(seat)
		"local_ready":
			_local_race.ready_seat(seat)
		"local_assign":
			_local_race.assign_device(seat, int(data.get("device", -2)))
		"local_use_item":
			_local_race.use_item_seat(seat, int(data.get("slot", -1)))
	_publish_hud()
