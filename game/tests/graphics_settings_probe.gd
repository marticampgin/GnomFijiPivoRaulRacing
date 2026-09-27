extends SceneTree

const Track = preload("res://track/authored_track.gd")
const Kart = preload("res://vehicle/prototype_kart.gd")

class TestClient extends "res://app/prototype.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var client := TestClient.new()
	root.add_child(client)
	client._track = Track.new()
	client.add_child(client._track)
	client._track.build(false)
	client._sun = DirectionalLight3D.new()
	client.add_child(client._sun)
	client._kart_script = Kart
	client._local = client._create_vehicle(0, true)
	client._local.reset_at(client._track.spawn_transform(0))
	client._local.drift_charge = 0.7
	client._local.boost_remaining = 1.2
	client._hud = {"lap": 2, "epoch": 3}
	client._sequence = 17
	client._pending = [{"sequence": 17}]
	var remote: Node3D = client._create_kart_visual()
	client.add_child(remote)
	client._remotes["other"] = {"node": remote, "samples": []}
	var before: Dictionary = client._local.capture_state()
	var identity: Dictionary = client._track.identity()
	var collision_count: int = client._track.get_child_count()
	client._apply_graphics_settings("low", true)
	_check(client._quality == "low" and client._reduced_effects, "Low and reduced-effects applied")
	_check(is_equal_approx(root.scaling_3d_scale, 0.75), "Low changes 3D render scale")
	_check(root.msaa_3d == Viewport.MSAA_DISABLED, "Low disables MSAA")
	_check(is_equal_approx(client._sun.directional_shadow_max_distance, 45.0), "Low shortens shadow distance")
	_check(client._local_visual._reduced_effects and remote._reduced_effects, "effects applied to local and remote visuals")
	client._local_visual.update_visual(0.1, 20.0, 0.5, true, 1.0)
	_check(client._local_visual._trails.visible and client._local_visual._trails.scale.z < 0.5, "reduced boost remains visible with a short trail")
	_check(is_zero_approx(client._local_visual._driver.position.y), "reduced effects suppress driver bounce")
	_check(client._local.capture_state() == before, "quality and animation preserve entire vehicle state")
	_check(client._track.identity() == identity and client._track.get_child_count() == collision_count, "quality preserves simulation identity and collisions")
	_check(client._hud == {"lap": 2, "epoch": 3} and client._sequence == 17 and client._pending == [{"sequence": 17}], "quality preserves progress and input epoch/queue")
	var new_remote: Node3D = client._create_kart_visual()
	_check(new_remote._reduced_effects, "newly created remote inherits reduced effects")
	new_remote.free()
	client._on_host_message([JSON.stringify({"type": "graphics", "quality": "ultra", "reduced_effects": false})])
	_check(client._quality == "low" and client._reduced_effects, "unknown profile rejected")
	client._on_host_message([JSON.stringify({"type": "graphics", "quality": "standard", "reduced_effects": "false"})])
	_check(client._quality == "low" and client._reduced_effects, "incorrect field type rejected")
	client._on_host_message([JSON.stringify({"type": "graphics", "quality": "standard", "reduced_effects": false})])
	_check(client._quality == "standard" and not client._reduced_effects, "host can restore Standard")
	_check(is_equal_approx(root.scaling_3d_scale, 1.0) and root.msaa_3d == Viewport.MSAA_2X, "Standard restores native scale and MSAA")
	_check(is_equal_approx(client._sun.directional_shadow_max_distance, 120.0), "Standard restores shadow distance")
	_check(not remote._reduced_effects, "remote restores standard effects")
	client._local_visual.update_visual(0.1, 0.0, 0.0, false, 0.0)
	_check(not client._local_visual._trails.visible, "no boost trail after recovery state")
	client._worker = true
	client._apply_graphics_settings("low", true)
	_check(client._quality == "standard" and not client._reduced_effects, "worker ignores graphics messages")
	client.queue_free()
	await process_frame
	print("GRAPHICS_SETTINGS_PROBE %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
