extends SceneTree

const DT: float = 1.0 / 60.0

class TestApp extends "res://app/prototype.gd":
	var sent: Array[Dictionary] = []
	var samples: int = 0
	var predicted: int = 0
	var leave_reason: String = ""

	func _ready() -> void:
		pass

	func _poll_client() -> void:
		pass

	func _update_camera(_delta: float) -> void:
		pass

	func _sample_input() -> Dictionary:
		samples += 1
		return Protocol.NEUTRAL.duplicate()

	func _send(packet: Dictionary) -> void:
		sent.append(packet.duplicate(true))

	func _step_local(_command: Dictionary, _delta: float) -> void:
		predicted += 1

	func _leave(reason: String) -> void:
		leave_reason = reason
		_joined = false

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := TestApp.new()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app._local = CharacterBody3D.new()
	app.add_child(app._local)
	app._joined = true
	app._status = "racing"
	app._last_server_ms = Time.get_ticks_msec()
	_step(app, 60)
	_check(app.sent.size() == 24, "missing acknowledgements cap transmitted input at 24")
	_check(app._sequence == 24, "blocked transmission does not advance input sequence")
	_check(app._pending.size() == 24, "prediction history remains bounded by unacknowledged window")
	_check(app.predicted == 24, "prediction does not run ahead when transmission is blocked")
	_check(app.samples == 60, "input and item edges are still sampled while transmission is blocked")
	_check(app.leave_reason.is_empty(), "temporary acknowledgement delay does not disconnect")
	app._pending.clear()
	_step(app, 10)
	_check(app.sent.size() == 24, "clearing prediction history alone does not grant send credit")
	_check(app.predicted == 24, "epoch history reset alone cannot advance prediction")
	var has_ack: bool = false
	for property: Dictionary in app.get_property_list():
		if property.name == "_input_ack":
			has_ack = true
	_check(has_ack, "network acknowledgements have independent flow-control state")
	if has_ack:
		app.set("_input_ack", 12)
		_step(app, 30)
		_check(app.sent.size() == 36, "acknowledging twelve inputs permits exactly twelve new inputs")
		_check(app._sequence == 36, "resumed inputs preserve monotonic sequence")
		_check(app.predicted == 36, "prediction resumes for newly transmitted inputs only")
		_check(app.samples == 100, "sampling remains active through resumed and blocked ticks")
		app.set("_input_ack", 36)
		_step(app, 24)
		_check(app.sent.size() == 60, "full acknowledgement grants a fresh bounded window")
		var valid_sequence: bool = true
		for index: int in app.sent.size():
			valid_sequence = valid_sequence and app.sent[index].get("type") == "input" and app.sent[index].get("sequence") == index + 1
		_check(valid_sequence, "flow-control pauses do not duplicate or skip wire sequences")
	app._last_server_ms = Time.get_ticks_msec() - 3001
	_step(app, 1)
	_check(app.leave_reason == "connection_lost", "flow control preserves stale-connection timeout")
	_check(not app._joined, "timeout leaves the joined session")
	print("INPUT_BACKPRESSURE_PROBE %d/%d passed" % [checks - failures, checks])
	app.free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _step(app: TestApp, count: int) -> void:
	for tick: int in count:
		app._physics_process(DT)


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
