extends SceneTree

const Items = preload("res://items/race_items.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)


func racer(id: String, position: Vector3, world: Node3D, items: RefCounted) -> Dictionary:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.18, 0.7, 2.696)
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	var player := {"id": id, "vehicle": body}
	items.init_player(player)
	return player


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var items := Items.new()
	items.reset({}, world)
	var a: Dictionary = racer("a", Vector3.ZERO, world, items)
	var b: Dictionary = racer("b", Vector3(0, 0, -15), world, items)
	var c: Dictionary = racer("c", Vector3(40, 0, 0), world, items)
	var players := {"c": c, "b": b, "a": a}
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200, 0.2, 200)
	floor_collision.shape = floor_box
	floor_body.add_child(floor_collision)
	floor_body.position.y = -0.1
	world.add_child(floor_body)
	await physics_frame
	await physics_frame
	for id: String in ["crystal_shield", "seeker", "rear_trap"]:
		check(items.Catalog.IDS.has(id), "new item belongs to loot catalog: " + id)
		check(items.Catalog.loot_weights(1, 10, 0)[id] > 0.0, "new item available to leader: " + id)
		check(items.Catalog.loot_weights(10, 10, 150)[id] > 0.0, "new item available to last place: " + id)
	a.combat.slots = ["crystal_shield", "mermaid_rum"]
	a.combat.health = 60.0
	a.combat.shards = 20
	a.combat.effects.burn = {"remaining": 4.0, "damage": 5.0}
	check(items.use_next(a, players), "shield usable from queue head")
	check(a.combat.slots == ["mermaid_rum", ""], "shield advances reserve to current item")
	check(a.combat.effects.has("burn"), "shield does not cleanse existing burn")
	check(not items.apply_damage(a, 25.0), "shield blocks new weapon damage")
	check(a.combat.health == 60.0 and a.combat.shards == 20, "blocked weapon loses no health or shards")
	items._explode({"kind": "stroh80", "position": a.vehicle.position, "damage_multiplier": 1.0}, players)
	check(a.combat.effects.burn.remaining == 4.0, "shield blocks refresh of incoming burn")
	items.step(players, 0.5)
	check(a.combat.health == 57.5, "existing burn ticks through shield")
	check(items.apply_damage(a, 5, {}, "contact") and a.combat.health == 52.5, "shield does not block contact")
	items.use_next(a, players)
	check(a.combat.health == 100 and a.combat.effects.has("mermaid_rum"), "shield permits voluntary healing and blur")
	check(a.combat.effects.has("burn"), "repair does not cleanse burn")
	var snapshot: Dictionary = items.player_state(a)
	items.step(players, 0.0)
	check(items.player_state(a) == snapshot, "zero simulation time freezes shield and burn")
	items.step(players, 4.5)
	check(not a.combat.effects.has("crystal_shield"), "shield expires")
	a.combat.slots = ["fanta", "rear_trap"]
	check(items.apply_damage(a, 1.0), "unshielded direct hit applies")
	check(a.combat.effects.has("weapon_guard"), "direct hit grants short protection")
	var health: float = a.combat.health
	check(not items.apply_damage(a, 20), "post-hit guard blocks repeated direct attack")
	check(items.apply_damage(a, 1, {}, "burn") and a.combat.health == health - 1, "post-hit guard permits existing burn tick")
	check(items.apply_damage(a, 1, {}, "contact"), "post-hit guard does not block collision")
	check(a.combat.slots == ["fanta", "rear_trap"], "incoming attacks never mutate inventory")
	items.step(players, 0.75)
	check(items.apply_damage(a, 1), "post-hit guard expires")
	items.reset(players, world)
	a.combat.slots = ["seeker", "bfg10k"]
	check(items.use_next(a, players), "seeker fires from inventory")
	var projectile: Dictionary = items._projectiles[0]
	check(projectile.target == "b", "seeker selects visible racer ahead")
	check(items.world_state().projectiles[0].target == "b", "warning target included in shared snapshot immediately")
	var origin: Vector3 = projectile.position
	items.step(players, 0.64)
	check(b.combat.health == 100 and projectile.position == origin, "warning interval prevents damage and delays launch")
	items.step(players, 0.0)
	check(projectile.age == 0.64, "pause freezes projectile arming")
	for tick: int in range(40):
		items.step(players, 1.0 / 60.0)
	check(b.combat.health == 70.0, "seeker hits undefended target after warning")
	check(items._projectiles.is_empty(), "seeker removed after impact")
	items.reset(players, world)
	a.combat.slots[0] = "seeker"
	items.use_next(a, players)
	items.step(players, 0.64)
	b.vehicle.position = Vector3(24, 0, -15)
	await physics_frame
	await physics_frame
	for tick: int in range(250):
		b.vehicle.position.x += 0.5
		items.step(players, 1.0 / 60.0)
	check(b.combat.health == 100 and items._projectiles.is_empty(), "target can evade by moving laterally after warning")
	items.reset(players, world)
	b.vehicle.position = Vector3(0, 0, -15)
	a.combat.slots[0] = "seeker"
	items.use_next(a, players)
	projectile = items._projectiles[0]
	var before: Vector3 = projectile.velocity.normalized()
	b.vehicle.position = Vector3(20, 0, -15)
	items.step(players, 0.1)
	check(before.angle_to(projectile.velocity.normalized()) <= 0.12001, "seeker turning rate is bounded and dodgeable")
	b.connected = false
	items.step(players, 0.1)
	check(projectile.target == "", "disconnect clears warning and lock")
	b.connected = true
	items.step(players, 0.1)
	check(projectile.target == "", "seeker does not retarget without a fresh warning")
	items.step(players, 4.0)
	check(items._projectiles.is_empty() and b.combat.health == 100, "missed seeker expires without area explosion")
	for flag: String in ["finished", "spectator", "expired"]:
		items.reset(players, world)
		b.vehicle.position = Vector3(0, 0, -15)
		a.combat.slots[0] = "seeker"
		items.use_next(a, players)
		projectile = items._projectiles[0]
		b[flag] = true
		items.step(players, 0.01)
		check(projectile.target == "", "target lifecycle clears " + flag)
		b[flag] = false
	items.reset(players, world)
	a.combat.slots[0] = "seeker"
	items.use_next(a, players)
	projectile = items._projectiles[0]
	b.combat.health = 0.0
	items.step(players, 0.01)
	check(projectile.target == "", "destroyed target releases lock")
	items.reset(players, world)
	a.combat.slots[0] = "seeker"
	items.use_next(a, players)
	projectile = items._projectiles[0]
	items.step({"a": a, "c": c}, 0.01)
	check(projectile.target == "", "removed target releases lock without failure")
	items.reset(players, world)
	a.combat.effects.crystal_shield = {"remaining": 5.0}
	items._explode({"kind": "stroh80", "position": a.vehicle.position, "damage_multiplier": 1.0}, players)
	check(a.combat.health == 100 and not a.combat.effects.has("burn"), "shield prevents new negative status")
	items.apply_damage(a, 1000, {}, "contact")
	check(a.combat.health == 1 and a.combat.effects.has("crystal_shield"), "physical contact bypasses shield but cannot destroy or clear effects")
	items.apply_damage(a, 1000, {}, "burn")
	check(a.combat.health == 0 and a.combat.effects.is_empty(), "existing lethal burn bypasses shield and clears effects")
	items.restore(a)
	check(a.combat.effects.is_empty(), "respawn does not retain shield")
	items.reset(players, world)
	b.vehicle.position = Vector3(30, 0, 0)
	a.combat.slots[0] = "rear_trap"
	check(items.use_next(a, players), "trap deploys from slot")
	projectile = items._projectiles[0]
	check(projectile.position.z == 3.0 and projectile.velocity == Vector3.ZERO, "trap placed behind kart and stationary")
	check(items.world_state().projectiles[0].target == "", "non-seeker target empty in uniform snapshot")
	b.vehicle.position = Vector3(0, 0, 3)
	c.vehicle.position = Vector3(0, 0, 3)
	items.step(players, 0.64)
	check(b.combat.health == 100 and c.combat.health == 100, "trap cannot trigger before arming")
	items.step(players, 0.02)
	check(b.combat.health == 75 and c.combat.health == 100, "shared trap selects one deterministic recipient")
	check(items._projectiles.is_empty(), "trap removed globally after one trigger")
	items.step(players, 1.0)
	check(c.combat.health == 100, "spent trap cannot strike another racer")
	items.reset(players, world)
	b.combat.effects.crystal_shield = {"remaining": 5.0}
	a.combat.slots[0] = "rear_trap"
	items.use_next(a, players)
	items.step(players, 0.7)
	check(b.combat.health == 100 and items._projectiles.is_empty(), "shield consumes trap without damage")
	items.reset(players, world)
	a.combat.slots[0] = "rear_trap"
	items.use_next(a, players)
	b.vehicle.position = Vector3(30, 0, 0)
	c.vehicle.position = Vector3(40, 0, 0)
	items.step(players, 12.0)
	check(items._projectiles.is_empty(), "unused trap expires")
	a.combat.slots[0] = "seeker"
	items.use_next(a, players)
	items.reset(players, world)
	check(items._projectiles.is_empty() and a.combat.effects.is_empty(), "rematch clears projectiles and protection")
	a.vehicle.position = Vector3.ZERO
	b.vehicle.position = Vector3(0, 0, -15)
	a.combat.slots[0] = "seeker"
	items.use_next(a, players)
	items.step(players, 0.64)
	a.vehicle.position.z = -4
	await physics_frame
	await physics_frame
	for tick: int in range(40):
		items.step(players, 1.0 / 60.0)
	check(a.combat.health == 100 and b.combat.health == 70, "moving owner launches ahead after windup without self hit")
	items.reset(players, world)
	a.vehicle.position = Vector3.ZERO
	a.combat.slots[0] = "seeker"
	items.use_next(a, players)
	projectile = items._projectiles[0]
	items.step(players, 0.7)
	check(projectile.launch_age < 0.71, "launch clock starts independently of warning")
	for tick: int in range(8):
		items.step(players, 1.0 / 60.0)
	check(projectile.owner_cleared, "owner collision grace ends after projectile clears kart")
	items._explode({"kind": "seeker", "owner": "a", "owner_cleared": true, "position": a.vehicle.position, "damage_multiplier": 1.0}, players)
	check(a.combat.health == 70, "cleared seeker can damage its owner later")
	items.reset(players, world)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 4, 0.4)
	collision.shape = box
	wall.add_child(collision)
	wall.position = Vector3(0, 0, -2)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	a.combat.slots[0] = "seeker"
	items.use_next(a, players)
	check(items._projectiles[0].target == "", "wall blocks target acquisition")
	items.step(players, 0.3)
	a.vehicle.position.z = -4
	items.step(players, 0.1)
	check(items._projectiles.is_empty() and b.combat.health == 100, "moving windup cannot carry seeker through wall")
	wall.position = Vector3(100, 0, 0)
	floor_body.position.y = -20
	var ramp := StaticBody3D.new()
	var ramp_collision := CollisionShape3D.new()
	var ramp_box := BoxShape3D.new()
	ramp_box.size = Vector3(10, 0.2, 10)
	ramp_collision.shape = ramp_box
	ramp.add_child(ramp_collision)
	ramp.rotation.x = 0.25
	world.add_child(ramp)
	a.vehicle.position = Vector3(0, 0.5, 0)
	await physics_frame
	await physics_frame
	a.combat.slots[0] = "rear_trap"
	items.use_next(a, players)
	var trap: Dictionary = items._projectiles[0]
	var expected_height: float = -tan(0.25) * 3.0 + 0.1 / cos(0.25) + 0.15
	check(absf(trap.position.y - expected_height) < 0.02, "trap rests on actual sloped road surface")
	check(absf(trap.position.y - 0.65) > 0.1, "trap no longer inherits owner height on slope")
	items._projectiles.clear()
	ramp.position.y = -5
	await physics_frame
	await physics_frame
	a.combat.slots = ["rear_trap", "fanta"]
	check(not items.use_next(a, players), "trap rejects distant lower road instead of floating")
	check(a.combat.slots == ["rear_trap", "fanta"] and items._projectiles.is_empty(), "unsupported deployment retains both items and their order")
	ramp.position.y = 0
	a.vehicle.position.y = 8
	await physics_frame
	await physics_frame
	check(not items.use_next(a, players) and a.combat.slots[0] == "rear_trap", "airborne kart cannot leave floating trap")
	a.vehicle.position = Vector3(40, 0, 0)
	check(not items.use_next(a, players) and a.combat.slots[0] == "rear_trap", "gap without ground retains trap")
	a.vehicle.position = Vector3(0, 0.5, 0)
	wall.position = Vector3(0, 0, 1.5)
	await physics_frame
	await physics_frame
	check(items.use_next(a, players), "blocked rear placement falls back to valid ground below owner")
	check(a.combat.slots == ["fanta", ""], "successful trap deployment advances reserve once")
	check(absf(items._projectiles[0].position.z) < 0.01, "blocked rear fallback does not deploy through wall")
	world.free()
	print("COMBAT_ITEMS_PROBE %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
