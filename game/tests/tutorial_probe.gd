extends SceneTree

const Tutorial = preload("res://race/driving_tutorial.gd")
const Track = preload("res://track/authored_track.gd")
const DT: float = 1.0 / 60.0
var checks: int = 0
var failures: int = 0
var lesson: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	lesson = Tutorial.new()
	root.add_child(lesson)
	var track: Node3D = Track.new()
	lesson.add_child(track)
	track.build(false)
	lesson.configure(track)
	_check(not lesson.start_local([{"device": -1}, {"device": 0}], [0]), "tutorial rejects multiple seats")
	_check(lesson.start_local([{"device": -1}], []), "tutorial starts without backend")
	lesson.inputs.configure_profile(0, {"keyboard": "both", "gamepad": "standard", "deadzone": 0.2, "steering": 1.0})
	_check(lesson._players.size() == 1 and not lesson._players["local:0"].is_bot, "single human without bots")
	_check(lesson.presentation().tutorial.step == "drive", "first real driving lesson")
	await _frame({})
	for tick: int in 180:
		await _frame({KEY_W: true})
		if lesson.presentation().tutorial.step == "brake":
			break
	_check(lesson.presentation().tutorial.step == "brake", "actual throttle and physics complete drive")
	for tick: int in 180:
		await _frame({KEY_S: true})
		if lesson.presentation().tutorial.step == "reverse":
			break
	_check(lesson.presentation().tutorial.step == "reverse", "actual brake stops moving kart")
	for tick: int in 180:
		await _frame({KEY_S: true})
		if lesson.presentation().tutorial.step == "drift":
			break
	_check(lesson.presentation().tutorial.step == "drift", "continuously held brake produces reverse without release")
	await _frame({})
	var player: Dictionary = lesson._players["local:0"]
	for tick: int in 90:
		await _frame({KEY_W: true})
	var drift_keys: Dictionary = {}
	for tick: int in 180:
		# Countersteer around the center line instead of holding a turn into the wall.
		drift_keys = {KEY_W: true, KEY_SHIFT: true}
		drift_keys[KEY_D if (tick + 8) % 32 < 16 else KEY_A] = true
		await _frame(drift_keys)
		if lesson._drift_charged:
			break
	_check(lesson._drift_charged, "real drifting motion reaches timing window")
	# First-ready-frame success must not depend on a prior HUD sample of charge.
	lesson._drift_charged = false
	player.vehicle.drift_charge = Tutorial.Vehicle.DRIFT_READY_CHARGE - Tutorial.Vehicle.DRIFT_CHARGE_RATE * float(player.vehicle.stats.drift) * DT * 0.5
	player.vehicle.velocity = -player.vehicle.global_basis.z * 20.0 + player.vehicle.global_basis.x * 2.0
	drift_keys[KEY_E] = true
	await _frame(drift_keys)
	_check(lesson.presentation().tutorial.step == "items", "first-ready-frame opposite shoulder earns manual boost and advances tutorial")
	_check(player.combat.slots == ["fanta", "crystal_shield"], "two deterministic training items")
	await _frame({})
	await _frame({KEY_Q: true})
	_check(not lesson.presentation().tutorial.complete and lesson.presentation().tutorial.progress == 0.5, "one real item use is insufficient")
	_check(player.combat.effects.has("fanta"), "training drink uses production effect")
	lesson.pause_local()
	var paused_tick: int = lesson._tick
	await _frame({KEY_Q: true})
	_check(lesson._tick == paused_tick and not lesson.presentation().tutorial.complete, "pause freezes lesson and items")
	lesson.resume_local()
	await _frame({KEY_Q: true})
	_check(not lesson.presentation().tutorial.complete, "held item cannot fire after resume")
	await _frame({})
	await _frame({KEY_Q: true})
	_check(lesson.presentation().tutorial.complete and player.combat.effects.has("crystal_shield"), "second actual effect completes lesson")
	_check(lesson._phase == "racing" and not player.finished, "completion is not race results or rewards")
	_check(lesson.restart_lesson(), "completed lesson can restart")
	_check(lesson.presentation().tutorial.stage == 0 and not lesson.presentation().tutorial.complete and player.combat.slots == ["", ""], "restart clears progress inventory and effects")
	lesson._race_elapsed = 181.0
	await _frame({})
	_check(lesson._phase == "racing", "tutorial does not time out")
	lesson.set_focused(false)
	paused_tick = lesson._tick
	await _frame({KEY_W: true})
	_check(lesson._tick == paused_tick and lesson.presentation().tutorial.stage == 0, "focus loss freezes progression")
	_check(not lesson.restart_lesson(), "unfocused retry cannot resume simulation")
	lesson.free()
	await process_frame
	print("TUTORIAL_PROBE %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _frame(keys: Dictionary) -> void:
	await physics_frame
	lesson.step_local(DT, {-1: {"connected": true, "keys": keys}})


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
