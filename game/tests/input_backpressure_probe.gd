extends SceneTree

const DT: float = 1.0 / 60.0

class TestApp extends "res://app/prototype.gd":
	var sent: Array[Dictionary] = []
	var samples: int = 0
	var predicted: int = 0
	var leave_reason: String = ""
	var held: Dictionary = {"drift_left": false, "drift_right": false}

	func _ready() -> void:
		pass

	func _poll_client() -> void:
		pass

	func _update_camera(_delta: float) -> void:
		pass

	func _sample_input() -> Dictionary:
		samples += 1
		var command: Dictionary = Protocol.NEUTRAL.duplicate()
		command.merge(held, true)
		return command

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
	app.held = {"drift_left": true, "drift_right": false}
	_step(app, 1)
	app.held.drift_right = true
	_step(app, 1)
	app.held.drift_right = false
	_step(app, 1)
	_check(app.sent.size() == 60, "brief shoulder press waits behind full input window")
	app._input_ack = 60
	_step(app, 3)
	_check(app.sent[60].drift_left and not app.sent[60].drift_right, "initiating shoulder transition preserved")
	_check(app.sent[61].drift_left and app.sent[61].drift_right, "short opposite tap preserved under backpressure")
	_check(app.sent[62].drift_left and not app.sent[62].drift_right, "opposite release follows preserved tap")
	_step(app, 1)
	_check(not app.sent[63].drift_right, "tap is not repeatedly replayed")
	app._capture_drift_transition({"drift_left": true, "drift_right": true})
	app._release_inputs()
	_check(app._drift_transitions == [{"drift_left": false, "drift_right": false}], "focus cancellation replaces deferred taps with neutral boundary")
	app._input_ack = app._sequence - 24
	app.held = {"drift_left": true, "drift_right": false}
	_step(app, 1)
	_check(app._drift_transitions.size() == 2, "new shoulder after interruption queues after neutral while window full")
	var before_cancel_send: int = app.sent.size()
	app._input_ack = app._sequence
	_step(app, 2)
	_check(not app.sent[before_cancel_send].drift_left and not app.sent[before_cancel_send].drift_right, "first resumed input cancels old authoritative drift")
	_check(app.sent[before_cancel_send + 1].drift_left, "fresh drift follows authoritative cancellation boundary")
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
