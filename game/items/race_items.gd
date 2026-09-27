class_name RaceItems
extends RefCounted

const Catalog = preload("res://items/item_catalog.gd")
const PICKUP_COOLDOWN: float = 2.0
var _track: Node3D
var _pickups: Array = []
var _shards: Array = []
var _projectiles: Array = []
var _events: Array = []
var _cooldowns: Dictionary = {}
var _next_id: int = 0
var _rng := RandomNumberGenerator.new()


func reset(players: Dictionary, track: Node3D) -> void:
	_track = track
	_pickups.clear()
	_shards.clear()
	_projectiles.clear()
	_events.clear()
	_cooldowns.clear()
	_rng.randomize()
	for player: Dictionary in players.values():
		init_player(player)
	if not is_instance_valid(track) or not track.has_method("sample_at"):
		return
	var descriptor: Dictionary = track.descriptor()
	var length: float = float(descriptor.get("length", 0.0))
	for index: int in range(32):
		for offset: int in range(3):
			var shard_sample: Dictionary = track.sample_at(fposmod(length * (float(index) + 0.25) / 32.0 + float(offset) * 2.8, length))
			_shards.append({"id": _serial(), "position": _vector(shard_sample.position) + Vector3.UP * 0.8, "scattered": false, "remaining": 0.0, "arm": 0.0})
	for index: int in range(8):
		var sample: Dictionary = track.sample_at(length * (float(index) + 0.5) / 8.0)
		var center: Vector3 = _vector(sample.position) + Vector3.UP * 0.7
		var right: Vector3 = _vector(sample.tangent).cross(Vector3.UP).normalized()
		for lane: int in range(3):
			_pickups.append({"id": index * 3 + lane, "position": center + right * float(lane - 1) * 3.2})


func init_player(player: Dictionary) -> void:
	player["combat"] = {"health": 100.0, "max_health": 100.0, "slots": ["", ""], "effects": {},
		"destroyed_remaining": 0.0, "invulnerable_remaining": 0.0, "item_ack": 0, "shards": 0}


func restore(player: Dictionary) -> void:
	var ack: int = int(player.combat.item_ack)
	init_player(player)
	player.combat.item_ack = ack
	player.combat.invulnerable_remaining = 2.0


func use(player: Dictionary, slot: int, _players: Dictionary) -> bool:
	if not _active(player) or slot < 0 or slot > 1:
		return false
	var state: Dictionary = player.combat
	var id: String = state.slots[slot]
	if not Catalog.IDS.has(id):
		return false
	state.slots[slot] = ""
	var definition: Dictionary = Catalog.definition(id)
	if definition.has("repair"):
		state.health = minf(float(state.max_health), float(state.health) + float(definition.repair))
	if definition.has("duration"):
		state.effects[id] = {"remaining": float(definition.duration)}
	if id == "stroh80" or id == "bfg10k":
		var body: Node3D = player.vehicle
		var forward: Vector3 = -body.global_basis.z
		# Start inside the kart's front envelope so a bumper against a wall cannot fire through it.
		var position: Vector3 = body.global_position + Vector3.UP * (0.8 if id == "stroh80" else 0.1) + forward * 0.8
		_projectiles.append({"id": _serial(), "kind": id, "owner": str(player.id), "position": position,
			"velocity": forward * float(definition.speed) + (Vector3.UP * 7.0 if id == "stroh80" else Vector3.ZERO),
			"remaining": 2.5, "age": 0.0, "damage_multiplier": _damage_multiplier(player)})
	_event("use_" + id, player.vehicle.global_position, 1.0)
	return true


func step(players: Dictionary, delta: float) -> Array:
	var due: Array = []
	for key: String in _cooldowns.keys():
		_cooldowns[key] = maxf(0.0, float(_cooldowns[key]) - delta)
	for event: Dictionary in _events:
		event.remaining -= delta
	_events = _events.filter(func(event: Dictionary) -> bool: return event.remaining > 0.0)
	for player: Dictionary in players.values():
		if not player.has("combat"):
			init_player(player)
		var state: Dictionary = player.combat
		state.invulnerable_remaining = maxf(0.0, float(state.invulnerable_remaining) - delta)
		if float(state.destroyed_remaining) > 0.0:
			state.destroyed_remaining = maxf(0.0, float(state.destroyed_remaining) - delta)
			if state.destroyed_remaining == 0.0:
				due.append(player.id)
			continue
		for id: String in state.effects.keys():
			var effect: Dictionary = state.effects[id]
			if id == "burn" and _active(player):
				apply_damage(player, float(effect.damage) * minf(delta, float(effect.remaining)), {}, "burn")
				if float(state.health) <= 0.0:
					break
			effect.remaining = maxf(0.0, float(effect.remaining) - delta)
			if effect.remaining == 0.0:
				state.effects.erase(id)
	_collect_pickups(players)
	_step_shards(players, delta)
	_step_projectiles(players, delta)
	return due


func effects_stats(player: Dictionary, base: Dictionary) -> Dictionary:
	var stats: Dictionary = base.duplicate(true)
	var multiplier: float = 1.0
	for id: String in player.get("combat", {}).get("effects", {}):
		multiplier = maxf(multiplier, float(Catalog.definition(id).get("speed", 1.0)))
	for key: String in ["top_speed", "acceleration"]:
		if stats.has(key):
			stats[key] = float(stats[key]) * multiplier
	if stats.has("top_speed"):
		stats.top_speed = float(stats.top_speed) * shard_speed_multiplier(player.get("combat", {}))
	return stats


static func shard_speed_multiplier(combat: Dictionary) -> float:
	return 1.0 + float(clampi(int(combat.get("shards", 0)), 0, Catalog.SHARD_CAP)) / float(Catalog.SHARD_CAP) * Catalog.SHARD_TOP_SPEED_BONUS


func player_state(player: Dictionary) -> Dictionary:
	return player.combat.duplicate(true)


static func blur_intensity(combat: Dictionary) -> float:
	var strength: float = 0.0
	for id: String in combat.get("effects", {}):
		if float(combat.effects[id].get("remaining", 0.0)) > 0.0:
			strength = maxf(strength, float(Catalog.definition(id).get("blur", 0.0)))
	return strength


func world_state(_player_id: String = "") -> Dictionary:
	var pickups: Array = []
	var projectiles: Array = []
	var events: Array = []
	var shards: Array = []
	for shard: Dictionary in _shards:
		shards.append({"id": shard.id, "position": _array(shard.position), "available": _shard_available(shard), "scattered": shard.scattered})
	for pickup: Dictionary in _pickups:
		var available: bool = float(_cooldowns.get(str(pickup.id), 0.0)) <= 0.0
		pickups.append({"id": pickup.id, "position": _array(pickup.position), "available": available})
	for projectile: Dictionary in _projectiles:
		projectiles.append({"id": projectile.id, "kind": projectile.kind, "position": _array(projectile.position)})
	for event: Dictionary in _events:
		events.append({"id": event.id, "kind": event.kind, "position": _array(event.position), "radius": event.radius})
	return {"pickups": pickups, "projectiles": projectiles, "events": events, "shards": shards}


func apply_damage(player: Dictionary, amount: float, source: Dictionary = {}, impact_kind: String = "weapon") -> void:
	if not _active(player) or float(player.combat.invulnerable_remaining) > 0.0:
		return
	var multiplier: float = _damage_multiplier(source) if not source.is_empty() else 1.0
	var actual: float = maxf(0.0, amount) * multiplier
	player.combat.health = maxf(0.0, float(player.combat.health) - actual)
	if actual > 0.0 and (impact_kind == "weapon" or (impact_kind == "contact" and actual >= Catalog.SHARD_STRONG_CONTACT_DAMAGE)):
		_lose_shards(player, player.combat.health == 0.0)
	if player.combat.health == 0.0:
		player.combat.shards = 0
		player.combat.destroyed_remaining = 2.0
		player.combat.effects.clear()
		_event("destroyed", player.vehicle.global_position, 2.0)


func _lose_shards(player: Dictionary, destroyed: bool) -> void:
	var stock: int = clampi(int(player.combat.get("shards", 0)), 0, Catalog.SHARD_CAP)
	var lost: int = stock if destroyed else mini(stock, ceili(float(stock) * Catalog.SHARD_LOSS_FRACTION))
	player.combat.shards = stock - lost
	var scatter: int = mini(lost / 2, Catalog.SHARD_WORLD_LIMIT - _shards.size())
	for index: int in scatter:
		var angle: float = TAU * float(index) / float(maxi(scatter, 1)) + float(player.get("slot", 0))
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 2.4
		_shards.append({"id": _serial(), "position": player.vehicle.global_position + Vector3.UP * 0.8 + offset,
			"scattered": true, "remaining": Catalog.SHARD_SCATTER_SECONDS, "arm": Catalog.SHARD_SCATTER_ARM_SECONDS})


func _shard_available(shard: Dictionary) -> bool:
	return float(shard.arm) <= 0.0 and (bool(shard.scattered) or float(shard.remaining) <= 0.0)


func _step_shards(players: Dictionary, delta: float) -> void:
	var retained: Array = []
	for shard: Dictionary in _shards:
		shard.remaining = maxf(0.0, float(shard.remaining) - delta)
		shard.arm = maxf(0.0, float(shard.arm) - delta)
		if bool(shard.scattered) and float(shard.remaining) == 0.0:
			continue
		var winner: Dictionary = {}
		var best: float = INF
		if _shard_available(shard):
			for player: Dictionary in players.values():
				if not _active(player) or int(player.combat.get("shards", 0)) >= Catalog.SHARD_CAP:
					continue
				var distance: float = player.vehicle.global_position.distance_squared_to(shard.position)
				if distance <= 2.25 and (distance < best or (distance == best and str(player.id) < str(winner.get("id", "")))):
					winner = player
					best = distance
		if not winner.is_empty():
			winner.combat.shards = mini(Catalog.SHARD_CAP, int(winner.combat.get("shards", 0)) + 1)
			if bool(shard.scattered):
				continue
			shard.remaining = Catalog.SHARD_RESPAWN_SECONDS
		retained.append(shard)
	_shards = retained


func _active(player: Dictionary) -> bool:
	return player.has("combat") and not player.get("finished", false) and not player.get("spectator", false) and float(player.combat.health) > 0.0


func _damage_multiplier(player: Dictionary) -> float:
	return 1.15 if player.get("combat", {}).get("effects", {}).has("lays_crab") else 1.0


func _collect_pickups(players: Dictionary) -> void:
	var recipients: Dictionary = {}
	for pickup: Dictionary in _pickups:
		var key: String = str(pickup.id)
		if float(_cooldowns.get(key, 0.0)) > 0.0:
			continue
		var candidates: Array[Dictionary] = []
		for player: Dictionary in players.values():
			if not _active(player) or recipients.has(player.id) or player.combat.slots.find("") < 0:
				continue
			var distance: float = player.vehicle.global_position.distance_squared_to(pickup.position)
			if distance <= 4.0:
				candidates.append({"player": player, "distance": distance})
		if candidates.is_empty():
			continue
		# Stable spatial arbitration is independent of dictionary order and racer type.
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.distance != b.distance:
				return a.distance < b.distance
			if int(a.player.get("slot", 0)) != int(b.player.get("slot", 0)):
				return int(a.player.get("slot", 0)) < int(b.player.get("slot", 0))
			return str(a.player.id) < str(b.player.id))
		var recipient: Dictionary = candidates[0].player
		var context: Dictionary = _loot_context(recipient, players)
		var slot: int = recipient.combat.slots.find("")
		recipient.combat.slots[slot] = _draw_item(Catalog.loot_weights(context.place, context.racers, context.gap))
		_cooldowns[key] = PICKUP_COOLDOWN
		recipients[recipient.id] = true
		_event("pickup", pickup.position, 1.0)


func _loot_context(recipient: Dictionary, players: Dictionary) -> Dictionary:
	var distances: Dictionary = {}
	for player: Dictionary in players.values():
		if player.get("spectator", false):
			continue
		var distance: float = 0.0
		if is_instance_valid(_track) and _track.has_method("standings_distance") and player.has("progress"):
			distance = _track.standings_distance(player.progress, player.vehicle.global_position)
		distances[player.id] = distance if is_finite(distance) else 0.0
	var own: float = float(distances.get(recipient.id, 0.0))
	var leader: float = own
	var place: int = 1
	for distance: float in distances.values():
		leader = maxf(leader, distance)
		if distance > own:
			place += 1
	return {"place": place, "racers": distances.size(), "gap": maxf(0.0, leader - own)}


func _draw_item(weights: Dictionary) -> String:
	var total: float = 0.0
	for id: String in Catalog.IDS:
		total += float(weights[id])
	var draw: float = _rng.randf() * total
	for id: String in Catalog.IDS:
		draw -= float(weights[id])
		if draw < 0.0:
			return id
	return Catalog.IDS.back()


func _step_projectiles(players: Dictionary, delta: float) -> void:
	var retained: Array = []
	for projectile: Dictionary in _projectiles:
		var definition: Dictionary = Catalog.definition(projectile.kind)
		var previous: Vector3 = projectile.position
		projectile.velocity += Vector3.DOWN * float(definition.gravity) * delta
		var next: Vector3 = previous + projectile.velocity * delta
		projectile.age += delta
		projectile.remaining -= delta
		var impact: bool = false
		if is_instance_valid(_track) and _track.is_inside_tree():
			var query := PhysicsRayQueryParameters3D.create(previous, next, 3)
			var excluded: Array[RID] = []
			for player: Dictionary in players.values():
				if not _active(player) or (str(player.id) == str(projectile.owner) and float(projectile.age) < 0.2):
					excluded.append(player.vehicle.get_rid())
			query.exclude = excluded
			var hit: Dictionary = _track.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				next = hit.position + hit.normal * 0.03
				impact = true
		projectile.position = next
		if impact or float(projectile.remaining) <= 0.0:
			_explode(projectile, players)
		else:
			retained.append(projectile)
	_projectiles = retained


func _explode(projectile: Dictionary, players: Dictionary) -> void:
	var definition: Dictionary = Catalog.definition(projectile.kind)
	var center: Vector3 = projectile.position
	_event("blast_" + str(projectile.kind), center, float(definition.radius))
	for player: Dictionary in players.values():
		if not _active(player) or float(player.combat.invulnerable_remaining) > 0.0:
			continue
		var target: Vector3 = player.vehicle.global_position + Vector3.UP * 0.35
		if center.distance_to(target) > float(definition.radius) or not _line_of_sight(center, target):
			continue
		apply_damage(player, float(definition.damage) * float(projectile.damage_multiplier))
		if projectile.kind == "stroh80" and _active(player):
			player.combat.effects.burn = {"remaining": float(definition.burn_duration), "damage": float(definition.burn_damage) * float(projectile.damage_multiplier)}


func _line_of_sight(from: Vector3, to: Vector3) -> bool:
	if not is_instance_valid(_track) or not _track.is_inside_tree() or from.distance_to(to) < 0.02:
		return true
	# Move a centimetre off the impact surface toward the target, avoiding self-hit.
	var query := PhysicsRayQueryParameters3D.create(from.move_toward(to, 0.01), to, 1)
	query.hit_back_faces = true
	return _track.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _event(kind: String, position: Vector3, radius: float) -> void:
	_events.append({"id": _serial(), "kind": kind, "position": position, "radius": radius, "remaining": 1.0})


func _serial() -> int:
	_next_id += 1
	return _next_id


static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
