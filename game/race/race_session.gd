extends Node3D

const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Styles = preload("res://vehicle/driving_styles.gd")
const Protocol = preload("res://net/prototype_protocol.gd")
const BotDriver = preload("res://ai/racing_bot_driver.gd")
const VehicleContacts = preload("res://vehicle/vehicle_contacts.gd")
const Items = preload("res://items/race_items.gd")
const Techniques = preload("res://race/race_techniques.gd")
const TrackEvent = preload("res://race/track_event.gd")
const RecoveryPlacement = preload("res://race/recovery_placement.gd")
const MAX_PLAYERS: int = 10
const RACE_LAPS: int = 3

var _track: Node3D
var _players: Dictionary = {}
var _tick: int = 0
var _countdown: int = -1
var _finish_count: int = 0
var _race_id: int = 0
var _phase: String = "waiting"
var _race_elapsed: float = 0.0
var _finish_remaining: float = -1.0
var _items: RefCounted = Items.new()
var _bot_difficulty: String = "normal"
var _techniques: RefCounted = Techniques.new()
var _track_event: RefCounted = TrackEvent.new()


func _step_track_event(delta: float) -> void:
	_track_event.step(_players, _track, delta, _tick)
	_track.apply_event(_track_event.snapshot())


func _create_vehicle(_slot: int, _visuals: bool) -> CharacterBody3D:
	var vehicle: CharacterBody3D = Vehicle.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = Vehicle.create_collision_shape()
	vehicle.add_child(collider)
	# Pair contacts are resolved once after all vehicles have moved.
	vehicle.collision_layer = 2
	vehicle.collision_mask = 1
	add_child(vehicle)
	return vehicle


func _human_input_available(_player: Dictionary) -> bool:
	return true


func _step_session(delta: float) -> void:
	_tick += 1
	var was_countdown: bool = _phase == "countdown"
	if _countdown > 0:
		_countdown -= 1
		if _countdown == 0:
			_phase = "racing"
	if _phase == "racing":
		_race_elapsed += delta
		_step_track_event(delta)
		for id: String in _items.step(_players, delta):
			if _recover(_players[id]):
				_items.restore(_players[id])
			else:
				_players[id].combat.destroyed_remaining = delta
		if _finish_remaining >= 0.0:
			_finish_remaining = maxf(0.0, _finish_remaining - delta)
		_techniques.step(_players, delta)
	var contact_bodies: Array = []
	var previous_transforms: Dictionary = {}
	var impact_damage: Dictionary = {}
	for id: String in _players.keys():
		var player: Dictionary = _players[id]
		var queue: Array = player["queue"]
		while not player["item_queue"].is_empty():
			var use_command: Dictionary = player["item_queue"].pop_front()
			player["combat"]["item_ack"] = int(use_command["sequence"])
			if _phase == "racing" and player["connected"] and use_command["epoch"] == player["epoch"]:
				_items.use_next(player, _players)
		if player["is_bot"] and _phase == "racing":
			if player["driver"].should_use_item(player, _players, _tick):
				_items.use_next(player, _players)
		if not queue.is_empty():
			player["input"] = queue.pop_front()
			player["ack"] = int(player["input"]["sequence"])
		var command: Dictionary = player["input"]
		if player["is_bot"] and was_countdown:
			command = player["driver"].sample_countdown(float(_countdown) / 60.0)
		elif player["is_bot"] and _phase == "racing" and not player["finished"]:
			command = player["driver"].sample(player["vehicle"], player["progress"], delta)
		if was_countdown:
			var start_command: Dictionary = command if player["is_bot"] or _human_input_available(player) else Protocol.BLOCKED
			_techniques.countdown(player, start_command, float(_countdown) / 60.0, _phase == "racing")
		if (not player["is_bot"] and not _human_input_available(player)) or _phase != "racing" or player["finished"] or player["spectator"]:
			command = Protocol.BLOCKED
		player["previous_position"] = player["vehicle"].global_position
		player["vehicle"].configure(_items.effects_stats(player, Styles.stats_for(player["style_id"])))
		var destroyed: bool = float(player["combat"]["destroyed_remaining"]) > 0.0
		if _phase == "racing" and not player["finished"] and not player["spectator"] and not destroyed:
			contact_bodies.append(player["vehicle"])
			previous_transforms[player["vehicle"].get_instance_id()] = player["vehicle"].global_transform
		if destroyed:
			player["vehicle"].velocity = Vector3.ZERO
			player["vehicle"].speed_mps = 0.0
		else:
			var before_velocity: Vector3 = player["vehicle"].velocity
			player["vehicle"].step(command, delta)
			if _phase == "racing" and not player["finished"] and not player["spectator"]:
				for collision_index: int in player["vehicle"].get_slide_collision_count():
					var collision: KinematicCollision3D = player["vehicle"].get_slide_collision(collision_index)
					var normal: Vector3 = collision.get_normal()
					if absf(normal.dot(player["vehicle"].up_direction)) < 0.5:
						var closing: float = maxf(0.0, -before_velocity.dot(normal))
						impact_damage[id] = maxf(float(impact_damage.get(id, 0.0)), _contact_damage(closing))
	if contact_bodies.size() > 1:
		var impacts: Array = []
		VehicleContacts.resolve(contact_bodies, previous_transforms,
			_players.values().map(func(player: Dictionary) -> CharacterBody3D: return player["vehicle"]), impacts)
		for impact: Dictionary in impacts:
			for player: Dictionary in _players.values():
				if player["vehicle"] == impact["a"] or player["vehicle"] == impact["b"]:
					impact_damage[player["id"]] = maxf(float(impact_damage.get(player["id"], 0.0)), _contact_damage(float(impact["closing"])))
	for id: String in impact_damage:
		_items.apply_damage(_players[id], float(impact_damage[id]), {}, "contact")
	# Checkpoints observe the final contact-corrected pose, never an unresolved overlap.
	for player: Dictionary in _players.values():
		if _phase == "racing" and not player["finished"] and not player["spectator"]:
			player["elapsed"] += delta
			if float(player["combat"]["destroyed_remaining"]) <= 0.0:
				_update_progress(player)
		if float(player["combat"]["destroyed_remaining"]) <= 0.0 and (_track.needs_recovery(player["vehicle"].global_position) or not bool(player["progress"]["interval_valid"])):
			_recover(player)
	_remove_expired_waiters()
	if _human_count() == 0:
		for player: Dictionary in _players.values():
			player["vehicle"].queue_free()
		_players.clear()
		_countdown = -1
		_finish_count = 0
		_phase = "waiting"
	elif _phase == "racing":
		if _race_participants_finished() or _race_elapsed >= 180.0 or _finish_remaining == 0.0:
			_phase = "results"
			for player: Dictionary in _players.values():
				player["dnf"] = not player["spectator"] and not player["finished"]
				player["result_progress"] = _race_progress(player)
	elif _phase == "results":
		_try_repeat()


func _race_participants_finished() -> bool:
	var has_human: bool = false
	var bots_done: bool = true
	for player: Dictionary in _players.values():
		if player["spectator"] or player.get("expired", false):
			continue
		if player["is_bot"]:
			bots_done = bots_done and bool(player["finished"])
		else:
			has_human = true
			if not player["finished"]:
				return false
	return has_human or bots_done


func _human_count() -> int:
	var count: int = 0
	for player: Dictionary in _players.values():
		if not player["is_bot"] and not player.get("expired", false):
			count += 1
	return count


func _new_player(id: String, display_name: String, slot: int, bot: bool, style_id: String = Styles.DEFAULT_ID) -> Dictionary:
	var vehicle: CharacterBody3D = _create_vehicle(slot, false)
	if bot:
		style_id = Styles.IDS[slot % Styles.IDS.size()]
	vehicle.configure(Styles.stats_for(style_id))
	vehicle.reset_at(_track.spawn_transform(slot))
	var player: Dictionary = {"id": id, "name": display_name, "slot": slot, "vehicle": vehicle,
		"style_id": style_id, "next_style_id": style_id,
		"is_bot": bot, "driver": BotDriver.new(_track, slot, _bot_difficulty) if bot else null,
		"spectator": false, "ready": bot, "dnf": false,
		"connected": true,
		"accepted": 0, "ack": 0, "queue": [], "item_queue": [], "item_accepted": 0, "input": Protocol.BLOCKED.duplicate(),
		"lap": 1, "progress": _track.initial_progress(), "previous_position": vehicle.global_position,
		"finished": false, "finish_order": 0, "elapsed": 0.0, "last_recover_at": -1000, "epoch": 0}
	_items.init_player(player)
	player["driving"] = Techniques.new_state()
	return player


func _remove_expired_waiters() -> void:
	for id: String in _players.keys():
		if _players[id]["spectator"] and _players[id].get("expired", false):
			_players[id]["vehicle"].queue_free()
			_players.erase(id)


func _start_race() -> void:
	_track_event.reset()
	_track.apply_event(_track_event.snapshot())
	for id: String in _players.keys():
		if _players[id]["is_bot"] or _players[id].get("expired", false):
			_players[id]["vehicle"].queue_free()
			_players.erase(id)
	var slot: int = 0
	for player: Dictionary in _players.values():
		player["slot"] = slot
		player["spectator"] = false
		_reset_race(player)
		slot += 1
	while slot < MAX_PLAYERS:
		var id: String = "bot:%d" % slot
		_players[id] = _new_player(id, "Bot %02d" % (slot + 1), slot, true)
		slot += 1
	_race_id += 1
	_items.reset(_players, _track)
	for player: Dictionary in _players.values():
		player["combat"]["item_ack"] = player["item_accepted"]
		player["item_queue"].clear()
	_phase = "countdown"
	_countdown = 300
	_finish_count = 0
	_race_elapsed = 0.0
	_finish_remaining = -1.0


func _try_repeat() -> void:
	if _phase != "results":
		return
	var eligible: int = 0
	for player: Dictionary in _players.values():
		if player["is_bot"] or not player["connected"]:
			continue
		eligible += 1
		if not player["spectator"] and not player["ready"]:
			return
	if eligible > 0:
		_start_race()


func _update_progress(player: Dictionary) -> void:
	var events: Array = _track.advance_progress(player["progress"], player["previous_position"], player["vehicle"].global_position)
	player["lap"] = int(player["progress"]["lap"]) + 1
	for event: Dictionary in events:
		if event["type"] == "finish" and not player["finished"]:
			_finish_count += 1
			player["finished"] = true
			player["finish_order"] = _finish_count
			if _finish_remaining < 0.0:
				_finish_remaining = 30.0


func _recover(player: Dictionary) -> bool:
	var pose: Variant = RecoveryPlacement.find_pose(_track, player, _players)
	if pose == null:
		return false
	_reset_player_at(player, pose)
	return true


func _reset_player_at(player: Dictionary, pose: Transform3D) -> void:
	player["driving"] = Techniques.new_state()
	player["vehicle"].reset_at(pose)
	_track.mark_recovered(player["progress"])
	player["previous_position"] = player["vehicle"].global_position
	player["queue"].clear()
	player["item_queue"].clear()
	player["combat"]["item_ack"] = player["item_accepted"]
	player["input"] = Protocol.BLOCKED.duplicate()
	player["ack"] = player["accepted"]
	player["epoch"] += 1
	if player["is_bot"]:
		player["driver"].reset()


func _reset_race(player: Dictionary) -> void:
	player["style_id"] = player.get("next_style_id", Styles.DEFAULT_ID)
	player["vehicle"].configure(Styles.stats_for(player["style_id"]))
	player["lap"] = 1
	player["progress"] = _track.initial_progress()
	player["finished"] = false
	player["finish_order"] = 0
	player["elapsed"] = 0.0
	player["dnf"] = false
	player["ready"] = player["is_bot"]
	_reset_player_at(player, _track.spawn_transform(int(player["slot"])))


func _race_progress(player: Dictionary) -> float:
	return _track.standings_distance(player["progress"], player["vehicle"].global_position)


func _contact_damage(closing: float) -> float:
	return clampf((closing - 8.0) * 1.5, 0.0, 30.0)
