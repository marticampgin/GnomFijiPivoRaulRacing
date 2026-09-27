extends SceneTree

const Items = preload("res://items/race_items.gd")
const Catalog = preload("res://items/item_catalog.gd")
const Visuals = preload("res://items/item_visuals.gd")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _player(id: String, world: Node3D, items: RefCounted) -> Dictionary:
	var body := CharacterBody3D.new()
	world.add_child(body)
	var result: Dictionary = {"id": id, "vehicle": body}
	items.init_player(result)
	return result


func _shard(id: int, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"id": id, "position": position, "scattered": false, "remaining": 0.0, "arm": 0.0}


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var items := Items.new()
	items.reset({}, world)
	var a: Dictionary = _player("a", world, items)
	var b: Dictionary = _player("b", world, items)
	var players: Dictionary = {"b": b, "a": a}
	items._shards = [_shard(1)]
	a.combat.health = 50.0
	a.combat.slots = ["fanta", "ice_rum"]
	items.step(players, 0.0)
	_check(a.combat.shards == 1 and b.combat.shards == 0, "shared shard has one deterministic recipient")
	_check(a.combat.slots == ["fanta", "ice_rum"] and a.combat.health == 50.0, "shard ignores inventory and never heals")
	_check(a.combat.effects.is_empty(), "collecting does not apply instant boost or stun")
	_check(not items.world_state().shards[0].available, "collected static shard disappears globally")
	items.step(players, 0.0)
	_check(a.combat.shards == 1 and items._shards[0].remaining == 5.0, "paused simulation freezes shard respawn")
	a.vehicle.position = Vector3(20, 0, 0)
	items.step(players, 5.0)
	_check(b.combat.shards == 1, "static shard respawns for another racer")
	var base: Dictionary = {"top_speed": 30.0, "acceleration": 20.0}
	var previous: float = 30.0
	for stock: int in range(21):
		a.combat.shards = stock
		var stats: Dictionary = items.effects_stats(a, base)
		_check(stats.top_speed >= previous and stats.top_speed <= 33.00001 and stats.acceleration == 20.0, "stock %d only increases capped top speed" % stock)
		previous = stats.top_speed
	_check(is_equal_approx(previous, 33.0) and base.top_speed == 30.0, "cap gives ten percent without mutating style stats")
	a.vehicle.position = Vector3.ZERO
	b.vehicle.position = Vector3(20, 0, 0)
	items._shards = [_shard(2)]
	items.step(players, 0.0)
	_check(a.combat.shards == 20 and items.world_state().shards[0].available, "at cap leaves collectible available for others")
	items._shards.clear()
	items.apply_damage(a, 5.0, {}, "contact")
	_check(a.combat.shards == 20, "light contact loses no shards")
	items.apply_damage(a, 12.0, {}, "contact")
	_check(a.combat.shards == 15 and items._shards.size() == 2, "strong contact loses quarter and scatters half of loss")
	_check(not items.world_state().shards[0].available and items.world_state().shards[0].scattered, "scattered shards have a short visible arming interval")
	var scatter_position: Vector3 = items._shards[0].position
	b.vehicle.position = scatter_position
	items.step(players, 0.49)
	_check(b.combat.shards == 1, "scattered shards cannot be instantly recaptured")
	items.step(players, 0.02)
	_check(b.combat.shards == 2, "opponent can collect scattered shard")
	a.vehicle.position = items._shards[0].position
	items.step(players, 0.0)
	_check(a.combat.shards == 16, "former owner can recover scattered shard too")
	items.apply_damage(a, 1.0)
	_check(a.combat.shards == 12, "weapon hit loses shards")
	var count: int = a.combat.shards
	items.apply_damage(a, 1.0, {}, "burn")
	_check(a.combat.shards == count, "ongoing burn does not repeatedly scatter stock")
	a.combat.invulnerable_remaining = 1.0
	items.apply_damage(a, 50.0)
	_check(a.combat.shards == count, "blocked hit causes no shard loss")
	a.combat.invulnerable_remaining = 0.0
	a.combat.shards = 1
	a.combat.effects.erase("weapon_guard")
	items.apply_damage(a, 1.0)
	_check(a.combat.shards == 0 and a.combat.destroyed_remaining == 0.0 and a.combat.effects.size() == 1 and a.combat.effects.has("weapon_guard"), "zero shards causes no additional stun or destruction")
	a.combat.shards = 20
	a.combat.effects.erase("weapon_guard")
	items.apply_damage(a, 1000.0)
	_check(a.combat.shards == 0 and a.combat.health == 0.0, "destruction always zeroes stock")
	a.vehicle.position = Vector3(100, 0, 0)
	b.vehicle.position = Vector3(100, 0, 0)
	items.step(players, 8.0)
	_check(items._shards.is_empty(), "uncollected scatter expires")
	items.restore(a)
	a.combat.invulnerable_remaining = 0.0
	a.combat.shards = 20
	items._explode({"kind": "bfg10k", "position": a.vehicle.position + Vector3.UP * 0.35, "damage_multiplier": 1.0}, {"a": a})
	_check(a.combat.shards == 15, "self splash follows the same weapon loss rule")
	var visuals := Visuals.new()
	world.add_child(visuals)
	visuals.set_process(false)
	visuals.apply_world(items.world_state())
	_check(visuals._shards.size() == items._shards.size() and visuals._shards.size() > 0, "world shards create turquoise 3D visuals")
	for node: Node3D in visuals._shards.values():
		_check(node.get_child_count() == 2 and node.visible, "unarmed scattered crystal renders both faceted halves")
	visuals.set_reduced_effects(true)
	visuals._process(0.1)
	items.reset(players, world)
	visuals.apply_world(items.world_state())
	_check(a.combat.shards == 0 and b.combat.shards == 0 and items._shards.is_empty(), "new race resets stock and scattered world state")
	_check(visuals._shards.is_empty(), "visual synchronization removes expired/reset shards")
	for index: int in range(254):
		items._shards.append(_shard(1000 + index, Vector3(50, 0, 0)))
	a.combat.shards = 20
	items.apply_damage(a, 1000.0)
	_check(items._shards.size() == Catalog.SHARD_WORLD_LIMIT, "scatter respects bounded world snapshot size")
	world.free()
	print("SHARDS_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
