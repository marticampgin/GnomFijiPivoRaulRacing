extends SceneTree

const Protocol = preload("res://net/prototype_protocol.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Track = preload("res://track/authored_track.gd")

class TestClient extends "res://app/prototype.gd":
	var applied_in_physics: bool = false
	var waiting_packet: Dictionary = {}

	func _ready() -> void:
		pass

	func _apply_snapshot(packet: Dictionary) -> void:
		applied_in_physics = Engine.is_in_physics_frame()
		super._apply_snapshot(packet)

	func _poll_client() -> void:
		if not waiting_packet.is_empty():
			_last_server_ms = Time.get_ticks_msec()
			_queue_snapshot(waiting_packet)
			waiting_packet = {}
		super._poll_client()

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source: CharacterBody3D = Vehicle.new()
	root.add_child(source)
	source.global_position = Vector3(12.0, 3.0, 1.0)
	var state: Dictionary = Protocol.pack_state(source.capture_state())
	source.free()
	var client: TestClient = TestClient.new()
	# This fixture overrides the normal client resource warm-up.
	client._kart_script = load("res://vehicle/prototype_kart.gd")
	var track: Node3D = Track.new()
	client._track = track
	root.add_child(client)
	client._joined = true
	client._player_id = "probe"
	client._last_server_ms = Time.get_ticks_msec()
	client._queue_snapshot({"type": "snapshot", "tick": 9, "countdown": 0.0, "players": [{"id": "probe", "slot": 0, "ack": 0, "epoch": 0, "style_id": "handling", "state": state}]})
	_check(client._tick == 0 and client._local == null, "receive does not mutate physics body")
	client._queue_snapshot({"type": "snapshot", "tick": 6, "countdown": 0.0, "players": []})
	_check(client._queued_snapshot.get("tick") == 9, "buffer keeps latest snapshot")
	await physics_frame
	await process_frame
	_check(client.applied_in_physics, "restore and replay execute inside physics callback")
	_check(client._tick == 9 and client._local != null, "physics consumes queued snapshot")
	_check(is_equal_approx(client._local.stats["handling"], 1.18), "client uses authoritative handling profile before replay")
	if client._local == null:
		client.free()
		track.free()
		quit(1)
		return
	_check(is_equal_approx(client._local.global_position.x, 12.0), "authoritative transform restored")
	_check(client._queued_snapshot.is_empty(), "snapshot consumed once")
	client._pending = [{"type": "input", "sequence": 1, "steering": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false}, {"type": "input", "sequence": 2, "steering": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false}]
	client._sequence = 2
	client._queue_snapshot({"type": "snapshot", "tick": 12, "countdown": 0.0, "players": [{"id": "probe", "slot": 0, "ack": 1, "epoch": 0, "style_id": "handling", "state": state}]})
	await physics_frame
	await process_frame
	_check(client._pending.all(func(command: Dictionary) -> bool: return int(command["sequence"]) > 1), "acknowledged commands removed before replay")
	_check(client._pending.any(func(command: Dictionary) -> bool: return int(command["sequence"]) == 2), "unacknowledged command retained and replayed")
	client.set_process(false)
	client._last_server_ms = Time.get_ticks_msec() - 7000
	client.waiting_packet = {"type": "snapshot", "tick": 15, "countdown": 0.0, "players": [{"id": "probe", "slot": 0, "ack": client._sequence, "epoch": 0, "style_id": "handling", "state": state}]}
	await physics_frame
	await process_frame
	_check(client._joined and client._local != null, "resumed physics polls waiting packet before stale timeout")
	_check(client._tick == 15 and client.waiting_packet.is_empty(), "resumed physics applies freshly received snapshot")
	var falling_state: Dictionary = state.duplicate(true)
	falling_state["velocity"] = [0.0, -20.0, 0.0]
	var moving_state: Dictionary = state.duplicate(true)
	moving_state["velocity"] = [3.0, -20.0, 4.0]
	client._queue_snapshot({"type": "snapshot", "tick": 16, "countdown": 0.0, "players": [
		{"id": "probe", "slot": 0, "ack": client._sequence, "epoch": 0, "style_id": "handling", "state": state},
		{"id": "falling", "slot": 1, "style_id": "handling", "state": falling_state},
		{"id": "moving", "slot": 2, "style_id": "handling", "state": moving_state},
	]})
	await physics_frame
	await process_frame
	_check(client._remotes.has("falling") and is_zero_approx(client._remotes["falling"]["samples"].back()["speed"]), "vertical-only remote velocity does not rotate wheels")
	_check(client._remotes.has("moving") and is_equal_approx(client._remotes["moving"]["samples"].back()["speed"], 5.0), "remote wheel speed uses planar 3-4-5 velocity only")
	client._queue_snapshot({"type": "snapshot", "tick": 8, "players": []})
	_check(client._queued_snapshot.is_empty(), "stale snapshot ignored after application")
	client._queue_snapshot({"type": "snapshot", "tick": 18, "players": []})
	client._leave("ready")
	_check(client._queued_snapshot.is_empty(), "leave clears pending snapshot")
	Input.action_press("look_back")
	client._on_host_message([JSON.stringify({"type": "focus", "visible": false})])
	client._on_host_message([JSON.stringify({"type": "focus", "visible": true})])
	_check(not Input.is_action_pressed("look_back"), "focus loss releases rear view before returning")
	Input.action_press("look_back")
	client._on_host_message([JSON.stringify({"type": "input_enabled", "enabled": false})])
	client._on_host_message([JSON.stringify({"type": "input_enabled", "enabled": true})])
	_check(not Input.is_action_pressed("look_back"), "closing a menu does not retain rear view")
	client.queue_free()
	track.free()
	await process_frame
	print("NETWORK_CLIENT_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
