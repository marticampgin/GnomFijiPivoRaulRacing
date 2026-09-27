extends SceneTree

const Protocol = preload("res://net/prototype_protocol.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const DT: float = 1.0 / 60.0

class TestClient extends "res://app/prototype.gd":
	func _ready() -> void:
		pass

	func _physics_process(_delta: float) -> void:
		if not _queued_snapshot.is_empty():
			var packet: Dictionary = _queued_snapshot
			_queued_snapshot = {}
			_apply_snapshot(packet)

	func _create_vehicle(_slot: int, _visuals: bool) -> CharacterBody3D:
		var body: CharacterBody3D = Vehicle.new()
		body.collision_layer = 2
		body.collision_mask = 1
		var collider := CollisionShape3D.new()
		collider.shape = Vehicle.create_collision_shape()
		body.add_child(collider)
		add_child(body)
		return body

	func _create_kart_visual() -> Node3D:
		return Node3D.new()

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var client := TestClient.new()
	root.add_child(client)
	client.set_process(false)
	client._joined = true
	client._player_id = "contact-probe"
	var source: CharacterBody3D = Vehicle.new()
	source.configure(preload("res://vehicle/driving_styles.gd").stats_for("handling"))
	root.add_child(source)
	source.global_position = Vector3(10.0, 30.0, 10.0)
	# A server impact has already changed velocity, including a lateral component.
	source.velocity = Vector3(4.0, 0.0, -13.0)
	var state: Dictionary = Protocol.pack_state(source.capture_state())
	client._queue_snapshot(_snapshot(3, 1, 0, 1, state))
	await physics_frame
	await process_frame
	_check(client._local != null, "collision snapshot creates local vehicle")
	if client._local == null:
		quit(1)
		return
	_check(client._local.velocity.is_equal_approx(source.velocity), "authoritative collision velocity is restored exactly")
	_check(client._local.collision_mask == 1, "client prediction never enables pair collision mask")
	_check(client._remotes["other"]["node"] is Node3D and not client._remotes["other"]["node"] is PhysicsBody3D, "overlapping remote remains visual-only")
	var restored: Transform3D = client._local.global_transform
	client._queue_snapshot(_snapshot(3, 1, 0, 1, state))
	client._queue_snapshot(_snapshot(2, 1, 0, 1, state))
	await physics_frame
	await process_frame
	_check(client._queued_snapshot.is_empty() and client._tick == 3, "duplicate and stale collision snapshots are ignored")
	_check(client._local.velocity.is_equal_approx(source.velocity) and client._local.global_transform.is_equal_approx(restored), "ignored snapshots do not apply impact twice")

	var command: Dictionary = {"type": "input", "sequence": 2, "steering": 0.2, "throttle": 1.0, "brake": 0.0, "drift": false}
	client._pending = [command.duplicate(), command.duplicate()]
	client._pending[0]["sequence"] = 1
	client._sequence = 2
	client._queue_snapshot(_snapshot(6, 1, 1, 1, state))
	await physics_frame
	# Reference replay uses exactly the authoritative post-impact state once.
	source.restore_state(Protocol.unpack_state(state))
	source.step(command, DT)
	await process_frame
	_check(client._pending.size() == 1 and client._pending[0]["sequence"] == 2, "collision reconciliation removes acknowledged input")
	_check(client._local.velocity.is_equal_approx(source.velocity), "unacknowledged replay starts from post-impact velocity once")
	_check(client._local.global_transform.is_equal_approx(source.global_transform), "replay position matches one ordinary vehicle step")
	var replayed_velocity: Vector3 = client._local.velocity
	client._queue_snapshot(_snapshot(6, 1, 1, 1, state))
	await physics_frame
	await process_frame
	_check(client._local.velocity.is_equal_approx(replayed_velocity), "duplicate snapshot cannot replay the remaining command again")

	client._pending = [command.duplicate()]
	client._remotes["other"]["near_pose"] = Transform3D.IDENTITY
	client._remotes["other"]["near_sample_at"] = 0
	client._remotes["other"]["near_lead"] = 0.1
	client._queue_snapshot(_snapshot(9, 1, 1, 2, state))
	await physics_frame
	await process_frame
	_check(client._pending.is_empty(), "recovery epoch clears pre-impact pending input")
	_check(not client._remotes["other"].has("near_pose") and not client._remotes["other"].has("near_lead"), "recovery epoch clears remote presentation correction history")
	_check(client._local.velocity.is_equal_approx(Protocol.unpack_state(state)["velocity"]), "recovery does not replay old collision inputs")
	client._pending = [command.duplicate()]
	client._remotes["other"]["near_pose"] = Transform3D.IDENTITY
	client._remotes["other"]["near_sample_at"] = 0
	client._remotes["other"]["near_lead"] = 0.1
	client._queue_snapshot(_snapshot(12, 2, 1, 2, state))
	await physics_frame
	await process_frame
	_check(client._pending.is_empty(), "new race generation clears old pending input even with unchanged epoch")
	_check(client._remotes["other"]["samples"].size() == 1, "new generation drops old remote interpolation samples")
	_check(not client._remotes["other"].has("near_pose") and not client._remotes["other"].has("near_lead"), "new generation clears remote presentation correction history")
	_check(client._local.velocity.is_equal_approx(Protocol.unpack_state(state)["velocity"]), "new generation does not carry collision replay across races")
	client.free()
	source.free()
	print("CONTACT_RECONCILIATION_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _snapshot(tick: int, generation: int, ack: int, epoch: int, state: Dictionary) -> Dictionary:
	return {"type": "snapshot", "tick": tick, "race_id": generation, "phase": "racing", "countdown": 0.0, "players": [
		{"id": "contact-probe", "slot": 0, "ack": ack, "epoch": epoch, "style_id": "handling", "state": state},
		{"id": "other", "slot": 1, "epoch": epoch, "style_id": "handling", "state": state},
	]}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
