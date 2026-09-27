extends SceneTree

const Protocol = preload("res://net/prototype_protocol.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Transport = preload("res://net/prototype_socket_server.gd")
const Track = preload("res://track/authored_track.gd")

class TestClient extends "res://app/prototype.gd":
	var applied_in_physics: bool = false

	func _ready() -> void:
		pass

	func _apply_snapshot(packet: Dictionary) -> void:
		applied_in_physics = Engine.is_in_physics_frame()
		super._apply_snapshot(packet)

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 120
	var source: CharacterBody3D = Vehicle.new()
	root.add_child(source)
	source.global_position = Vector3(42.0, 3.0, 1.0)
	var state: Dictionary = Protocol.pack_state(source.capture_state())
	source.free()
	var connection: Dictionary = {"peer_id": -1}
	var track: Node3D = Track.new()
	var compatibility: Dictionary = Protocol.compatibility(track.descriptor())
	var server: Node = Transport.new()
	root.add_child(server)
	var port: int = int(OS.get_environment("NETWORK_RESUME_TEST_PORT")) if OS.has_environment("NETWORK_RESUME_TEST_PORT") else 19081
	if server.listen(port) != OK:
		push_error("Resume probe needs available loopback port %d" % port)
		server.queue_free()
		track.free()
		quit(1)
		return
	server.received.connect(func(peer_id: int, packet: Dictionary) -> void:
		if packet.get("type") == "join":
			connection["peer_id"] = peer_id
			server.authenticate(peer_id)
			server.send_to(peer_id, {"type": "welcome", "player_id": "probe", "ack": 0, "compatibility": compatibility})
			server.send_to(peer_id, _snapshot(30, 0, state)))
	var client: TestClient = TestClient.new()
	client._kart_script = load("res://vehicle/prototype_kart.gd")
	client._track = track
	root.add_child(client)
	client._connect_client("ws://127.0.0.1:%d" % port, "test-only-fake-server")
	for attempt: int in 100:
		if client._joined and client._local != null:
			break
		await create_timer(0.02).timeout
	_check(client._joined and client._local != null, "real WebSocket handshake initializes client")
	if client._joined:
		client.set_process(false)
		client.set_physics_process(false)
		client._last_server_ms = Time.get_ticks_msec() - 7000
		server.send_to(int(connection["peer_id"]), _snapshot(33, client._sequence, state))
		await create_timer(0.05).timeout
		_check(client._tick == 30, "suspended client has not applied incoming socket data")
		client.set_physics_process(true)
		await physics_frame
		await process_frame
		_check(client._joined and client._local != null, "fresh queued bytes prevent false disconnect after resume")
		_check(client._tick == 33 and Time.get_ticks_msec() - client._last_server_ms < 1000, "socket drains before timeout and consumes fresh snapshot")
		_check(client.applied_in_physics, "resumed socket snapshot still applies only in physics callback")
	client._leave("ready")
	client.queue_free()
	track.free()
	server.queue_free()
	await process_frame
	print("NETWORK_RESUME_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _snapshot(tick: int, ack: int, state: Dictionary) -> Dictionary:
	return {"type": "snapshot", "tick": tick, "countdown": 0.0, "players": [{"id": "probe", "slot": 0, "ack": ack, "epoch": 0, "style_id": "handling", "state": state}]}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
