extends SceneTree

const Items = preload("res://items/race_items.gd")
const Catalog = preload("res://items/item_catalog.gd")

class TestTrack extends Node3D:
	func standings_distance(progress: Dictionary, _position: Vector3) -> float:
		return float(progress.distance)

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _player(id: String, slot: int, bot: bool, world: Node3D, items: RefCounted) -> Dictionary:
	var body := CharacterBody3D.new()
	world.add_child(body)
	var result: Dictionary = {"id": id, "slot": slot, "is_bot": bot, "vehicle": body, "progress": {"distance": 0.0}}
	items.init_player(result)
	return result


func _run() -> void:
	var track := TestTrack.new()
	root.add_child(track)
	var items := Items.new()
	items.reset({}, track)
	items._pickups = [{"id": 1, "position": Vector3.ZERO}]
	var human: Dictionary = _player("human", 1, false, track, items)
	var bot: Dictionary = _player("bot", 0, true, track, items)
	var players: Dictionary = {"human": human, "bot": bot}
	items.step(players, 0.0)
	_check(bot.combat.slots[0] != "" and human.combat.slots[0] == "", "one atomic winner, no human-first dictionary privilege")
	_check(items.world_state("human") == items.world_state("bot") and items.world_state() == items.world_state("human"), "all recipients observe identical gift world")
	_check(items._cooldowns["1"] == 2.0, "successful collection starts exactly two simulation seconds")
	items.step(players, 0.0)
	_check(items._cooldowns["1"] == 2.0 and bot.combat.slots[1] == "", "zero-delta pause does not age or duplicate collected gift")
	items.step(players, 1.99)
	_check(human.combat.slots[0] == "" and not items.world_state().pickups[0].available, "no early availability")
	bot.vehicle.position = Vector3(10, 0, 0)
	items.step(players, 0.011)
	_check(human.combat.slots[0] != "" and not items.world_state().pickups[0].available, "another racer collects after respawn")
	items.step(players, 2.0)
	_check(human.combat.slots[1] != "", "previous recipient can collect the same gift again")
	items.step(players, 2.0)
	_check(items.world_state().pickups[0].available, "full inventory leaves respawned gift visible")
	_check(items._cooldowns["1"] == 0.0, "full inventory never restarts cooldown")
	bot.vehicle.position = Vector3.ZERO
	items.step(players, 0.0)
	_check(bot.combat.slots[1] != "", "full racer does not block eligible competitor")
	items._cooldowns.clear()
	items.init_player(human)
	items.init_player(bot)
	bot.vehicle.position = Vector3(1, 0, 0)
	items.step({"bot": bot, "human": human}, 0.0)
	_check(human.combat.slots[0] != "" and bot.combat.slots[0] == "", "nearest recipient wins independent of role, slot, insertion order")
	var leader: Dictionary = Catalog.loot_weights(1, 10, 0.0)
	var tail_close: Dictionary = Catalog.loot_weights(10, 10, 0.0)
	var tail_far: Dictionary = Catalog.loot_weights(10, 10, 150.0)
	_check(tail_close.fanta > leader.fanta and tail_far.fanta > tail_close.fanta, "both rank and leader gap softly influence weights")
	_check(Catalog.loot_weights(10, 10, 1500.0) == tail_far, "leader-gap influence is capped")
	for id: String in Catalog.IDS:
		_check(float(leader[id]) > 0.0 and float(tail_far[id]) >= 0.9 and float(tail_far[id]) <= 1.4, "%s remains possible within soft bounds" % id)
	human.progress.distance = 80.0
	bot.progress.distance = 180.0
	var context: Dictionary = items._loot_context(human, players)
	_check(context == {"place": 2, "racers": 2, "gap": 100.0}, "route standings determine exact rank and physical leader gap")
	human.is_bot = true
	bot.is_bot = false
	_check(items._loot_context(human, players) == context, "changing racer type does not change distribution context")
	var other := Items.new()
	items._rng.seed = 20260927
	other._rng.seed = 20260927
	var seen: Dictionary = {}
	var equal_draws: bool = true
	for index: int in 1000:
		var chosen: String = items._draw_item(tail_far)
		equal_draws = equal_draws and chosen == other._draw_item(tail_far)
		seen[chosen] = true
	_check(equal_draws, "seeded weighted draws are reproducible")
	_check(seen.size() == Catalog.IDS.size(), "even last place can receive every item, not a guaranteed attack")
	items.reset(players, track)
	_check(items._cooldowns.is_empty() and items._events.is_empty(), "repeat clears old gift cooldowns and pickup events")
	_check(human.combat.slots == ["", ""] and bot.combat.slots == ["", ""], "repeat resets both inventories")
	items._pickups = [{"id": 1, "position": Vector3.ZERO}]
	_check(items.world_state().pickups[0].available, "same gift ID starts available in next race")
	track.free()
	print("GIFTS_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
