class_name DriverInput
extends RefCounted

const KEYBOARD: int = -1
const BUTTON_ACTIONS: Array[String] = ["drift_left", "drift_right", "use_item", "look_back", "pause"]
const AXIS_ACTIONS: Array[String] = ["steering", "throttle", "brake"]
const EDGE_ACTIONS: Array[String] = ["use_item", "pause"]
var device: int = KEYBOARD
var _previous: Dictionary = {}
var _blocked: Dictionary = {}
var _rearm: bool = true
var _profile: Dictionary = default_profile()


func _init(source: int = KEYBOARD) -> void:
	device = source


static func default_profile() -> Dictionary:
	return {"keyboard": "arcade", "gamepad": "arcade", "deadzone": 0.2, "steering": 1.0}


static func validate_profile(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != 4:
		return {}
	if value.get("keyboard") not in ["arcade", "both", "wasd", "arrows"] or value.get("gamepad") not in ["arcade", "standard", "alternate"]:
		return {}
	for key: String in ["deadzone", "steering"]:
		if typeof(value.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[key])):
			return {}
	if float(value.deadzone) < 0.05 or float(value.deadzone) > 0.35 or float(value.steering) < 0.5 or float(value.steering) > 1.5:
		return {}
	return {"keyboard": value.keyboard, "gamepad": value.gamepad,
		"deadzone": float(value.deadzone), "steering": float(value.steering)}


func configure_profile(value: Variant) -> bool:
	var validated: Dictionary = validate_profile(value)
	if validated.is_empty():
		return false
	_profile = validated
	reset()
	return true


func profile() -> Dictionary:
	return _profile.duplicate()


static func neutral() -> Dictionary:
	return {"steering": 0.0, "throttle": 0.0, "brake": 0.0, "drift_left": false,
		"drift_right": false, "use_item": false, "look_back": false, "pause": false}


func reset() -> void:
	_previous.clear()
	_blocked.clear()
	_rearm = true


## Raw snapshots provide the same boundary for real devices and deterministic probes.
static func read_device(source: int) -> Dictionary:
	if source == KEYBOARD:
		var keys: Dictionary = {}
		for key: int in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN,
			KEY_SPACE, KEY_Q, KEY_E, KEY_C, KEY_ESCAPE, KEY_SHIFT, KEY_T, KEY_F, KEY_TAB]:
			keys[key] = Input.is_physical_key_pressed(key)
		return {"connected": true, "keys": keys}
	if source not in Input.get_connected_joypads():
		return {"connected": false}
	var axes: Dictionary = {}
	for axis: int in [JOY_AXIS_LEFT_X, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		axes[axis] = Input.get_joy_axis(source, axis)
	var buttons: Dictionary = {}
	for button: int in [JOY_BUTTON_A, JOY_BUTTON_Y, JOY_BUTTON_X, JOY_BUTTON_B, JOY_BUTTON_LEFT_SHOULDER,
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
		command.steering = float(_key_axis(keys, KEY_D, KEY_RIGHT)) - float(_key_axis(keys, KEY_A, KEY_LEFT))
		command.throttle = float(_key_axis(keys, KEY_W, KEY_UP))
		command.brake = float(_key_axis(keys, KEY_S, KEY_DOWN))
		command.drift_left = bool(keys.get(KEY_SHIFT, false))
		command.drift_right = bool(keys.get(KEY_E, false))
		command.use_item = bool(keys.get(KEY_Q, false))
		command.look_back = bool(keys.get(KEY_C, false))
		command.pause = bool(keys.get(KEY_ESCAPE, false))
		if _profile.keyboard == "arcade":
			command.throttle = float(bool(keys.get(KEY_SPACE, false)))
			command.brake = float(bool(keys.get(KEY_C, false)))
			command.look_back = bool(keys.get(KEY_F, false))
			command.pause = command.pause or bool(keys.get(KEY_TAB, false))
	else:
		var axes: Dictionary = raw.get("axes", {})
		var buttons: Dictionary = raw.get("buttons", {})
		command.steering = _axis(float(axes.get(JOY_AXIS_LEFT_X, 0.0)), _profile.deadzone, true)
		command.throttle = _axis(float(axes.get(JOY_AXIS_TRIGGER_RIGHT, 0.0)), 0.1, false)
		command.brake = _axis(float(axes.get(JOY_AXIS_TRIGGER_LEFT, 0.0)), 0.1, false)
		command.drift_left = bool(buttons.get(JOY_BUTTON_LEFT_SHOULDER, false))
		command.drift_right = bool(buttons.get(JOY_BUTTON_RIGHT_SHOULDER, false))
		command.use_item = bool(buttons.get(JOY_BUTTON_Y, false))
		command.look_back = bool(buttons.get(JOY_BUTTON_B if _profile.gamepad == "alternate" else JOY_BUTTON_X, false))
		command.pause = bool(buttons.get(JOY_BUTTON_START, false))
		if _profile.gamepad == "arcade":
			command.throttle = float(bool(buttons.get(JOY_BUTTON_A, false)))
			command.brake = float(bool(buttons.get(JOY_BUTTON_B, false)))
			command.look_back = bool(buttons.get(JOY_BUTTON_X, false))
	command.steering = clampf(command.steering * _profile.steering, -1.0, 1.0)
	return command


func _key_axis(keys: Dictionary, first: int, second: int) -> bool:
	return (_profile.keyboard != "arrows" and bool(keys.get(first, false))) or (_profile.keyboard != "wasd" and bool(keys.get(second, false)))


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
		"drift_left": Input.is_action_pressed("drive_drift_left"),
		"drift_right": Input.is_action_pressed("drive_drift_right"),
		"use_item": Input.is_action_just_pressed("use_item"),
		"look_back": Input.is_action_pressed("look_back"),
	}
