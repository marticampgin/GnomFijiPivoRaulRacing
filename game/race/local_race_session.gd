extends "res://race/race_session.gd"

const LocalInputs = preload("res://input/local_player_inputs.gd")
const Driver = preload("res://input/driver_input.gd")

var inputs: RefCounted = LocalInputs.new()
var _seats: Dictionary = {}
var _focused: bool = true
var _started: bool = false
var _last_commands: Dictionary = {}
var _disconnected_seats: Array[int] = []


func configure(track: Node3D) -> void:
	_track = track


func start_local(seats: Array, available_pads: Variant = null, bot_difficulty: String = "normal") -> bool:
	if bot_difficulty not in BotDriver.DIFFICULTIES:
		return false
	if _track == null or not is_inside_tree() or seats.is_empty() or seats.size() > 4:
		return false
	var next_inputs: RefCounted = LocalInputs.new()
	for seat: int in seats.size():
		if not seats[seat] is Dictionary:
			return false
		var config: Dictionary = seats[seat]
		if str(config.get("style_id", Styles.DEFAULT_ID)) not in Styles.IDS:
			return false
		if not next_inputs.assign(seat, int(config.get("device", Driver.KEYBOARD)), available_pads):
			return false
		if not next_inputs.configure_profile(seat, config.get("controls", Driver.default_profile())):
			return false
	for player: Dictionary in _players.values():
		player.vehicle.free()
	_players.clear()
	_seats.clear()
	_last_commands.clear()
	_disconnected_seats.clear()
	inputs = next_inputs
	_bot_difficulty = bot_difficulty
	inputs.set_focused(_focused)
	inputs.set_suspended(not _focused)
	_tick = 0
	for seat: int in seats.size():
		var config: Dictionary = seats[seat]
		var id: String = "local:%d" % seat
		_seats[seat] = id
		_players[id] = _new_player(id, str(config.get("name", "Player %d" % (seat + 1))), seat, false, str(config.get("style_id", Styles.DEFAULT_ID)))
	_start_race()
	_started = true
	return true


## The owning adapter calls this once, irrespective of the number of cameras.
func step_local(delta: float, snapshots: Variant = null) -> void:
	if not _started:
		return
	_last_commands = inputs.sample_all(snapshots)
	_disconnected_seats.clear()
	for seat: int in _seats:
		if not bool(inputs._connected.get(seat, false)):
			_disconnected_seats.append(seat)
	for command: Dictionary in _last_commands.values():
		if command.pause:
			if inputs.is_suspended():
				resume_local()
			else:
				pause_local()
			return
	if inputs.is_suspended() or not _focused:
		return
	for seat: int in _seats:
		var player: Dictionary = _players[_seats[seat]]
		var command: Dictionary = _last_commands.get(seat, Driver.neutral())
		player.input = command
		for slot: int in 2:
			if bool(command.get("use_item_%d" % (slot + 1), false)):
				use_item_seat(seat, slot)
	_step_session(delta)


func is_paused_local() -> bool:
	return inputs.is_suspended()


func command_for_seat(seat: int) -> Dictionary:
	return _last_commands.get(seat, Driver.neutral()).duplicate()


func use_item_seat(seat: int, slot: int) -> bool:
	if not _seats.has(seat) or slot < 0 or slot > 1 or _phase != "racing" or inputs.is_suspended() or not _focused:
		return false
	var player: Dictionary = _players[_seats[seat]]
	if player.finished:
		return false
	for pending: Dictionary in player.item_queue:
		if int(pending.slot) == slot:
			return false
	player.item_accepted += 1
	player.item_queue.append({"sequence": player.item_accepted, "slot": slot, "epoch": player.epoch})
	return true


func pause_local() -> void:
	inputs.set_suspended(true)
	_last_commands.clear()


func resume_local() -> bool:
	if not _focused:
		return false
	return inputs.set_suspended(false)


func set_focused(value: bool) -> void:
	_focused = value
	inputs.set_focused(value)
	if not value:
		pause_local()


func assign_device(seat: int, device: int, available_pads: Variant = null) -> bool:
	if not _seats.has(seat) or not inputs.assign(seat, device, available_pads):
		return false
	_disconnected_seats.erase(seat)
	return true


func ready_seat(seat: int, style_id: String = "") -> bool:
	if _phase != "results" or not _seats.has(seat) or (not style_id.is_empty() and style_id not in Styles.IDS):
		return false
	var player: Dictionary = _players[_seats[seat]]
	if not style_id.is_empty():
		player.next_style_id = style_id
	player.ready = true
	return true


func recover_seat(seat: int) -> bool:
	if not _seats.has(seat) or _phase != "racing" or inputs.is_suspended() or not _focused:
		return false
	var player: Dictionary = _players[_seats[seat]]
	if player.finished or float(player.combat.destroyed_remaining) > 0.0 or _tick - int(player.last_recover_at) < 60:
		return false
	player.last_recover_at = _tick
	_recover(player)
	return true


func vehicle_for_seat(seat: int) -> CharacterBody3D:
	return _players[_seats[seat]].vehicle if _seats.has(seat) else null


func presentation() -> Dictionary:
	var standings: Array = _players.values()
	# Route projection is constant within this snapshot, not within the next one.
	var distances: Dictionary = {}
	for player: Dictionary in standings:
		if not player.finished:
			distances[player.id] = float(player.get("result_progress", 0.0)) if _phase == "results" else _race_progress(player)
	standings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.finished or b.finished:
			return int(a.finish_order) < int(b.finish_order) if a.finished and b.finished else bool(a.finished)
		var distance_a: float = distances[a.id]
		var distance_b: float = distances[b.id]
		return int(a.slot) < int(b.slot) if is_equal_approx(distance_a, distance_b) else distance_a > distance_b)
	var entries: Array = []
	var seats: Dictionary = {}
	for index: int in standings.size():
		var player: Dictionary = standings[index]
		var entry: Dictionary = {"id": player.id, "name": player.name, "slot": player.slot,
			"position": index + 1, "style_id": player.style_id, "next_style_id": player.next_style_id,
			"lap": mini(RACE_LAPS, int(player.lap)), "finished": player.finished, "ready": player.ready,
			"dnf": player.dnf, "is_bot": player.is_bot, "spectator": false, "connected": int(player.slot) not in _disconnected_seats,
			"elapsed": player.elapsed, "epoch": player.epoch,
			"combat": _items.player_state(player), "driving": Techniques.presentation(player), "state": Protocol.pack_state(player.vehicle.capture_state())}
		entries.append(entry)
		if not player.is_bot:
			var seat: int = int(player.slot)
			seats[seat] = entry.duplicate(true)
			seats[seat]["look_back"] = bool(_last_commands.get(seat, {}).get("look_back", false))
			seats[seat]["items_world"] = _items.world_state(player.id)
	return {"tick": _tick, "race_id": _race_id, "phase": _phase, "players": entries, "seats": seats, "bot_difficulty": _bot_difficulty,
		"track_event": _track_event.snapshot(),
		"controls": inputs.profiles(),
		"paused": inputs.is_suspended(), "focused": _focused, "devices": inputs.assignments(),
		"pause_reason": "focus" if not _focused else ("device" if not _disconnected_seats.is_empty() else ("manual" if inputs.is_suspended() else "")),
		"disconnected_seats": _disconnected_seats.duplicate(), "available_pads": Input.get_connected_joypads(),
		"items_world": _items.world_state(), "countdown": maxf(0.0, float(_countdown) / 60.0),
		"finish_remaining": _finish_remaining, "race_remaining": maxf(0.0, 180.0 - _race_elapsed)}
