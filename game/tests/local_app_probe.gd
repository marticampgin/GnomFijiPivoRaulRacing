extends SceneTree

class TestApp extends "res://app/prototype.gd":
	var requested: int = 0

	func _physics_process(delta: float) -> void:
		if requested > 0:
			requested -= 1
			super._physics_process(delta)

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _step(app: TestApp) -> void:
	app.requested = 1
	while app.requested > 0:
		await physics_frame
		await process_frame


func _run() -> void:
	var app := TestApp.new()
	root.add_child(app)
	app._on_local_message({"type": "local_start", "seats": [{"device": -1, "style_id": "speed"}], "layout": "side-by-side"})
	await _step(app)
	var session: Node3D = app._local_race
	_check(is_instance_valid(session) and app._socket == null, "local bridge creates authority without a socket")
	_check(app._local_view.sectors().size() == 1 and root.disable_3d, "local camera replaces root render")
	var hud: Dictionary = app._local_hud_state()
	_check(hud.seats.size() == 1 and hud.players.size() == 10, "bridge publishes complete local grid")
	_check(hud.seats[0].styleId == "speed" and hud.seats[0].device == -1, "seat style and device survive the bridge")
	_check(hud.trackDescriptor.track_id == "castle-waterfalls", "local HUD uses authored route")
	app._on_local_message({"type": "local_start", "seats": [{"device": -1}, {"device": -1}]})
	_check(app._local_race == session, "invalid start preserves active local session")
	session._phase = "racing"
	session._countdown = 0
	var player: Dictionary = session._players["local:0"]
	player.combat.slots = ["fanta", "mermaid_rum"]
	player.combat.health = 30.0
	app._on_local_message({"type": "local_use_item", "seat": 0, "slot": 1})
	await _step(app)
	hud = app._local_hud_state()
	_check(hud.seats[0].items == ["fanta", ""] and hud.seats[0].health > 30.0, "local item button reaches the shared simulation")
	_check(hud.seats[0].blurIntensity > 0.0, "drink blur reaches only the owning seat projection")
	app._on_local_message({"type": "local_pause"})
	var tick: int = session._tick
	await _step(app)
	_check(app._local_hud_state().paused and session._tick == tick, "pause bridge freezes authority")
	var epoch: int = player.epoch
	app._on_local_message({"type": "local_recover", "seat": 0})
	_check(not session.is_paused_local() and player.epoch == epoch + 1, "pause recovery explicitly resumes then recovers")
	session._phase = "results"
	player.dnf = true
	var race_id: int = session._race_id
	app._on_local_message({"type": "local_ready", "seat": 0})
	await _step(app)
	_check(session._race_id == race_id + 1 and session._phase == "countdown", "local result button starts one rematch")
	_check(app._local_hud_state().seats[0].items == ["", ""], "rematch clears projected inventory")
	app._on_local_message({"type": "local_leave"})
	_check(not is_instance_valid(app._local_race) and not is_instance_valid(app._local_view), "leave removes local authority and views")
	_check(not root.disable_3d and app._camera.current, "leave restores network/practice rendering")
	app.free()
	await process_frame
	print("LOCAL_APP_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
