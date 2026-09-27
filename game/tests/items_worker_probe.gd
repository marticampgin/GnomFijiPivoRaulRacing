extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Protocol = preload("res://net/prototype_protocol.gd")
const DT: float = 1.0 / 60.0

class TestWorker extends "res://app/prototype.gd":
	var requested: int = 0
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		if requested > 0:
			requested -= 1
			_step_server(DT)
	func _broadcast_snapshot() -> void:
		pass

class FakeServer extends Node:
	var packet: Dictionary = {}
	var reason: String = ""
	func authenticate(_peer: int) -> void:
		pass
	func send_to(_peer: int, data: Dictionary, _disposable: bool = false) -> void:
		packet = data
	func close_peer(_peer: int, value: String) -> void:
		reason = value

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _step(worker: TestWorker, count: int = 1) -> void:
	worker.requested = count
	while worker.requested > 0:
		await physics_frame
		await process_frame

func _command(worker: TestWorker, player: Dictionary, sequence: int) -> Dictionary:
	return {"type": "use_item", "sequence": sequence, "race_id": worker._race_id, "epoch": player.epoch}

func _run() -> void:
	var worker := TestWorker.new()
	root.add_child(worker)
	worker.set_process(false)
	worker._server = FakeServer.new()
	worker.add_child(worker._server)
	worker._track = Track.new()
	worker.add_child(worker._track)
	worker._track.build(false)
	worker._secret = "item-worker-test-secret-at-least-32-characters"
	var player: Dictionary = worker._new_player("probe", "Probe", 0, false)
	player.peer_id = 1
	worker._players = {"probe": player}
	worker._peer_players = {1: "probe"}
	worker._race_id = 1
	worker._phase = "racing"
	worker._countdown = 0
	await physics_frame
	await process_frame
	player.combat.slots = ["fanta", "mermaid_rum"]
	player.combat.health = 40.0
	var first: Dictionary = _command(worker, player, 1)
	worker._on_packet(1, first)
	_check(player.combat.slots == ["fanta", "mermaid_rum"], "socket does not mutate inventory outside physics")
	await _step(worker)
	_check(player.combat.slots == ["mermaid_rum", ""] and player.combat.item_ack == 1, "single command consumes only oldest item")
	worker._on_packet(1, first)
	await _step(worker)
	_check(player.combat.slots == ["mermaid_rum", ""] and player.combat.health == 40.0, "repeated first command cannot consume shifted reserve")
	worker._on_packet(1, _command(worker, player, 2))
	await _step(worker)
	_check(player.combat.slots == ["", ""] and player.combat.item_ack == 2, "second distinct command consumes reserve after advancement")
	_check(player.combat.effects.has("fanta") and player.combat.effects.has("mermaid_rum") and player.combat.health > 40.0, "boost and repair effects coexist")
	player.combat.slots[0] = "lays_crab"
	worker._on_packet(1, first)
	await _step(worker)
	_check(player.combat.slots[0] == "lays_crab" and not player.combat.effects.has("lays_crab"), "duplicate cannot spend subsequently refilled slot")
	for key: String in ["race_id", "epoch"]:
		var stale: Dictionary = _command(worker, player, 3)
		stale[key] += 1
		worker._on_packet(1, stale)
	await _step(worker)
	_check(player.combat.item_ack == 2 and player.combat.slots[0] == "lays_crab", "stale race and recovery commands cannot spend inventory")
	worker._phase = "countdown"
	worker._countdown = 1
	worker._on_packet(1, _command(worker, player, 3))
	await _step(worker)
	_check(worker._phase == "racing" and player.combat.item_ack == 3 and player.combat.slots[0] == "lays_crab", "prestart command cannot cross countdown boundary and activate")
	var preserved: Dictionary = player.combat.duplicate(true)
	worker._on_disconnect(1)
	worker._join_server(2, _ticket(worker))
	_check(player.connected and player.peer_id == 2 and player.combat == preserved, "signed reconnect preserves durability inventory and effects")
	_check(worker._server.packet.get("item_ack") == 3, "reconnect welcome preserves item acknowledgement")
	var old_epoch: int = player.epoch
	worker._on_packet(2, {"type": "recover"})
	_check(player.epoch == old_epoch + 1 and player.combat == preserved, "manual recovery cannot heal or remove effects/items")
	var gate: int = player.progress.expected_gate
	var lap: int = player.lap
	worker._items.apply_damage(player, 1000.0)
	_check(player.combat.health == 0.0 and player.combat.destroyed_remaining == 2.0, "lethal hit schedules two-second recovery")
	old_epoch = player.epoch
	player.last_recover_at = -1000
	worker._on_packet(2, {"type": "recover"})
	_check(player.epoch == old_epoch and player.combat.health == 0.0, "manual recovery cannot bypass destruction delay")
	await _step(worker, 119)
	_check(player.epoch == old_epoch and player.combat.health == 0.0, "destroyed kart remains disabled before two seconds")
	await _step(worker, 2)
	_check(player.epoch == old_epoch + 1 and player.combat.health == 100.0 and player.combat.invulnerable_remaining > 1.9, "scheduled recovery restores durability with spawn protection")
	_check(player.progress.expected_gate == gate and player.lap == lap and not player.finished and worker._finish_count == 0, "destruction recovery preserves checkpoint progress without fabricated finish")
	_check(player.combat.slots == ["", ""] and player.combat.effects.is_empty() and player.combat.item_ack == 3, "destruction clears inventory/effects without rewinding sequence")
	player.combat.slots = ["stroh80", "fanta"]
	worker._items.use_next(player, worker._players)
	worker._items.use_next(player, worker._players)
	_check(not worker._items.world_state().projectiles.is_empty(), "repeat fixture contains active projectile")
	worker._start_race()
	_check(worker._race_id == 2 and worker._phase == "countdown" and worker._players.size() == 10, "repeat resets generation and refills ten racers")
	_check(player.combat.health == 100.0 and player.combat.slots == ["", ""] and player.combat.effects.is_empty(), "repeat clears damage inventory and buffs")
	_check(player.combat.item_ack == 3 and player.item_accepted == 3 and player.item_queue.is_empty(), "repeat preserves item sequence monotonicity and clears queue")
	var world: Dictionary = worker._items.world_state()
	_check(world.projectiles.is_empty() and world.events.is_empty() and world.pickups.size() == 24, "repeat removes prior projectiles/events and rebuilds pickups")
	worker._phase = "racing"
	worker._countdown = 0
	player.combat.slots = ["fanta", "ice_rum"]
	worker._on_packet(2, _command(worker, player, 4))
	worker._on_packet(2, _command(worker, player, 5))
	await _step(worker)
	var use_events: Array = worker._items.world_state().events.filter(func(event: Dictionary) -> bool: return str(event.kind).begins_with("use_"))
	_check(player.combat.slots == ["", ""] and player.combat.item_ack == 5, "two distinct buffered presses consume two items")
	_check(use_events.size() == 2 and use_events[0].kind == "use_fanta" and use_events[1].kind == "use_ice_rum", "buffered commands preserve oldest first activation order")
	worker.free()
	print("ITEMS_WORKER_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)

func _ticket(worker: TestWorker) -> String:
	var claims: Dictionary = Protocol.compatibility(worker._track.identity())
	claims.merge({"v": Protocol.TICKET_VERSION, "style_id": "handling", "match_id": Protocol.MATCH_ID, "expires_at": int(Time.get_unix_time_from_system()) + 60, "player_id": "probe", "display_name": "Probe", "jti": "items-worker-reconnect"})
	var payload: String = _base64url(JSON.stringify(claims).to_utf8_buffer())
	var context := HMACContext.new()
	context.start(HashingContext.HASH_SHA256, worker._secret.to_utf8_buffer())
	context.update(payload.to_utf8_buffer())
	return payload + "." + _base64url(context.finish())

func _base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
