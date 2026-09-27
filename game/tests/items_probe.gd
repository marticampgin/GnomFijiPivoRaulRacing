extends SceneTree

const Items = preload("res://items/race_items.gd")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)


func _player(id: String, position: Vector3, world: Node3D, items: RefCounted) -> Dictionary:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.position = position
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.18, 0.7, 2.696)
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	var player: Dictionary = {"id": id, "vehicle": body, "finished": false, "spectator": false}
	items.init_player(player)
	return player


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var items := Items.new()
	items.reset({}, world)
	var a: Dictionary = _player("a", Vector3.ZERO, world, items)
	var b: Dictionary = _player("b", Vector3(3, 0, 0), world, items)
	var players: Dictionary = {"a": a, "b": b}
	await physics_frame
	a.combat.slots = ["fanta", "ice_rum"]
	a.combat.health = 60.0
	_check(items.use(a, 0, players) and items.use(a, 1, players), "two slots usable immediately")
	_check(not items.use(a, 0, players), "empty slot cannot repeat")
	_check(a.combat.health == 75.0, "ice repairs 15")
	var base: Dictionary = {"top_speed": 30.0, "acceleration": 20.0}
	_check(is_equal_approx(items.effects_stats(a, base).top_speed, 39.0), "speed buffs strongest wins")
	_check(base.top_speed == 30.0, "base stats unchanged")
	items.step(players, 2.0)
	a.combat.slots[0] = "fanta"
	items.use(a, 0, players)
	_check(a.combat.effects.fanta.remaining == 4.0, "same buff refreshes duration")
	_check(is_equal_approx(items.effects_stats(a, base).top_speed, 39.0), "same buff does not stack")
	a.combat.slots[0] = "mermaid_rum"
	items.use(a, 0, players)
	_check(a.combat.health == 100.0, "repair clamps to max health")
	_check(a.combat.effects.mermaid_rum.remaining == 4.0, "mermaid blur duration")
	_check(Items.blur_intensity(a.combat) == 0.5, "strongest active blur wins")
	_check(Items.blur_intensity({"effects": {"mermaid_rum": {"remaining": 1.0}}}) == 0.2, "mermaid blur from catalog")
	_check(Items.blur_intensity({"effects": {"ice_rum": {"remaining": 0.0}}}) == 0.0, "expired blur is absent")
	a.combat.slots[0] = "lays_crab"
	items.use(a, 0, players)
	items.apply_damage(b, 20.0, a)
	_check(is_equal_approx(b.combat.health, 77.0), "chips increases damage15percent")
	items.apply_damage(b, -10.0)
	_check(is_equal_approx(b.combat.health, 77.0), "negative damage cannot repair")
	items.apply_damage(b, 1000.0)
	_check(b.combat.health == 0.0 and b.combat.destroyed_remaining == 2.0, "lethal damage clamps and schedules destruction")
	_check(items.step(players, 1.0).is_empty(), "no early restoration")
	_check(items.step(players, 1.0) == ["b"], "restoration due once")
	_check(items.step(players, 0.1).is_empty(), "restoration not repeated")
	b.combat.item_ack = 42
	items.restore(b)
	_check(b.combat.health == 100.0 and b.combat.slots == ["", ""] and b.combat.item_ack == 42, "restore resets combat preserves ack")
	items.apply_damage(b, 50.0)
	_check(b.combat.health == 100.0, "spawn immunity prevents damage")
	items.step(players, 2.0)
	items.apply_damage(b, 20.0)
	_check(b.combat.health == 80.0, "immunity expires")
	items.step(players, 10.0)
	_check(a.combat.effects.is_empty(), "all timed effects expire")
	items._pickups = [{"id": 1, "position": Vector3.ZERO}]
	a.combat.slots = ["fanta", "ice_rum"]
	items.step(players, 0.01)
	_check(a.combat.slots == ["fanta", "ice_rum"], "full slots never replaced")
	a.combat.slots = ["", ""]
	items.step(players, 0.01)
	_check(a.combat.slots[0] != "" and a.combat.slots[1] == "", "pickup fills first free slot")
	_check(not items.world_state("a").pickups[0].available, "collector snapshot hides cooling pickup")
	_check(not items.world_state("b").pickups[0].available and not items.world_state().pickups[0].available, "pickup unavailable globally")
	items.step(players, 0.01)
	_check(a.combat.slots[1] == "", "same pickup cooldown")
	b.vehicle.position = Vector3.ZERO
	items.step(players, 0.01)
	_check(b.combat.slots[0] == "", "another racer cannot collect during global cooldown")
	a.combat.slots = ["fanta", "ice_rum"]
	items.step(players, 2.0)
	_check(b.combat.slots[0] != "", "another racer collects after two seconds")
	b.combat.slots = ["fanta", "ice_rum"]
	items.step(players, 2.0)
	_check(items.world_state("a").pickups[0].available, "global pickup available after two seconds")
	_check(a.combat.slots == ["fanta", "ice_rum"], "cooldown expiry never replaces full slots")
	items._pickups.clear()
	b.vehicle.position = Vector3(0, 10, 0)
	var explosion: Dictionary = {"kind": "bfg10k", "position": Vector3(0, 0.35, 0), "damage_multiplier": 1.0}
	items._explode(explosion, players)
	_check(a.combat.health == 45.0, "BFG damages owner too")
	_check(b.combat.health == 80.0, "height outside sphere immune")
	items.restore(a)
	a.combat.invulnerable_remaining = 0.0
	b.vehicle.position = Vector3(3, 0, 0)
	items._explode({"kind": "stroh80", "position": Vector3(0, 0.35, 0), "damage_multiplier": 1.0}, players)
	_check(a.combat.health == 75.0 and a.combat.effects.burn.remaining == 4.0, "Stroh blast and burn")
	items.step(players, 0.5)
	_check(a.combat.health == 72.5, "burn integrates fixed delta")
	items.restore(a)
	items._explode({"kind": "stroh80", "position": Vector3(0, 0.35, 0), "damage_multiplier": 1.0}, players)
	_check(not a.combat.effects.has("burn"), "immunity also prevents burn application")
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 6.0, 8.0)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(1.5, 0, 0)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	b.combat.health = 100.0
	items._explode(explosion, players)
	_check(b.combat.health == 100.0, "wall blocks explosion damage")
	_check(not items._line_of_sight(Vector3.ZERO, Vector3(3, 0, 0)), "static geometry LOS enforced")
	wall.rotation.z = PI / 2.0
	wall.position = Vector3(0, 2, 0)
	b.vehicle.position = Vector3(0, 4, 0)
	await physics_frame
	await physics_frame
	items._explode(explosion, players)
	_check(b.combat.health == 100.0, "stacked road blocks blast within radius")
	a.combat.slots = ["stroh80", "bfg10k"]
	items.use(a, 0, players)
	items.use(a, 1, players)
	_check(items.world_state().projectiles.size() == 2, "both attack items launch projectiles")
	_check(JSON.stringify(items.world_state()).contains("projectiles"), "world snapshot JSON serializable")
	items.reset(players, world)
	_check(items.world_state().projectiles.is_empty() and items.world_state().events.is_empty(), "race reset clears world")
	_check(a.combat.health == 100.0 and a.combat.effects.is_empty(), "race reset clears effects")
	wall.position = Vector3(100, 0, 0)
	b.vehicle.position = Vector3(0, 0, -6)
	await physics_frame
	await physics_frame
	a.combat.slots[0] = "bfg10k"
	items.use(a, 0, players)
	for frame: int in range(12):
		items.step(players, 1.0 / 60.0)
	_check(b.combat.health == 45.0, "BFG swept ray actually strikes kart collider")
	_check(a.combat.health == 45.0, "near BFG impact damages shooter")
	_check(items.world_state().projectiles.is_empty(), "projectile consumed at first hit")
	items.restore(a)
	items.restore(b)
	a.combat.invulnerable_remaining = 0.0
	b.combat.invulnerable_remaining = 0.0
	a.finished = true
	b.spectator = true
	a.combat.slots[0] = "fanta"
	_check(not items.use(a, 0, players), "finished racer cannot activate item")
	items._explode(explosion, players)
	_check(a.combat.health == 100.0 and b.combat.health == 100.0, "finished and spectator immune to attacks")
	print("ITEMS_PROBE checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures else 0)
