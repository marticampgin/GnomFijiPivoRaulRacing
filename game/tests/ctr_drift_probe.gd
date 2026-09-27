extends SceneTree

const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Styles = preload("res://vehicle/driving_styles.gd")
const Bot = preload("res://ai/racing_bot_driver.gd")
const DT: float = 1.0 / 60.0
var checks: int = 0
var failures: int = 0

class BroadBend extends Node3D:
	func standings_distance(_progress: Dictionary, _position: Vector3) -> float:
		return 0.0
	func sample_at(distance: float) -> Dictionary:
		var tangent := Vector3(sin(0.17), 0.0, -cos(0.17))
		var point: Vector3 = tangent * distance
		return {"position": [point.x, point.y, point.z], "tangent": [tangent.x, tangent.y, tangent.z]}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vehicle = Vehicle.new()
	root.add_child(vehicle)
	for style: String in Styles.IDS:
		vehicle.configure(Styles.stats_for(style))
		for left_owner: bool in [true, false]:
			_start(vehicle, left_owner)
			for chain: int in range(1, 4):
				_charge(vehicle, left_owner)
				_check(vehicle.drift_ready(), style + " exposes a ready timing window")
				vehicle._step_drift(true, true, true, 0.2, DT)
				_check(vehicle.drift_chain == chain, style + " symmetric opposite shoulder advances chain " + str(chain))
				_check(is_equal_approx(vehicle.boost_remaining, Vehicle.DRIFT_BOOST_SECONDS[chain - 1]), "chain duration uses shared balance")
				var state: Dictionary = vehicle.capture_state()
				vehicle._step_drift(true, true, true, 0.2, DT)
				_check(vehicle.drift_chain == chain, "held or repeated network command cannot grant another turbo")
				vehicle.restore_state(state)
				_check(vehicle.capture_state() == state, "prediction captures every timing and edge latch")
				vehicle._step_drift(true, true, true, 0.2, DT)
				_check(vehicle.drift_chain == chain, "snapshot restoration cannot replay a consumed shoulder edge")
				vehicle._step_drift(left_owner, not left_owner, true, 0.2, DT)
			_check(vehicle.drift_feedback == "complete", "third turbo gives explicit completion feedback")
			for tick: int in 240:
				vehicle._step_drift(left_owner, not left_owner, true, 0.2, DT)
			vehicle._step_drift(true, true, true, 0.2, DT)
			_check(vehicle.drift_chain == 3 and vehicle.drift_charge == 0.0, "three is the hard per-drift turbo limit")
			vehicle.boost_remaining = 0.0
			vehicle._step_drift(false, false, true, 0.2, DT)
			_check(vehicle.boost_remaining == 0.0 and not vehicle.is_drifting, "release never grants automatic turbo")
	for left_owner: bool in [true, false]:
		_start(vehicle, left_owner)
		vehicle._step_drift(true, true, true, 0.2, DT)
		_check(vehicle.drift_feedback == "early" and vehicle.boost_remaining == 0.0, "early opposite press fails visibly")
		for tick: int in 200:
			vehicle._step_drift(left_owner, not left_owner, true, 0.2, DT)
		vehicle._step_drift(true, true, true, 0.2, DT)
		_check(vehicle.drift_chain == 0, "early failure needs a new drift, not a held-button retry")
		_start(vehicle, left_owner)
		for tick: int in 240:
			vehicle._step_drift(left_owner, not left_owner, true, 0.2, DT)
		_check(vehicle._drift_failed and vehicle.drift_chain == 0, "missed window cannot charge forever")
		vehicle._step_drift(true, true, true, 0.2, DT)
		_check(vehicle.boost_remaining == 0.0, "late press gives no turbo")
		_start(vehicle, left_owner)
		_charge(vehicle, left_owner)
		vehicle._step_drift(not left_owner, left_owner, true, 0.2, DT)
		_check(not vehicle.is_drifting and vehicle.drift_owner == 0 and vehicle.boost_remaining == 0.0, "releasing initiator cannot transfer ownership or give boost")
		vehicle._step_drift(not left_owner, left_owner, true, 0.2, DT)
		_check(not vehicle.is_drifting, "held opposite must release before a new drift")
	_start(vehicle, true)
	_charge(vehicle, true)
	vehicle._step_drift(true, true, false, 0.2, DT)
	_check(vehicle.drift_charge == 0.0 and vehicle.boost_remaining == 0.0, "airborne, low-speed or blocked physics gate cancels without boost")
	vehicle._step_drift(true, false, true, 0.2, DT)
	_check(not vehicle.is_drifting, "landing or recovery cannot resume a held shoulder")
	_start(vehicle, true)
	for tick: int in 240:
		vehicle._step_drift(true, false, true, 0.0, DT)
	_check(vehicle.drift_charge == 0.0, "no lateral slip means no charge")
	_start(vehicle, true)
	vehicle._step_drift(true, false, true, Vehicle.DRIFT_MAX_SLIP + 0.1, DT)
	_check(not vehicle.is_drifting, "spin exceeding slip limit cancels drift")
	vehicle._step_drift(false, false, true, 0.2, DT)
	vehicle._step_drift(true, true, true, 0.2, DT)
	vehicle._step_drift(true, false, true, 0.2, DT)
	_check(not vehicle.is_drifting, "simultaneous first shoulders require a clean release")
	_start(vehicle, true)
	_charge(vehicle, true)
	vehicle.reset_at(Transform3D.IDENTITY)
	_check(vehicle.drift_chain == 0 and vehicle.drift_owner == 0 and vehicle.drift_charge == 0.0 and vehicle.drift_feedback.is_empty(), "respawn clears complete drift state")
	vehicle._step_drift(true, false, true, 0.2, DT)
	_check(not vehicle.is_drifting, "respawn requires fresh released controls")
	vehicle.free()
	_bots()
	print("CTR_DRIFT_PROBE %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _start(vehicle: CharacterBody3D, left: bool) -> void:
	vehicle.reset_at(Transform3D.IDENTITY)
	vehicle._step_drift(false, false, true, 0.2, DT)
	vehicle._step_drift(left, not left, true, 0.0, DT)


func _bots() -> void:
	var track := BroadBend.new()
	root.add_child(track)
	for difficulty: String in Bot.DIFFICULTIES:
		var vehicle = Vehicle.new()
		root.add_child(vehicle)
		vehicle.configure(Styles.stats_for("drift"))
		vehicle.speed_mps = 16.0
		vehicle.grounded = true
		vehicle.velocity = Vector3.FORWARD * 16.0
		var bot = Bot.new(track, 1, difficulty)
		var max_chain: int = 0
		for tick: int in 600:
			var command: Dictionary = bot.sample(vehicle, {}, DT)
			vehicle._step_drift(command.drift_left, command.drift_right, true, 0.2, DT)
			max_chain = maxi(max_chain, vehicle.drift_chain)
		_check(max_chain >= (1 if difficulty == "easy" else 3), difficulty + " bot earns timed shoulder boosts under the shared rules")
		vehicle.cancel_drift()
		bot._reaction_remaining = 0.0
		var canceled: Dictionary = bot.sample(vehicle, {}, DT)
		_check(not canceled.drift_left and not canceled.drift_right, "bot neutralizes shoulders after a lifecycle cancellation")
		vehicle.free()
	track.free()


func _charge(vehicle: CharacterBody3D, left: bool) -> void:
	for tick: int in 180:
		if vehicle.drift_charge >= 0.75:
			return
		vehicle._step_drift(left, not left, true, 0.2, DT)
	_check(false, "charge reaches timing window")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
