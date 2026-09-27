extends SceneTree

const Driver = preload("res://input/driver_input.gd")
const Seats = preload("res://input/local_player_inputs.gd")
var checks: int = 0
var failures: int = 0
var disconnects: Array = []
var disconnect_resume_attempts: Array = []


func _initialize() -> void:
	var seats = Seats.new()
	seats.device_disconnected.connect(func(seat: int, device: int): disconnects.append([seat, device]))
	seats.device_disconnected.connect(func(_seat: int, _device: int): disconnect_resume_attempts.append(seats.set_suspended(false)))
	_check(seats.assign(0, -1, [2, 7, 9]), "keyboard assigned")
	_check(not seats.assign(1, -1, [2, 7, 9]), "second keyboard rejected")
	_check(seats.assign(1, 2, [2, 7, 9]), "first gamepad assigned")
	_check(not seats.assign(2, 2, [2, 7, 9]), "duplicate gamepad rejected")
	_check(not seats.assign(2, 8, [2, 7, 9]), "unconnected gamepad rejected")
	_check(not seats.assign(2, -2, [2, 7, 9]), "invalid device rejected")
	_check(not seats.assign(-1, 7, [2, 7, 9]) and not seats.assign(4, 7, [2, 7, 9]), "invalid seats rejected")
	_check(seats.assign(2, 7, [2, 7, 9]) and seats.assign(3, 9, [2, 7, 9]), "four seats assigned")
	var raw: Dictionary = {-1: _keys(), 2: _pad(), 7: _pad(), 9: _pad()}
	seats.sample_all(raw)
	raw[-1] = _keys({KEY_W: true, KEY_Q: true, KEY_C: true})
	var commands: Dictionary = seats.sample_all(raw)
	_check(commands[0].throttle == 1.0 and commands[0].use_item_1 and commands[0].look_back, "keyboard maps drive item camera")
	_check(commands[1] == Driver.neutral() and commands[2] == Driver.neutral() and commands[3] == Driver.neutral(), "keyboard isolated from all gamepads")
	_check(not seats.sample_all(raw)[0].use_item_1, "held item fires once")
	raw[2] = _pad({JOY_AXIS_LEFT_X: -1.0, JOY_AXIS_TRIGGER_RIGHT: 1.0}, {JOY_BUTTON_LEFT_SHOULDER: true, JOY_BUTTON_START: true})
	commands = seats.sample_all(raw)
	_check(commands[1].steering == -1.0 and commands[1].throttle == 1.0 and commands[1].use_item_1 and commands[1].pause, "gamepad maps own axes item pause")
	_check(not commands[0].use_item_1 and commands[2] == Driver.neutral(), "gamepad edge independent of keyboard and second pad")
	_check(not seats.sample_all(raw)[1].pause, "pause is edge triggered")
	raw[9] = _pad({JOY_AXIS_LEFT_X: 0.6, JOY_AXIS_TRIGGER_LEFT: 1.0}, {JOY_BUTTON_A: true, JOY_BUTTON_Y: true, JOY_BUTTON_RIGHT_SHOULDER: true})
	commands = seats.sample_all(raw)
	_check(is_equal_approx(commands[3].steering, 0.5) and commands[3].brake == 1.0 and commands[3].drift and commands[3].look_back and commands[3].use_item_2, "fourth pad preserves analog steering and other actions")
	_check(not commands[1].use_item_1 and not commands[1].use_item_2, "fourth pad item does not create another pad edge")
	raw[7] = _pad({JOY_AXIS_LEFT_X: 0.1, JOY_AXIS_TRIGGER_LEFT: 0.05})
	_check(seats.sample_all(raw)[2] == Driver.neutral(), "stick and trigger deadzones")
	raw[7] = _pad({JOY_AXIS_LEFT_X: NAN, JOY_AXIS_TRIGGER_LEFT: INF})
	_check(seats.sample_all(raw)[2] == Driver.neutral(), "nonfinite axes neutralized")
	raw[-1] = _keys({KEY_A: true, KEY_RIGHT: true, KEY_S: true, KEY_SPACE: true, KEY_E: true, KEY_ESCAPE: true})
	commands = seats.sample_all(raw)
	_check(commands[0].steering == 0.0 and commands[0].brake == 1.0 and commands[0].drift and commands[0].use_item_2 and commands[0].pause, "keyboard alternatives and opposite directions")
	seats.set_suspended(true)
	_check(_all_neutral(seats.sample_all(raw)), "pause neutralizes every seat")
	raw[2] = _pad()
	seats.sample_all(raw)
	raw[2] = _pad({JOY_AXIS_TRIGGER_RIGHT: 1.0}, {JOY_BUTTON_START: true, JOY_BUTTON_LEFT_SHOULDER: true})
	commands = seats.sample_all(raw)
	_check(commands[1].pause and commands[1].throttle == 0.0 and not commands[1].use_item_1, "fresh pause edge available while driving and items suspended")
	_check(not seats.sample_all(raw)[1].pause, "held pause does not repeatedly request resume")
	seats.set_suspended(false)
	_check(_all_neutral(seats.sample_all(raw)), "held controls suppressed after resume")
	raw = {-1: _keys(), 2: _pad(), 7: _pad(), 9: _pad()}
	seats.sample_all(raw)
	raw[-1] = _keys({KEY_Q: true})
	_check(seats.sample_all(raw)[0].use_item_1, "release rearms item after pause")
	seats.set_focused(false)
	_check(_all_neutral(seats.sample_all(raw)), "focus loss neutralizes all seats")
	seats.set_focused(true)
	_check(not seats.sample_all(raw)[0].use_item_1, "focus regain does not use held item")
	raw.erase(2)
	_check(_all_neutral(seats.sample_all(raw)) and seats.is_suspended(), "disconnect suspends all seats")
	_check(disconnects == [[1, 2]], "disconnect emits seat and device once")
	_check(disconnect_resume_attempts == [false] and seats.is_suspended(), "synchronous disconnect listener cannot resume missing controller")
	seats.sample_all(raw)
	_check(disconnects.size() == 1 and not seats.set_suspended(false), "cannot resume missing controller")
	raw[2] = _pad({}, {JOY_BUTTON_LEFT_SHOULDER: true})
	_check(_all_neutral(seats.sample_all(raw)) and seats.is_suspended(), "reconnect does not auto resume")
	_check(seats.set_suspended(false), "explicit resume after reconnect")
	_check(not seats.sample_all(raw)[1].use_item_1, "reconnected held item suppressed")
	raw[2] = _pad()
	seats.sample_all(raw)
	raw[2] = _pad({}, {JOY_BUTTON_LEFT_SHOULDER: true})
	_check(seats.sample_all(raw)[1].use_item_1, "reconnected fresh item press accepted")
	_check(seats.assign(1, 5, [5]), "device reassigned")
	raw[5] = _pad({}, {JOY_BUTTON_RIGHT_SHOULDER: true})
	_check(not seats.sample_all(raw)[1].use_item_2, "reassignment held button suppressed")
	seats.unassign(0)
	_check(not seats.assignments().has(0) and seats.assign(0, 2, [2]), "keyboard optional all gamepad layout")
	var assignments: Dictionary = seats.assignments()
	assignments.clear()
	_check(seats.assignments().size() == 4, "assignment snapshot cannot mutate registry")
	var changing = Seats.new()
	changing.assign(0, 2, [2, 7])
	changing.assign(1, 7, [2, 7])
	var notices: Array = []
	changing.device_disconnected.connect(func(seat: int, device: int):
		notices.append([seat, device])
		changing.unassign(1)
		changing.assign(0, -1, []))
	_check(_all_neutral(changing.sample_all({})), "reassignment from disconnect listener preserves neutral frame")
	_check(notices == [[0, 2], [1, 7]], "disconnect notifications retain original devices across callback reassignment")
	for registry: RefCounted in [seats, changing]:
		for connection: Dictionary in registry.device_disconnected.get_connections():
			registry.device_disconnected.disconnect(connection.callable)
	print("LOCAL_INPUT_PROBE ", JSON.stringify({"checks": checks, "failures": failures, "physical_gamepads_verified": false}))
	quit(0 if failures == 0 else 1)


func _keys(keys: Dictionary = {}) -> Dictionary:
	return {"connected": true, "keys": keys}


func _pad(axes: Dictionary = {}, buttons: Dictionary = {}) -> Dictionary:
	return {"connected": true, "axes": axes, "buttons": buttons}


func _all_neutral(commands: Dictionary) -> bool:
	for command: Dictionary in commands.values():
		if command != Driver.neutral():
			return false
	return true


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
