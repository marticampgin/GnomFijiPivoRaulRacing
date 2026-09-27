extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Protocol = preload("res://net/prototype_protocol.gd")
const DT: float = 1.0 / 60.0
const BRAKE: Dictionary = {"steering": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false}

class TestApp extends "res://app/prototype.gd":
	func _ready() -> void:
		pass

var checks: int = 0
var failures: int = 0
var app: TestApp
var player: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	app = TestApp.new()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app._track = Track.new()
	app.add_child(app._track)
	app._track.build(false)
	player = app._new_player("probe", "P1", 0, false)
	app._players["probe"] = player
	for gate: String in ["countdown", "finished", "spectator", "stale", "disconnected"]:
		await _reset()
		app._phase = "countdown" if gate == "countdown" else "racing"
		app._countdown = 300 if gate == "countdown" else 0
		player.finished = gate == "finished"
		player.spectator = gate == "spectator"
		player.connected = gate != "disconnected"
		player.last_input_at = Time.get_ticks_msec() - (app.INPUT_TIMEOUT_MS + 100 if gate == "stale" else 0)
		player.input = BRAKE.duplicate()
		player.vehicle.boost_remaining = 2.0
		for tick: int in 8:
			await physics_frame
			app._step_session(DT)
		_check(player.vehicle.speed_mps < 0.05, "shared authority parks held brake and boost for " + gate)
	app._local = player.vehicle
	for gate: String in ["countdown", "finished", "spectator", "focus", "menu"]:
		await _reset()
		app._phase = "countdown" if gate == "countdown" else "racing"
		app._status = "racing"
		app._hud = {"finished": gate == "finished", "spectator": gate == "spectator"}
		app._focused = gate != "focus"
		app._input_enabled = gate != "menu"
		player.vehicle.boost_remaining = 2.0
		for tick: int in 8:
			await physics_frame
			app._step_local(BRAKE, DT)
		_check(player.vehicle.speed_mps < 0.05, "client prediction parks held brake and boost for " + gate)
		if gate in ["focus", "menu"]:
			_check(app._sample_input() == Protocol.NEUTRAL, "unfocused/menu input sends safe neutral without parking flag")
	await _reset()
	app._phase = "racing"
	app._status = "racing"
	app._hud = {}
	app._focused = true
	app._input_enabled = true
	for tick: int in 8:
		await physics_frame
		app._step_local(BRAKE, DT)
	_check(player.vehicle.velocity.dot(-player.vehicle.global_basis.z) < -0.5, "enabled client still reverses with held brake")
	print("REVERSE_GATES_PROBE %d/%d passed" % [checks - failures, checks])
	app.free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _reset() -> void:
	player.vehicle.reset_at(app._track.spawn_transform(0))
	player.finished = false
	player.spectator = false
	player.connected = true
	player.dnf = false
	player.combat.effects = {}
	for tick: int in 30:
		await physics_frame
		player.vehicle.step(Protocol.BLOCKED, DT)
	_check(player.vehicle.grounded, "gate fixture settles on authored track")
	player.vehicle.velocity = Vector3.ZERO


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
