extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Protocol = preload("res://net/prototype_protocol.gd")
const DT: float = 1.0 / 60.0

class CheckedDriver extends "res://ai/racing_bot_driver.gd":
	var invalid_commands: int = 0
	func sample(vehicle: CharacterBody3D, progress: Dictionary, delta: float) -> Dictionary:
		var command: Dictionary = super.sample(vehicle, progress, delta)
		var packet: Dictionary = command.duplicate()
		packet.merge({"type": "input", "sequence": 1})
		if Protocol.validate_input(packet).is_empty():
			invalid_commands += 1
		return command

class TestRace extends "res://app/prototype.gd":
	var running: bool = false
	var recoveries: int = 0
	var finishes: Dictionary = {}
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		if running and _phase == "racing":
			_step_server(DT)
	func _broadcast_snapshot() -> void:
		pass
	func _human_count() -> int:
		return 1
	func _recover(player: Dictionary) -> bool:
		var recovered: bool = super._recover(player)
		if running and recovered:
			recoveries += 1
		return recovered
	func _update_progress(player: Dictionary) -> void:
		var was_finished: bool = player.finished
		super._update_progress(player)
		if not was_finished and player.finished:
			finishes[player.id] = int(finishes.get(player.id, 0)) + 1

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var race := TestRace.new()
	root.add_child(race)
	race.set_process(false)
	race._track = Track.new()
	race.add_child(race._track)
	race._track.build(false)
	race._start_race()
	for player: Dictionary in race._players.values():
		player.driver = CheckedDriver.new(race._track, int(player.slot))
	race._countdown = 0
	race._phase = "racing"
	# Lock only the test RNG so a failed combat race can be reproduced.
	race._items._rng.seed = 20260927
	var event_ids: Dictionary = {}
	var projectile_ids: Dictionary = {}
	var uses: Dictionary = {}
	var destructions: int = 0
	var health_changes: int = 0
	var last_health: Dictionary = {}
	var invalid_states: int = 0
	var invalid_commands: int = 0
	await physics_frame
	await process_frame
	race.running = true
	while race._phase == "racing" and race._tick < 10810:
		await physics_frame
		await process_frame
		var world: Dictionary = race._items.world_state()
		for event: Dictionary in world.events:
			if event_ids.has(event.id):
				continue
			event_ids[event.id] = true
			if str(event.kind).begins_with("use_"):
				uses[event.kind] = int(uses.get(event.kind, 0)) + 1
			elif event.kind == "destroyed":
				destructions += 1
		for projectile: Dictionary in world.projectiles:
			projectile_ids[projectile.id] = true
		for player: Dictionary in race._players.values():
			# Validate the JSON wire representation, not Godot-native StringName keys.
			var wire: Dictionary = JSON.parse_string(JSON.stringify({"combat": player.combat, "state": Protocol.pack_state(player.vehicle.capture_state())}))
			if Protocol.validate_combat(wire.combat).is_empty() or Protocol.unpack_state(wire.state).is_empty():
				if invalid_states == 0:
					print("ITEMS_RACE_FIRST_INVALID tick=%d wire=%s" % [race._tick, JSON.stringify(wire)])
				invalid_states += 1
			if last_health.has(player.id) and not is_equal_approx(float(last_health[player.id]), float(player.combat.health)):
				health_changes += 1
			last_health[player.id] = player.combat.health
		race.running = race._phase == "racing"
	_check(race._phase == "results", "integrated worker terminates the race")
	_check(race._players.size() == 10 and race._finish_count == 10, "all ten bots finish integrated items race")
	var orders: Dictionary = {}
	for player: Dictionary in race._players.values():
		invalid_commands += int(player.driver.invalid_commands)
		_check(player.finished and not player.dnf and player.lap == 4 and int(race.finishes.get(player.id, 0)) == 1, "%s completes three checkpoint-counted laps exactly once (lap=%d gate=%d epoch=%d)" % [player.id, player.lap, player.progress.expected_gate, player.epoch])
		orders[player.finish_order] = true
	_check(orders.size() == 10 and not orders.has(0), "finish order is unique for ten racers")
	_check(invalid_states == 0, "every combat and vehicle snapshot stays finite and protocol-valid")
	_check(invalid_commands == 0, "all bot commands stay within validated input range")
	_check(not uses.is_empty() and not projectile_ids.is_empty() and health_changes > 0, "full race actually exercises consumables projectiles and durability")
	print("ITEMS_RACE_METRICS seconds=%.2f ticks=%d finishes=%d recoveries=%d destructions=%d projectiles=%d health_changes=%d uses=%s" % [race._race_elapsed, race._tick, race._finish_count, race.recoveries, destructions, projectile_ids.size(), health_changes, JSON.stringify(uses)])
	race.free()
	print("ITEMS_RACE_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
