class_name LocalPlayerInputs
extends RefCounted

signal device_disconnected(seat: int, device: int)

const Driver = preload("res://input/driver_input.gd")
const MAX_PLAYERS: int = 4
var _drivers: Dictionary = {}
var _connected: Dictionary = {}
var _suspended: bool = false
var _focused: bool = true


func assign(seat: int, device: int, available_pads: Variant = null) -> bool:
	if seat < 0 or seat >= MAX_PLAYERS or device < Driver.KEYBOARD:
		return false
	var pads: Variant = Input.get_connected_joypads() if available_pads == null else available_pads
	if device != Driver.KEYBOARD and device not in pads:
		return false
	for other: int in _drivers:
		if other != seat and _drivers[other].device == device:
			return false
	_drivers[seat] = Driver.new(device)
	_connected[seat] = true
	return true


func unassign(seat: int) -> void:
	_drivers.erase(seat)
	_connected.erase(seat)


func assignments() -> Dictionary:
	var result: Dictionary = {}
	for seat: int in _drivers:
		result[seat] = _drivers[seat].device
	return result


func set_suspended(value: bool) -> bool:
	if not value and false in _connected.values():
		return false
	if value != _suspended:
		_reset()
	_suspended = value
	return true


func is_suspended() -> bool:
	return _suspended


func set_focused(value: bool) -> void:
	if value != _focused:
		_reset()
	_focused = value


## Read once per physics tick, then route these immutable-by-convention commands by seat.
func sample_all(device_snapshots: Variant = null) -> Dictionary:
	var snapshots: Dictionary = {}
	var disconnected: Array[Dictionary] = []
	for seat: int in _drivers:
		var device: int = _drivers[seat].device
		var raw: Dictionary = Driver.read_device(device) if device_snapshots == null else device_snapshots.get(device, {"connected": false})
		snapshots[seat] = raw
		var connected: bool = bool(raw.get("connected", false))
		var was_connected: bool = bool(_connected.get(seat, false))
		_connected[seat] = connected
		if was_connected and not connected:
			disconnected.append({"seat": seat, "device": device})
	if not disconnected.is_empty():
		set_suspended(true)
	var result: Dictionary = {}
	for seat: int in _drivers:
		result[seat] = _drivers[seat].sample_local(snapshots[seat], _focused and not _suspended, _focused)
	# Listeners may reassign devices; finish this neutral frame before notifying them.
	for event: Dictionary in disconnected:
		device_disconnected.emit(event.seat, event.device)
	return result


func _reset() -> void:
	for driver: RefCounted in _drivers.values():
		driver.reset()
