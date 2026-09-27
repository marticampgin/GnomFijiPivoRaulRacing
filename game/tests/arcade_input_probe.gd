extends SceneTree

const Driver = preload("res://input/driver_input.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(Driver.default_profile().keyboard == "arcade" and Driver.default_profile().gamepad == "arcade", "arcade is default for both devices")
	for pair: Array in [[KEY_SPACE, "throttle"], [KEY_C, "brake"], [KEY_SHIFT, "drift_left"], [KEY_E, "drift_right"],
		[KEY_Q, "use_item"], [KEY_F, "look_back"], [KEY_TAB, "pause"], [KEY_ESCAPE, "pause"]]:
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
	_check(keyboard.sample_local(_keys({KEY_T: true})) == Driver.neutral(), "former second item key cannot bypass FIFO")
	_check(keyboard.sample_local(_keys({KEY_Q: true})).use_item, "Q emits the only item edge")
	_check(not keyboard.sample_local(_keys({KEY_Q: true})).use_item, "held Q does not repeat item")
	for pair: Array in [[JOY_BUTTON_A, "throttle"], [JOY_BUTTON_B, "brake"], [JOY_BUTTON_RIGHT_SHOULDER, "drift_right"],
		[JOY_BUTTON_LEFT_SHOULDER, "drift_left"], [JOY_BUTTON_Y, "use_item"], [JOY_BUTTON_X, "look_back"], [JOY_BUTTON_START, "pause"]]:
		var driver = Driver.new(0)
		driver.sample_local(_pad())
		_check(_only(driver.sample_local(_pad({}, {pair[0]: true})), pair[1]), "gamepad button action isolated: " + str(pair[0]))
	for trigger: int in [JOY_AXIS_TRIGGER_RIGHT, JOY_AXIS_TRIGGER_LEFT]:
		var driver = Driver.new(0)
		driver.sample_local(_pad())
		_check(driver.sample_local(_pad({trigger: 1.0})) == Driver.neutral(), "arcade triggers do not alias drift or items")
		_check(driver.sample_local(_pad({trigger: NAN})) == Driver.neutral(), "nonfinite arcade trigger neutralized")
	var pad = Driver.new(0)
	pad.sample_local(_pad())
	_check(pad.sample_local(_pad({}, {JOY_BUTTON_Y: true})).use_item, "Y emits FIFO item edge")
	var held: Dictionary = pad.sample_local(_pad({}, {JOY_BUTTON_Y: true, JOY_BUTTON_LEFT_SHOULDER: true, JOY_BUTTON_RIGHT_SHOULDER: true}))
	_check(not held.use_item and held.drift_left and held.drift_right, "shoulders remain distinct held inputs, not item aliases")
	pad.sample_local(_pad())
	_check(pad.sample_local(_pad({}, {JOY_BUTTON_Y: true})).use_item, "fresh Y press consumes next item")
	pad.reset()
	_check(pad.sample_local(_pad({}, {JOY_BUTTON_RIGHT_SHOULDER: true, JOY_BUTTON_A: true, JOY_BUTTON_Y: true})) == Driver.neutral(), "arcade held inputs rearm after interruption")
	pad.sample_local(_pad())
	var resumed: Dictionary = pad.sample_local(_pad({}, {JOY_BUTTON_RIGHT_SHOULDER: true, JOY_BUTTON_A: true, JOY_BUTTON_Y: true}))
	_check(resumed.throttle == 1.0 and resumed.drift_right and resumed.use_item, "arcade controls resume after neutral")
	_check_network_map()
	print("ARCADE_INPUT_PROBE %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _check_network_map() -> void:
	var expected: Dictionary = {
		"drive_left": [["key", KEY_A], ["key", KEY_LEFT], ["axis", JOY_AXIS_LEFT_X, -1.0]],
		"drive_right": [["key", KEY_D], ["key", KEY_RIGHT], ["axis", JOY_AXIS_LEFT_X, 1.0]],
		"drive_accelerate": [["key", KEY_SPACE], ["button", JOY_BUTTON_A]],
		"drive_brake": [["key", KEY_C], ["button", JOY_BUTTON_B]],
		"drive_drift_left": [["key", KEY_SHIFT], ["button", JOY_BUTTON_LEFT_SHOULDER]],
		"drive_drift_right": [["key", KEY_E], ["button", JOY_BUTTON_RIGHT_SHOULDER]],
		"use_item": [["key", KEY_Q], ["button", JOY_BUTTON_Y]],
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
	_check(not InputMap.has_action("use_item_1") and not InputMap.has_action("use_item_2"), "old independent slot actions removed")


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
