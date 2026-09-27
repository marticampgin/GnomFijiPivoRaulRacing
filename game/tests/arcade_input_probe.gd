extends SceneTree

const Driver = preload("res://input/driver_input.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(Driver.default_profile().keyboard == "arcade" and Driver.default_profile().gamepad == "arcade", "arcade is default for both devices")
	for pair: Array in [[KEY_SPACE, "throttle"], [KEY_C, "brake"], [KEY_SHIFT, "drift"], [KEY_E, "drift"],
		[KEY_Q, "use_item_1"], [KEY_T, "use_item_2"], [KEY_F, "look_back"], [KEY_TAB, "pause"], [KEY_ESCAPE, "pause"]]:
		var driver = Driver.new()
		driver.sample_local(_keys())
		_check(_only(driver.sample_local(_keys({pair[0]: true})), pair[1]), "keyboard action isolated: " + OS.get_keycode_string(pair[0]))
	for pair: Array in [[KEY_A, -1.0], [KEY_D, 1.0], [KEY_LEFT, -1.0], [KEY_RIGHT, 1.0]]:
		var driver = Driver.new()
		driver.sample_local(_keys())
		_check(driver.sample_local(_keys({pair[0]: true})).steering == pair[1], "arcade lateral steering: " + OS.get_keycode_string(pair[0]))
	var keyboard = Driver.new()
	keyboard.sample_local(_keys())
	_check(keyboard.sample_local(_keys({KEY_W: true, KEY_S: true, KEY_UP: true, KEY_DOWN: true})) == Driver.neutral(), "legacy throttle keys do not silently act in arcade")
	_check(keyboard.sample_local(_keys({KEY_Q: true, KEY_T: true})).use_item_2, "second item edge begins on T")
	_check(not keyboard.sample_local(_keys({KEY_Q: true, KEY_T: true})).use_item_2, "held T does not repeat item")
	for pair: Array in [[JOY_BUTTON_A, "throttle"], [JOY_BUTTON_B, "brake"], [JOY_BUTTON_RIGHT_SHOULDER, "drift"],
		[JOY_BUTTON_LEFT_SHOULDER, "use_item_1"], [JOY_BUTTON_Y, "use_item_2"], [JOY_BUTTON_X, "look_back"], [JOY_BUTTON_START, "pause"]]:
		var driver = Driver.new(0)
		driver.sample_local(_pad())
		_check(_only(driver.sample_local(_pad({}, {pair[0]: true})), pair[1]), "gamepad button action isolated: " + str(pair[0]))
	for pair: Array in [[JOY_AXIS_TRIGGER_RIGHT, "drift"], [JOY_AXIS_TRIGGER_LEFT, "use_item_1"]]:
		var driver = Driver.new(0)
		driver.sample_local(_pad())
		_check(driver.sample_local(_pad({pair[0]: 0.5})) == Driver.neutral(), "digital trigger ignores half pressure and below")
		_check(_only(driver.sample_local(_pad({pair[0]: 0.75})), pair[1]), "trigger activates intended action above threshold")
		_check(driver.sample_local(_pad({pair[0]: NAN})) == Driver.neutral(), "nonfinite arcade trigger neutralized")
	var pad = Driver.new(0)
	pad.sample_local(_pad())
	_check(pad.sample_local(_pad({JOY_AXIS_TRIGGER_LEFT: 1.0})).use_item_1, "LT emits first item edge")
	_check(not pad.sample_local(_pad({JOY_AXIS_TRIGGER_LEFT: 1.0}, {JOY_BUTTON_LEFT_SHOULDER: true})).use_item_1, "LB alias cannot repeat held LT item")
	_check(not pad.sample_local(_pad({}, {JOY_BUTTON_LEFT_SHOULDER: true})).use_item_1, "releasing only one item alias does not rearm")
	pad.sample_local(_pad())
	_check(pad.sample_local(_pad({}, {JOY_BUTTON_LEFT_SHOULDER: true})).use_item_1, "releasing both aliases rearms item")
	pad.reset()
	_check(pad.sample_local(_pad({JOY_AXIS_TRIGGER_RIGHT: 1.0}, {JOY_BUTTON_A: true, JOY_BUTTON_Y: true})) == Driver.neutral(), "arcade held inputs rearm after interruption")
	pad.sample_local(_pad())
	var resumed: Dictionary = pad.sample_local(_pad({JOY_AXIS_TRIGGER_RIGHT: 1.0}, {JOY_BUTTON_A: true, JOY_BUTTON_Y: true}))
	_check(resumed.throttle == 1.0 and resumed.drift and resumed.use_item_2, "arcade controls resume after neutral")
	_check_network_map()
	print("ARCADE_INPUT_PROBE %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _check_network_map() -> void:
	var expected: Dictionary = {
		"drive_left": [["key", KEY_A], ["key", KEY_LEFT], ["axis", JOY_AXIS_LEFT_X, -1.0]],
		"drive_right": [["key", KEY_D], ["key", KEY_RIGHT], ["axis", JOY_AXIS_LEFT_X, 1.0]],
		"drive_accelerate": [["key", KEY_SPACE], ["button", JOY_BUTTON_A]],
		"drive_brake": [["key", KEY_C], ["button", JOY_BUTTON_B]],
		"drive_drift": [["key", KEY_SHIFT], ["key", KEY_E], ["button", JOY_BUTTON_RIGHT_SHOULDER], ["axis", JOY_AXIS_TRIGGER_RIGHT, 1.0]],
		"use_item_1": [["key", KEY_Q], ["button", JOY_BUTTON_LEFT_SHOULDER], ["axis", JOY_AXIS_TRIGGER_LEFT, 1.0]],
		"use_item_2": [["key", KEY_T], ["button", JOY_BUTTON_Y]],
		"look_back": [["key", KEY_F], ["button", JOY_BUTTON_X]],
		"pause_menu": [["key", KEY_TAB], ["key", KEY_ESCAPE], ["button", JOY_BUTTON_START]],
	}
	for action: String in expected:
		var actual: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				actual.append(["key", event.physical_keycode])
			elif event is InputEventJoypadButton:
				actual.append(["button", event.button_index])
			elif event is InputEventJoypadMotion:
				actual.append(["axis", event.axis, event.axis_value])
		_check(actual == expected[action], "network InputMap matches arcade: " + action)
	_check(is_equal_approx(InputMap.action_get_deadzone("drive_drift"), 0.5) and is_equal_approx(InputMap.action_get_deadzone("use_item_1"), 0.5), "network and local digital trigger threshold match")


func _only(command: Dictionary, action: String) -> bool:
	var expected: Dictionary = Driver.neutral()
	expected[action] = 1.0 if action in Driver.AXIS_ACTIONS else true
	return command == expected


func _keys(keys: Dictionary = {}) -> Dictionary:
	return {"connected": true, "keys": keys}


func _pad(axes: Dictionary = {}, buttons: Dictionary = {}) -> Dictionary:
	return {"connected": true, "axes": axes, "buttons": buttons}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
