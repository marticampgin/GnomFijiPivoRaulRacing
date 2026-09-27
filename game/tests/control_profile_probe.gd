extends SceneTree

const Driver = preload("res://input/driver_input.gd")
const Seats = preload("res://input/local_player_inputs.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	var standard: Dictionary = Driver.default_profile()
	var legacy: Dictionary = {"keyboard": "both", "gamepad": "standard", "deadzone": 0.2, "steering": 1.0}
	_check(standard == {"keyboard": "arcade", "gamepad": "arcade", "deadzone": 0.2, "steering": 1.0}, "defaults select approved arcade mapping")
	_check(Driver.validate_profile(standard) == standard, "default validated")
	for invalid: Variant in [null, [], "profile", {}, {"keyboard": "both"}]:
		_check(Driver.validate_profile(invalid).is_empty(), "invalid shape rejected")
	var extra: Dictionary = standard.duplicate()
	extra.extra = true
	_check(Driver.validate_profile(extra).is_empty(), "unknown field rejected")
	for key: String in ["keyboard", "gamepad"]:
		for value: Variant in [null, true, 1, [], {}, "unknown"]:
			var bad: Dictionary = standard.duplicate()
			bad[key] = value
			_check(Driver.validate_profile(bad).is_empty(), "invalid preset rejected")
	for key: String in ["deadzone", "steering"]:
		for value: Variant in [null, true, "0.2", NAN, INF, -INF, -1, 2]:
			var bad: Dictionary = standard.duplicate()
			bad[key] = value
			_check(Driver.validate_profile(bad).is_empty(), "invalid numeric setting rejected")
	for value: Dictionary in [{"keyboard": "wasd", "gamepad": "alternate", "deadzone": 0.05, "steering": 0.5},
		{"keyboard": "arrows", "gamepad": "standard", "deadzone": 0.35, "steering": 1.5}]:
		_check(Driver.validate_profile(value) == value, "inclusive bounds accepted")
	var keyboard = Driver.new()
	keyboard.configure_profile(legacy)
	keyboard.sample_local(_keys())
	_check(keyboard.sample_local(_keys({KEY_UP: true})).throttle == 1.0, "legacy arrow throttle")
	var custom: Dictionary = {"keyboard": "wasd", "gamepad": "alternate", "deadzone": 0.1, "steering": 0.5}
	_check(keyboard.configure_profile(custom), "keyboard configured")
	custom.steering = 1.5
	_check(keyboard.profile().steering == 0.5, "configure owns profile copy")
	_check(keyboard.sample_local(_keys({KEY_W: true, KEY_Q: true})) == Driver.neutral(), "profile change blocks held throttle and item")
	keyboard.sample_local(_keys())
	var command: Dictionary = keyboard.sample_local(_keys({KEY_W: true, KEY_D: true, KEY_Q: true, KEY_E: true, KEY_SPACE: true, KEY_C: true, KEY_ESCAPE: true}))
	_check(command.throttle == 1.0 and command.steering == 0.5 and command.drift and command.look_back and command.use_item_1 and command.use_item_2 and command.pause, "keyboard preset only changes axes")
	_check(not keyboard.configure_profile({}), "invalid configure rejected")
	_check(not keyboard.sample_local(_keys({KEY_Q: true})).use_item_1, "invalid configure does not rearm edges")
	_check(keyboard.sample_local(_keys({KEY_UP: true, KEY_RIGHT: true})) == Driver.neutral(), "wasd ignores arrows")
	custom.keyboard = "arrows"
	keyboard.configure_profile(custom)
	keyboard.sample_local(_keys())
	_check(keyboard.sample_local(_keys({KEY_W: true, KEY_D: true})) == Driver.neutral(), "arrows ignore wasd")
	command = keyboard.sample_local(_keys({KEY_RIGHT: true, KEY_DOWN: true}))
	_check(command.steering == 1.0 and command.brake == 1.0, "steering sensitivity clamps and does not affect brake")
	var seats = Seats.new()
	seats.assign(0, 2, [2, 3, 4])
	seats.assign(1, 3, [2, 3, 4])
	seats.configure_profile(1, legacy)
	_check(not seats.configure_profile(2, standard), "unassigned seat rejected")
	_check(seats.configure_profile(0, custom), "seat profile configured")
	var raw: Dictionary = {2: _pad(), 3: _pad()}
	seats.sample_all(raw)
	raw[2] = _pad({JOY_AXIS_LEFT_X: 0.4, JOY_AXIS_TRIGGER_RIGHT: 0.55}, {JOY_BUTTON_X: true, JOY_BUTTON_B: true})
	raw[3] = raw[2]
	var commands: Dictionary = seats.sample_all(raw)
	_check(is_equal_approx(commands[0].steering, 0.5) and is_equal_approx(commands[0].throttle, 0.5), "custom deadzone sensitivity steering only")
	_check(commands[0].drift and commands[0].look_back, "alternate face buttons")
	_check(is_equal_approx(commands[1].steering, 0.25) and not commands[1].drift and not commands[1].look_back, "seat configuration isolated")
	raw[2] = _pad({}, {JOY_BUTTON_A: true, JOY_BUTTON_Y: true, JOY_BUTTON_LEFT_SHOULDER: true, JOY_BUTTON_RIGHT_SHOULDER: true, JOY_BUTTON_START: true})
	command = seats.sample_all(raw)[0]
	_check(not command.drift and not command.look_back and command.use_item_1 and command.use_item_2 and command.pause, "alternate leaves shoulders and pause unchanged")
	var profiles: Dictionary = seats.profiles()
	profiles[0].deadzone = 0.35
	profiles.clear()
	_check(seats.profiles()[0] == custom and seats.profiles()[1] == legacy, "profile snapshots cannot mutate registry")
	_check(not seats.configure_profile(0, {}) and seats.profiles()[0] == custom, "invalid seat profile is transactional")
	_check(not seats.assign(0, 3, [2, 3, 4]) and seats.profiles()[0] == custom and seats.assignments()[0] == 2, "failed reassignment preserves profile and device")
	_check(seats.assign(0, 4, [4]) and seats.profiles()[0] == custom, "reassignment preserves profile")
	raw[4] = _pad({JOY_AXIS_LEFT_X: 0.4}, {JOY_BUTTON_X: true, JOY_BUTTON_LEFT_SHOULDER: true})
	_check(seats.sample_all(raw)[0] == Driver.neutral(), "reassignment rearms held controls")
	raw[4] = _pad()
	seats.sample_all(raw)
	raw[4] = _pad({}, {JOY_BUTTON_X: true, JOY_BUTTON_LEFT_SHOULDER: true})
	command = seats.sample_all(raw)[0]
	_check(command.drift and command.use_item_1, "release rearms new device with preserved profile")
	seats.unassign(0)
	_check(not seats.profiles().has(0), "unassigned seat profile removed")
	seats.assign(0, 4, [4])
	_check(seats.profiles()[0] == standard, "new assignment defaults")
	print("CONTROL_PROFILE_PROBE ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures == 0 else 1)


func _keys(keys: Dictionary = {}) -> Dictionary:
	return {"connected": true, "keys": keys}


func _pad(axes: Dictionary = {}, buttons: Dictionary = {}) -> Dictionary:
	return {"connected": true, "axes": axes, "buttons": buttons}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
