extends SceneTree

const Protocol = preload("res://net/prototype_protocol.gd")
const Items = preload("res://items/race_items.gd")
const Track = preload("res://track/authored_track.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var empty: Dictionary = {"pickups": [], "projectiles": [], "events": [], "shards": []}
	_check(Protocol.validate_items_world(empty) == empty, "explicit empty world accepted")
	_check(Protocol.validate_items_world(null).is_empty(), "missing world rejected")
	var driving: Dictionary = {"start_boost_remaining": 1.0, "slipstream_charge": 0.5, "slipstream_boost_remaining": 0.0, "slipstream_target": "local:0"}
	_check(Protocol.validate_driving(driving) == driving, "driving presentation accepted")
	for field: String in driving:
		var invalid_driving: Dictionary = driving.duplicate()
		invalid_driving.erase(field)
		_check(Protocol.validate_driving(invalid_driving).is_empty(), "required driving field " + field)
		if field != "slipstream_target":
			for invalid: Variant in [NAN, INF, true, null, "1", -0.1, 1.1]:
				invalid_driving = driving.duplicate()
				invalid_driving[field] = invalid
				_check(Protocol.validate_driving(invalid_driving).is_empty(), "bounded driving value " + field)
	for invalid: Variant in [null, 1, true, "x".repeat(129)]:
		var invalid_driving: Dictionary = driving.duplicate()
		invalid_driving.slipstream_target = invalid
		_check(Protocol.validate_driving(invalid_driving).is_empty(), "bounded target id")
	var extra_driving: Dictionary = driving.duplicate()
	extra_driving.drift_level = 3
	_check(Protocol.validate_driving(extra_driving).is_empty(), "drift level is derived not network field")
	var world: Dictionary = {"pickups": [{"id": 0, "position": [0, 1, 2], "available": true}],
		"projectiles": [{"id": 1, "position": [0, 1, 2], "kind": "bfg10k"}],
		"events": [{"id": 2, "position": [0, 1, 2], "kind": "blast_bfg10k", "radius": 9}],
		"shards": [{"id": 3, "position": [0, 1, 2], "available": false, "scattered": true}]}
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(world))
	_check(Protocol.validate_items_world(decoded) == decoded, "full world JSON roundtrip")
	for category: String in empty:
		var broken: Dictionary = world.duplicate(true)
		broken.erase(category)
		_check(Protocol.validate_items_world(broken).is_empty(), "required world category " + category)
		broken = world.duplicate(true)
		broken[category] = {}
		_check(Protocol.validate_items_world(broken).is_empty(), "array category " + category)
		broken = world.duplicate(true)
		broken[category].append(broken[category][0].duplicate(true))
		_check(Protocol.validate_items_world(broken).is_empty(), "unique ids " + category)
		for invalid: Variant in [NAN, INF, true, "1", null, -1, 0.5, 2147483648]:
			broken = world.duplicate(true)
			broken[category][0].id = invalid
			_check(Protocol.validate_items_world(broken).is_empty(), "bounded integral id " + category)
		for invalid: Variant in [[NAN, 0, 0], [0, INF, 0], [1000001, 0, 0], [true, 0, 0], [0, 0], {}]:
			broken = world.duplicate(true)
			broken[category][0].position = invalid
			_check(Protocol.validate_items_world(broken).is_empty(), "finite world position " + category)
		broken = world.duplicate(true)
		broken[category][0].extra = true
		_check(Protocol.validate_items_world(broken).is_empty(), "strict entry shape " + category)
		broken = empty.duplicate(true)
		for index: int in 257:
			var entry: Dictionary = world[category][0].duplicate(true)
			entry.id = index + 1
			broken[category].append(entry)
		_check(Protocol.validate_items_world(broken).is_empty(), "bounded collection " + category)
	var broken: Dictionary = world.duplicate(true)
	broken.shards[0].id = broken.events[0].id
	_check(Protocol.validate_items_world(broken).is_empty(), "serial ids unique across visual categories")
	for property: String in ["available", "scattered"]:
		broken = world.duplicate(true)
		broken.shards[0][property] = 1
		_check(Protocol.validate_items_world(broken).is_empty(), "strict shard bool " + property)
	broken = world.duplicate(true)
	broken.projectiles[0].kind = "cheat"
	_check(Protocol.validate_items_world(broken).is_empty(), "known projectile")
	broken = world.duplicate(true)
	broken.events[0].radius = NAN
	_check(Protocol.validate_items_world(broken).is_empty(), "finite event radius")
	broken = world.duplicate(true)
	broken.events[0].kind = "cheat"
	_check(Protocol.validate_items_world(broken).is_empty(), "known event")
	var items := Items.new()
	var player: Dictionary = {}
	items.init_player(player)
	for amount: int in [0, 1, 20]:
		player.combat.shards = amount
		_check(not Protocol.validate_combat(player.combat).is_empty(), "valid shard count")
	for amount: Variant in [-1, 21, 1.5, NAN, INF, true, "1", null]:
		player.combat.shards = amount
		_check(Protocol.validate_combat(player.combat).is_empty(), "strict shard count")
	var track := Track.new()
	root.add_child(track)
	track.build(false)
	items.reset({}, track)
	_check(not Protocol.validate_items_world(items.world_state()).is_empty(), "production shard world valid")
	track.free()
	print("RACING_SNAPSHOT_BOUNDARY_PROBE %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
