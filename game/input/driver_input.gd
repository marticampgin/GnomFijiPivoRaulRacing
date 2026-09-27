class_name DriverInput
extends RefCounted

const KEYBOARD: int = -1
const BUTTON_ACTIONS: Array[String] = ["drift", "use_item_1", "use_item_2", "look_back", "pause"]
const AXIS_ACTIONS: Array[String] = ["steering", "throttle", "brake"]
const EDGE_ACTIONS: Array[String] = ["use_item_1", "use_item_2", "pause"]
var device: int = KEYBOARD
var _previous: Dictionary = {}
var _blocked: Dictionary = {}
var _rearm: bool = true


func _init(source: int = KEYBOARD) -> void:
	device = source


static func neutral() -> Dictionary:
	return {"steering": 0.0, "throttle": 0.0, "brake": 0.0, "drift": false,
		"use_item_1": false, "use_item_2": false, "look_back": false, "pause": false}


func reset() -> void:
	_previous.clear()
	_blocked.clear()
	_rearm = true


## Raw snapshots provide the same boundary for real devices and deterministic probes.
static func read_device(source: int) -> Dictionary:
	if source == KEYBOARD:
		var keys: Dictionary = {}
		for key: int in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN,
			KEY_SPACE, KEY_Q, KEY_E, KEY_C, KEY_ESCAPE]:
			keys[key] = Input.is_physical_key_pressed(key)
		return {"connected": true, "keys": keys}
	if source not in Input.get_connected_joypads():
		return {"connected": false}
	var axes: Dictionary = {}
	for axis: int in [JOY_AXIS_LEFT_X, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		axes[axis] = Input.get_joy_axis(source, axis)
	var buttons: Dictionary = {}
	for button: int in [JOY_BUTTON_A, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
		JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START]:
		buttons[button] = Input.is_joy_button_pressed(source, button)
	return {"connected": true, "axes": axes, "buttons": buttons}


func sample_local(snapshot: Variant = null, enabled: bool = true, menu_enabled: bool = false) -> Dictionary:
	var raw: Dictionary = read_device(device) if snapshot == null else snapshot
	if (not enabled and not menu_enabled) or not bool(raw.get("connected", false)):
		reset()
		return neutral()
	var command: Dictionary = _decode(raw)
	# Every held control must return to neutral after a lifecycle interruption.
	for action: String in AXIS_ACTIONS + BUTTON_ACTIONS:
		var held: bool = absf(float(command[action])) > 0.0
		if _rearm and held:
			_blocked[action] = true
		if not held:
			_blocked.erase(action)
		if _blocked.has(action):
			command[action] = 0.0 if action in AXIS_ACTIONS else false
	_rearm = false
	for action: String in EDGE_ACTIONS:
		var held: bool = bool(command[action])
		command[action] = held and not bool(_previous.get(action, false))
		_previous[action] = held
	if not enabled:
		var menu_command: Dictionary = neutral()
		menu_command.pause = command.pause
		return menu_command
	return command


func _decode(raw: Dictionary) -> Dictionary:
	var command: Dictionary = neutral()
	if device == KEYBOARD:
		var keys: Dictionary = raw.get("keys", {})
		command.steering = float(_pressed(keys, KEY_D, KEY_RIGHT)) - float(_pressed(keys, KEY_A, KEY_LEFT))
		command.throttle = float(_pressed(keys, KEY_W, KEY_UP))
		command.brake = float(_pressed(keys, KEY_S, KEY_DOWN))
		command.drift = bool(keys.get(KEY_SPACE, false))
		command.use_item_1 = bool(keys.get(KEY_Q, false))
		command.use_item_2 = bool(keys.get(KEY_E, false))
		command.look_back = bool(keys.get(KEY_C, false))
		command.pause = bool(keys.get(KEY_ESCAPE, false))
	else:
		var axes: Dictionary = raw.get("axes", {})
		var buttons: Dictionary = raw.get("buttons", {})
		command.steering = _axis(float(axes.get(JOY_AXIS_LEFT_X, 0.0)), 0.2, true)
		command.throttle = _axis(float(axes.get(JOY_AXIS_TRIGGER_RIGHT, 0.0)), 0.1, false)
		command.brake = _axis(float(axes.get(JOY_AXIS_TRIGGER_LEFT, 0.0)), 0.1, false)
		command.drift = bool(buttons.get(JOY_BUTTON_A, false))
		command.use_item_1 = bool(buttons.get(JOY_BUTTON_LEFT_SHOULDER, false))
		command.use_item_2 = bool(buttons.get(JOY_BUTTON_RIGHT_SHOULDER, false))
		command.look_back = bool(buttons.get(JOY_BUTTON_Y, false))
		command.pause = bool(buttons.get(JOY_BUTTON_START, false))
	return command


static func _pressed(keys: Dictionary, first: int, second: int) -> bool:
	return bool(keys.get(first, false)) or bool(keys.get(second, false))


static func _axis(value: float, deadzone: float, signed: bool) -> float:
	if not is_finite(value):
		return 0.0
	value = clampf(value, -1.0 if signed else 0.0, 1.0)
	return signf(value) * maxf(0.0, (absf(value) - deadzone) / (1.0 - deadzone))


## Read once per physics tick. Future touch controls can drive the same InputMap actions.
## This is local input only; the server must validate and sequence network commands.
static func sample() -> Dictionary:
	return {
		"steering": Input.get_axis("drive_left", "drive_right"),
		"throttle": Input.get_action_strength("drive_accelerate"),
		"brake": Input.get_action_strength("drive_brake"),
		"drift": Input.is_action_pressed("drive_drift"),
		"use_item_1": Input.is_action_just_pressed("use_item_1"),
		"use_item_2": Input.is_action_just_pressed("use_item_2"),
		"look_back": Input.is_action_pressed("look_back"),
	}
