extends Node3D

const Art = preload("res://items/item_art.gd")
var _pickups: Dictionary = {}
var _shards: Dictionary = {}
var _projectiles: Dictionary = {}
var _events: Dictionary = {}
var _seen_events: Dictionary = {}
var _clock := 0.0
var _reduced := false

func clear() -> void:
	for child in get_children():
		child.queue_free()
	_pickups.clear()
	_shards.clear()
	_projectiles.clear()
	_events.clear()
	_seen_events.clear()

func set_reduced_effects(value: bool) -> void:
	_reduced = value

func set_quality(_value: String) -> void:
	pass

func _position(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value.size() == 3 else Vector3.ZERO

func apply_world(world: Dictionary) -> void:
	_sync_shards(world.get("shards", []))
	_sync(world.get("pickups", []), _pickups, true)
	_sync(world.get("projectiles", []), _projectiles, false)
	for event in world.get("events", []):
		var id := str(event.get("id", ""))
		if id.is_empty() or _seen_events.has(id):
			continue
		_seen_events[id] = _clock
		var kind := str(event.get("kind", ""))
		if kind not in ["blast_stroh80", "blast_bfg10k", "blast_seeker", "blast_rear_trap", "destroyed"]:
			continue
		var node: Node3D = Art.create_explosion(kind)
		add_child(node)
		node.position = _position(event.get("position", []))
		_events[id] = {"node": node, "age": 0.0, "radius": clampf(float(event.get("radius", 2.0)), 0.1, 12.0)}


func _sync_shards(values: Array) -> void:
	var alive: Dictionary = {}
	for entry: Dictionary in values:
		var id: String = str(entry.id)
		alive[id] = true
		if not _shards.has(id):
			var shard: Node3D = Art.create_shard()
			add_child(shard)
			_shards[id] = shard
		var visual: Node3D = _shards[id]
		visual.position = _position(entry.position)
		visual.set_meta("base_position", visual.position)
		# Unarmed scattered shards remain visible so racers can anticipate collection.
		visual.visible = bool(entry.available) or bool(entry.scattered)
	for id: String in _shards.keys():
		if not alive.has(id):
			_shards[id].queue_free()
			_shards.erase(id)

func _sync(values: Array, existing: Dictionary, pickup: bool) -> void:
	var alive: Dictionary = {}
	for entry in values:
		var id := str(entry.get("id", ""))
		if id.is_empty():
			continue
		alive[id] = true
		if not existing.has(id):
			var node: Node3D = Art.create_pickup() if pickup else Art.create_projectile(str(entry.get("kind", entry.get("item", "stroh80"))))
			add_child(node)
			node.position = _position(entry.get("position", []))
			existing[id] = node
		var visual: Node3D = existing[id]
		visual.visible = bool(entry.get("available", true)) if pickup else true
		var target := _position(entry.get("position", []))
		visual.set_meta("kind", str(entry.get("kind", "")))
		if str(entry.get("kind", "")) == "seeker":
			var direction: Vector3 = target - visual.get_meta("base_position", visual.position)
			if direction.length_squared() > 0.0001 and direction.normalized().cross(Vector3.UP).length_squared() > 0.001:
				visual.look_at(visual.global_position + direction, Vector3.UP)
		visual.set_meta("base_position", target)
		if pickup or str(entry.get("kind", "")) == "rear_trap":
			visual.position = target
	for id in existing.keys():
		if not alive.has(id):
			existing[id].queue_free()
			existing.erase(id)

func _process(delta: float) -> void:
	_clock += delta
	for shard: Node3D in _shards.values():
		shard.rotation.y += delta * (0.25 if _reduced else 1.2)
		shard.position.y = shard.get_meta("base_position").y + (0.0 if _reduced else sin(_clock * 2.0 + shard.position.x) * 0.08)
	for node in _pickups.values():
		node.rotation.y += delta * (0.25 if _reduced else 0.8)
		node.position.y = node.get_meta("base_position").y + (0.0 if _reduced else sin(_clock * 2.0 + node.position.x) * 0.12)
	for node in _projectiles.values():
		node.position = node.position.lerp(node.get_meta("base_position"), 1.0 - exp(-delta / 0.045))
		if node.get_meta("kind", "") not in ["seeker", "rear_trap"]:
			node.rotation.z += delta * (0.4 if _reduced else 2.0)
	for id in _events.keys():
		var effect: Dictionary = _events[id]
		effect.age += delta
		if effect.age > 0.4:
			effect.node.queue_free()
			_events.erase(id)
		else:
			var radius: float = effect.radius * sin(effect.age / 0.4 * PI) * (0.35 if _reduced else 1.0)
			effect.node.scale = Vector3.ONE * maxf(0.01, radius * 2.0)
	for id in _seen_events.keys():
		if _clock - float(_seen_events[id]) > 5.0:
			_seen_events.erase(id)
