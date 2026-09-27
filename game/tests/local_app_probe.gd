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
	app._on_local_message({"type": "local_start", "seats": [{"device": -1, "style_id": "speed"}], "layout": "side-by-side", "botDifficulty": "hard"})
	await _step(app)
	var session: Node3D = app._local_race
	_check(is_instance_valid(session) and app._socket == null, "local bridge creates authority without a socket")
	_check(app._local_view.sectors().size() == 1 and root.disable_3d, "local camera replaces root render")
	var hud: Dictionary = app._local_hud_state()
	_check(hud.seats.size() == 1 and hud.players.size() == 10, "bridge publishes complete local grid")
	_check(hud.seats[0].styleId == "speed" and hud.seats[0].device == -1, "seat style and device survive the bridge")
	_check(hud.trackDescriptor.track_id == "castle-waterfalls", "local HUD uses authored route")
	_check(hud.botDifficulty == "hard", "chosen bot difficulty reaches authority and HUD")
	_check(hud.seats[0].controls.keyboard == "arcade", "default local controls reach HUD")
	var controls: Dictionary = {"keyboard": "arrows", "gamepad": "alternate", "deadzone": 0.12, "steering": 0.8}
	app._on_local_message({"type": "local_start", "seats": [{"device": -1, "controls": {"keyboard": "invalid"}}]})
	_check(app._local_race == session, "invalid controls cannot replace active session")
	app._on_local_message({"type": "local_controls", "seat": 0, "controls": controls})
	_check(session.inputs.profiles()[0].keyboard == "arcade", "in-race control changes require pause")
	app._on_local_message({"type": "local_start", "seats": [{"device": -1}], "botDifficulty": "cheat"})
	_check(app._local_race == session, "invalid difficulty preserves active race")
	app._on_local_message({"type": "local_start", "seats": [{"device": -1}, {"device": -1}]})
	_check(app._local_race == session, "invalid start preserves active local session")
	session._phase = "racing"
	session._countdown = 0
	var player: Dictionary = session._players["local:0"]
	player.combat.shards = 7
	player.vehicle.drift_charge = 0.75
	player.vehicle.drift_chain = 2
	player.vehicle.drift_owner = -1
	player.vehicle.is_drifting = true
	player.vehicle.drift_feedback = "ready"
	player.driving.slipstream_charge = 0.5
	hud = app._local_hud_state()
	_check(hud.seats[0].shards == 7 and hud.seats[0].shardCap == 20, "race-only shard reserve reaches owning HUD")
	_check(hud.seats[0].driftLevel == 2 and hud.seats[0].driftSegments == [1.0, 1.0, 0.0], "HUD shows successful chain boosts independently of current charge")
	_check(hud.seats[0].drift == 0.75 and hud.seats[0].driftOwner == -1 and hud.seats[0].driftActive and hud.seats[0].driftFeedback == "ready", "HUD carries timing meter and opposite shoulder ownership")
	_check(hud.seats[0].driftWindowStart == app.Vehicle.DRIFT_READY_CHARGE, "HUD window matches shared simulation balance")
	_check(hud.seats[0].driving.slipstream_charge == 0.5, "authoritative technique state reaches owning HUD")
	var projectile_position: Vector3 = player.vehicle.global_position + player.vehicle.global_basis.z * 8.0
	var warning_world: Dictionary = {"projectiles": [{"kind": "seeker", "target": player.id, "position": [projectile_position.x, projectile_position.y, projectile_position.z]}]}
	_check(app._attack_warning(warning_world, player.id, player.vehicle) == "rear", "incoming marker uses actual rear direction")
	_check(app._attack_warning(warning_world, "another-seat", player.vehicle) == "", "warning never leaks to another seat")
	projectile_position = player.vehicle.global_position + player.vehicle.global_basis.x * 8.0
	warning_world.projectiles[0].position = [projectile_position.x, projectile_position.y, projectile_position.z]
	_check(app._attack_warning(warning_world, player.id, player.vehicle) == "right", "warning follows actual side instead of hardcoded rear")
	player.combat.slots = ["crystal_shield", "rear_trap"]
	player.combat.effects.burn = {"remaining": 3.0, "damage": 4.0}
	app._on_local_message({"type": "local_use_item", "seat": 0, "slot": 1})
	_check(player.item_queue.is_empty(), "legacy reserve selection cannot bypass FIFO through host bridge")
	app._on_local_message({"type": "local_use_item", "seat": 0})
	await _step(app)
	hud = app._local_hud_state()
	_check(hud.seats[0].items == ["rear_trap", ""] and hud.seats[0].effects.has("crystal_shield") and hud.seats[0].effects.has("burn"), "shield advances reserve without clearing incoming burn")
	var visual: Node3D = app._local_view._visuals[player.vehicle.get_instance_id()]
	_check(is_instance_valid(visual._shield_aura) and visual._shield_aura.visible, "shared view renders shield on the owning kart")
	app._on_local_message({"type": "local_use_item", "seat": 0})
	await _step(app)
	_check(session._items.world_state().projectiles.any(func(projectile: Dictionary) -> bool: return projectile.kind == "rear_trap"), "local item command deploys a real shared trap")
	var shield_time: float = float(player.combat.effects.crystal_shield.remaining)
	app._on_local_message({"type": "local_pause"})
	await _step(app)
	_check(float(player.combat.effects.crystal_shield.remaining) == shield_time, "local pause freezes shield duration")
	app._on_local_message({"type": "local_resume"})
	player.combat.effects.clear()
	player.vehicle.velocity = player.vehicle.global_basis.z * 2.0
	_check(app._local_hud_state().seats[0].reverse, "reverse indicator follows actual signed motion")
	player.vehicle.velocity = -player.vehicle.global_basis.z * 2.0
	_check(not app._local_hud_state().seats[0].reverse, "forward motion clears R")
	player.combat.slots = ["mermaid_rum", "fanta"]
	player.combat.health = 30.0
	app._on_local_message({"type": "local_use_item", "seat": 0})
	await _step(app)
	hud = app._local_hud_state()
	_check(hud.seats[0].items == ["fanta", ""] and hud.seats[0].health > 30.0, "local item button reaches the shared simulation")
	_check(hud.seats[0].blurIntensity > 0.0, "drink blur reaches only the owning seat projection")
	app._on_local_message({"type": "local_pause"})
	var tick: int = session._tick
	await _step(app)
	_check(app._local_hud_state().paused and session._tick == tick, "pause bridge freezes authority")
	app._on_local_message({"type": "local_controls", "seat": 0, "controls": controls})
	_check(app._local_hud_state().seats[0].controls == controls, "paused profile changes reach input and HUD")
	var epoch: int = player.epoch
	app._on_local_message({"type": "local_recover", "seat": 0})
	_check(not session.is_paused_local() and player.epoch == epoch + 1, "pause recovery explicitly resumes then recovers")
	session._phase = "results"
	player.dnf = true
	var race_id: int = session._race_id
	app._on_local_message({"type": "local_ready", "seat": 0})
	await _step(app)
	_check(session._race_id == race_id + 1 and session._phase == "countdown", "local result button starts one rematch")
	_check(app._local_hud_state().botDifficulty == "hard", "rematch keeps chosen difficulty")
	_check(app._local_hud_state().seats[0].controls == controls, "rematch preserves local control profile")
	_check(app._local_hud_state().seats[0].items == ["", ""], "rematch clears projected inventory")
	_check(app._local_hud_state().seats[0].shards == 0 and app._local_hud_state().seats[0].driving.slipstream_charge == 0.0, "rematch clears shards and technique HUD")
	_check(not visual._shield_aura.visible and session._items.world_state().projectiles.is_empty() and app._local_hud_state().seats[0].attackWarning == "", "rematch clears shield visuals, traps and attack warning")
	app._on_local_message({"type": "local_leave"})
	_check(not is_instance_valid(app._local_race) and not is_instance_valid(app._local_view), "leave removes local authority and views")
	_check(not root.disable_3d and app._camera.current, "leave restores network/practice rendering")
	app._on_local_message({"type": "local_start", "tutorial": true, "seats": [{"device": -1, "controls": controls}]})
	await _step(app)
	_check(app._local_hud_state().players.size() == 1 and app._local_hud_state().tutorial.step == "drive", "tutorial bridge starts one human without bots")
	_check(app._local_hud_state().seats[0].controls == controls, "tutorial uses selected controls")
	var tutorial_id: int = app._local_race._race_id
	app._on_local_message({"type": "local_tutorial_retry"})
	_check(app._local_race._race_id == tutorial_id + 1 and app._local_hud_state().tutorial.stage == 0, "tutorial retry resets through shared lifecycle")
	app._on_local_message({"type": "local_leave"})
	app.free()
	await process_frame
	print("LOCAL_APP_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
