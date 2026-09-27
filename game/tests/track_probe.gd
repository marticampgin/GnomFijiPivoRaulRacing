extends SceneTree

const TrackScript = preload("res://track/prototype_track.gd")
const VehicleScript = preload("res://vehicle/racing_vehicle.gd")
const KartScript = preload("res://vehicle/prototype_kart.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var track: Node3D = TrackScript.new()
	root.add_child(track)
	track.build(false)
	_check(track.find_children("*", "MeshInstance3D", true, false).is_empty(), "server track has no meshes")
	_check(track.find_children("*", "StaticBody3D", true, false).size() == 192, "server track has all road and barrier colliders")
	var count: int = track.get_child_count()
	track.build(false)
	_check(track.get_child_count() == count, "track build is idempotent")
	_check(track.sector_at(Vector3(62.0, 0.0, 0.0)) == 0, "start is sector zero")
	_check(track.sector_at(Vector3(0.0, 0.0, 42.0)) == 4, "positive travel reaches sector four")
	_check(track.sector_at(Vector3(-62.0, 0.0, 0.0)) == 8, "half lap is sector eight")
	var vehicles: Array[CharacterBody3D] = []
	for slot: int in 10:
		var vehicle: CharacterBody3D = VehicleScript.new()
		var collider: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(1.5, 0.8, 2.4)
		collider.shape = shape
		vehicle.add_child(collider)
		root.add_child(vehicle)
		vehicle.reset_at(track.spawn_transform(slot))
		vehicles.append(vehicle)
	for tick: int in 120:
		await physics_frame
		for vehicle: CharacterBody3D in vehicles:
			vehicle.step({}, 1.0 / 60.0)
	for slot: int in 10:
		_check(vehicles[slot].grounded, "spawn slot %d contacts road" % slot)
		_check(vehicles[slot].position.y > 0.39, "spawn slot %d stays above road" % slot)
	for vehicle: CharacterBody3D in vehicles:
		vehicle.queue_free()
	track.queue_free()
	await process_frame
	var visual_track: Node3D = TrackScript.new()
	root.add_child(visual_track)
	visual_track.build(true)
	_check(not visual_track.find_children("*", "MeshInstance3D", true, false).is_empty(), "client track has visuals")
	_check(visual_track.find_children("*", "StaticBody3D", true, false).size() == 192, "visuals do not change collision count")
	var kart: Node3D = KartScript.create(Color("64e3db"))
	root.add_child(kart)
	_check(kart.find_children("*", "MeshInstance3D", true, false).size() > 10, "kart has body and wheels")
	kart.queue_free()
	visual_track.queue_free()
	await process_frame
	print("TRACK_PROBE ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)
