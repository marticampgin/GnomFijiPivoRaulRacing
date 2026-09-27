extends "res://race/local_race_session.gd"

const STEPS: Array[String] = ["drive", "brake", "reverse", "drift", "items"]
const TRAINING_ITEMS: Array[String] = ["fanta", "crystal_shield"]
var _lesson_stage: int = 0
var _lesson_progress: float = 0.0
var _lesson_complete: bool = false
var _drift_charged: bool = false
var _used_items: int = 0


func start_local(seats: Array, available_pads: Variant = null, bot_difficulty: String = "normal") -> bool:
	if seats.size() != 1:
		return false
	return super.start_local(seats, available_pads, bot_difficulty)


func _start_race() -> void:
	super._start_race()
	for id: String in _players.keys():
		if _players[id].is_bot:
			_players[id].vehicle.free()
			_players.erase(id)
	_items._pickups.clear()
	_items._shards.clear()
	_lesson_stage = 0
	_lesson_progress = 0.0
	_lesson_complete = false
	_drift_charged = false
	_used_items = 0
	_phase = "racing"
	_countdown = 0
	_reset_lesson_pose()


func restart_lesson() -> bool:
	if not _started or not _focused:
		return false
	_start_race()
	return resume_local()


func _step_session(delta: float) -> void:
	# The shared simulation remains authoritative; only tutorial race endings are disabled.
	_race_elapsed = 0.0
	_finish_remaining = -1.0
	super._step_session(delta)


func _step_track_event(_delta: float) -> void:
	pass


func _update_progress(player: Dictionary) -> void:
	super._update_progress(player)
	player.finished = false
	player.finish_order = 0
	_finish_count = 0
	_finish_remaining = -1.0


func _recover(player: Dictionary) -> bool:
	var recovered: bool = super._recover(player)
	if recovered:
		_drift_charged = false
	return recovered


func step_local(delta: float, snapshots: Variant = null) -> void:
	var previous_tick: int = _tick
	var before_slots: Array = _players[_seats[0]].combat.slots.duplicate() if _started else []
	var before_ack: int = int(_players[_seats[0]].combat.item_ack) if _started else 0
	super.step_local(delta, snapshots)
	if _tick == previous_tick or _lesson_complete or _phase != "racing":
		return
	var player: Dictionary = _players[_seats[0]]
	var kart: CharacterBody3D = player.vehicle
	var forward_speed: float = kart.velocity.dot(-kart.global_basis.z)
	var command: Dictionary = command_for_seat(0)
	match STEPS[_lesson_stage]:
		"drive":
			_lesson_progress = clampf(kart.speed_mps / 8.0, 0.0, 1.0)
			if forward_speed >= 8.0 and float(command.throttle) > 0.5:
				_advance_lesson(false)
		"brake":
			_lesson_progress = clampf(1.0 - absf(kart.speed_mps) / 8.0, 0.0, 1.0)
			if absf(kart.speed_mps) <= 0.3 and float(command.brake) > 0.5:
				_advance_lesson(false)
		"reverse":
			_lesson_progress = clampf(-forward_speed, 0.0, 1.0)
			if forward_speed < -1.0 and float(command.brake) > 0.5:
				_advance_lesson(true)
		"drift":
			if kart.is_drifting and kart.drift_charge >= Vehicle.DRIFT_READY_CHARGE:
				_drift_charged = true
			_lesson_progress = 0.9 if _drift_charged else clampf(kart.drift_charge / Vehicle.DRIFT_READY_CHARGE, 0.0, 0.9)
			if kart.drift_chain > 0 and kart.boost_remaining > 0.0:
				_advance_lesson(true)
		"items":
			if int(player.combat.item_ack) > before_ack:
				var consumed: int = player.combat.slots.count("") - before_slots.count("")
				for index: int in consumed:
					if _used_items < 2 and before_slots[index] == TRAINING_ITEMS[_used_items] and player.combat.effects.has(before_slots[index]):
						_used_items += 1
			if player.combat.slots[0] == "" and _used_items < 2 and float(player.combat.destroyed_remaining) <= 0.0:
				player.combat.slots = [TRAINING_ITEMS[_used_items], TRAINING_ITEMS[1] if _used_items == 0 else ""]
			_lesson_progress = float(_used_items) / 2.0
			if _used_items == 2:
				_lesson_complete = true


func _advance_lesson(reset_pose: bool) -> void:
	_lesson_stage += 1
	_lesson_progress = 0.0
	if reset_pose:
		_reset_lesson_pose()
	if STEPS[_lesson_stage] == "items":
		_players[_seats[0]].combat.slots = TRAINING_ITEMS.duplicate()


func _reset_lesson_pose() -> void:
	var player: Dictionary = _players[_seats[0]]
	_reset_race(player)
	_items.init_player(player)
	_last_commands.clear()
	inputs.set_suspended(true)
	if _focused:
		inputs.set_suspended(false)


func presentation() -> Dictionary:
	var snapshot: Dictionary = super.presentation()
	snapshot["tutorial"] = {"stage": _lesson_stage, "total": STEPS.size(), "step": STEPS[_lesson_stage],
		"progress": _lesson_progress, "complete": _lesson_complete}
	return snapshot
