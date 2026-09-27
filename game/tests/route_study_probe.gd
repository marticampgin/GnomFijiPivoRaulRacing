extends SceneTree

const Study = preload("res://track/authored_track_study.gd")
const Track = preload("res://track/authored_track.gd")
const Baker = preload("res://track/track_baker.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var track := Track.new()
	var data: Dictionary = track.data
	var before: String = Baker.simulation_hash(data)
	track.free()
	var study := Study.new()
	root.add_child(study)
	study.build(data)
	_check(Baker.simulation_hash(data) == before, "visual study does not modify simulation data")
	_check(not study.get_meta("production_accepted", true), "study is explicitly not production accepted")
	_check(study.find_children("*", "CollisionObject3D", true, false).is_empty(), "study adds no physics bodies")
	var road: MeshInstance3D = study.find_child("StudyStoneRoad", true, false)
	_check(road != null, "stone road exists")
	if road != null:
		var vertices: PackedVector3Array = road.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var matches: bool = vertices.size() == data.collision.road_faces.size()
		for index: int in vertices.size():
			matches = matches and vertices[index].is_equal_approx(Baker.vector(data.collision.road_faces[index]) + Vector3.UP * 0.012)
		_check(matches, "visible road follows exact baked collision faces")
		_check(road.material_override.albedo_texture != null, "road uses existing stone texture")
	var lake: Node = study.find_child("StudyLake", true, false)
	var falls: Array[Node] = study.find_children("StudyWaterfall*", "MeshInstance3D", true, false)
	var castle: Node = study.find_child("CastleRockFoundation", true, false)
	_check(lake != null and falls.size() >= 4, "lake and two waterfall/foam samples exist")
	_check(castle != null, "castle has continuous rock foundation")
	var total: int = 0
	var foliage_count: int = 0
	for visual: Node in study.find_children("*", "MultiMeshInstance3D", true, false):
		total += visual.multimesh.instance_count
		if visual.get_meta("study_foliage", false):
			foliage_count += visual.multimesh.instance_count
	_check(foliage_count > 1000, "forest uses textured alpha-scissor foliage sample")
	var nodes: int = study.find_children("*", "GeometryInstance3D", true, false).size()
	study.set_quality(true)
	var low_count: int = 0
	for visual: Node in study.find_children("*", "MultiMeshInstance3D", true, false):
		if visual.get_meta("study_foliage", false):
			low_count += visual.multimesh.visible_instance_count
	_check(low_count < foliage_count and low_count > foliage_count / 2, "Low reduces foliage density while retaining forest silhouette")
	_check(study.find_children("*", "GeometryInstance3D", true, false).size() == nodes and lake.visible and castle.visible, "Low preserves road and landmark geometry")
	study.set_reduced_effects(true)
	_check(study._water.get_shader_parameter("motion_strength") < 1.0 and study._fall.get_shader_parameter("motion_strength") < 1.0, "reduced effects lowers animated water motion")
	study.set_quality(false)
	study.set_reduced_effects(false)
	_check(study._water.get_shader_parameter("motion_strength") == 1.0, "standard water motion restores")
	_check(Baker.simulation_hash(data) == before, "quality changes preserve simulation identity")
	for anchor: Dictionary in data.camera_anchors:
		_check(Baker.vector(anchor.position).is_finite(), "review anchor %s is valid" % anchor.id)
	print("ROUTE_STUDY_PROBE ", JSON.stringify({"checks": checks, "failures": failures, "render_nodes": nodes, "instances": total, "foliage_instances": foliage_count, "low_foliage_instances": low_count, "simulation_hash": before, "status": "internal_environment_study_not_visual_acceptance"}))
	study.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
