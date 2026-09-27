extends SceneTree

const KartScript = preload("res://vehicle/prototype_kart.gd")
const TrackScript = preload("res://track/prototype_track.gd")
var checks: int = 0
var failures: int = 0
var measurements: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var kart: Node3D = KartScript.create(Color("64e3db"))
	root.add_child(kart)
	for path: String in ["Driver/Head/Hat", "Driver/Head/Face", "Driver/Head/Beard", "CrystalEngine/Crystal", "WheelFrontLeft/TireAssembly", "WheelFrontRight/TireAssembly", "WheelRearLeft/TireAssembly", "WheelRearRight/TireAssembly"]:
		var feature: Node3D = kart.get_node_or_null(path) as Node3D
		_check(feature != null and _has_visible_geometry(feature), "kart feature is visible: " + path)
	_check(kart.find_children("*", "CollisionObject3D", true, false).is_empty() and kart.find_children("*", "CollisionShape3D", true, false).is_empty(), "kart visuals do not own physics colliders")
	var kart_geometry: Dictionary = _inspect(kart)
	_check_geometry(kart_geometry, "kart")
	var kart_size: Vector3 = kart_geometry["bounds"].size
	_check(kart_size.x > 1.0 and kart_size.x < 8.0 and kart_size.y > 0.7 and kart_size.y < 8.0 and kart_size.z > 1.5 and kart_size.z < 10.0, "kart dimensions remain vehicle-sized")
	measurements["kart_size"] = [kart_size.x, kart_size.y, kart_size.z]
	measurements["kart_instances"] = kart_geometry["instances"]
	measurements["kart_unique_meshes"] = kart_geometry["unique_meshes"]
	_check(kart.has_method("update_visual"), "kart has visual animation adapter")
	if kart.has_method("update_visual"):
		for state: Array in [[0.0, 0.0, false, 0.0], [20.0, 0.6, true, 0.0], [30.0, -0.7, false, 1.0]]:
			for frame: int in 10:
				kart.call("update_visual", 1.0 / 60.0, state[0], state[1], state[2], state[3])
			_check_geometry(_inspect(kart), "animated kart " + str(state))
	kart.queue_free()
	await process_frame

	var server_track: Node3D = TrackScript.new()
	root.add_child(server_track)
	server_track.build(false)
	_check(server_track.find_children("*", "GeometryInstance3D", true, false).is_empty(), "headless track does not allocate visible geometry")
	_check(server_track.get_node_or_null("FantasyScenery") == null, "headless track omits fantasy scenery")
	var visual_track: Node3D = TrackScript.new()
	root.add_child(visual_track)
	visual_track.build(true)
	_check(_same_colliders(server_track, visual_track), "visual track preserves every server collider pose and shape")
	var scenery: Node3D = visual_track.get_node_or_null("FantasyScenery") as Node3D
	_check(scenery != null, "client track has fantasy scenery")
	if scenery != null:
		_check(scenery.find_children("*", "CollisionObject3D", true, false).is_empty() and scenery.find_children("*", "CollisionShape3D", true, false).is_empty(), "fantasy scenery is visual-only")
		for feature_name: String in ["StoneRoad", "MainIsland", "CastleIsland", "Lake", "Waterfalls"]:
			var feature: Node3D = scenery.find_child(feature_name, true, false) as Node3D
			_check(feature != null and _has_visible_geometry(feature), "scenery feature is visible: " + feature_name)
	var track_geometry: Dictionary = _inspect(visual_track)
	_check_geometry(track_geometry, "visual track")
	var track_bounds: AABB = track_geometry["bounds"]
	_check(track_bounds.size.x > 100.0 and track_bounds.size.z > 60.0 and track_bounds.size.x < 2000.0 and track_bounds.size.y < 400.0 and track_bounds.size.z < 2000.0, "readable track geometry stays within the prototype world")
	measurements["track_readable_size"] = [track_bounds.size.x, track_bounds.size.y, track_bounds.size.z]
	measurements["track_instances"] = track_geometry["instances"]
	measurements["track_unique_meshes"] = track_geometry["unique_meshes"]
	measurements["headless_batch_placements_unverified"] = track_geometry["unverified_batch_instances"]
	server_track.queue_free()
	visual_track.queue_free()
	await process_frame
	print("VISUAL_ASSET_PROBE ", JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}))
	quit(0 if failures == 0 else 1)


func _has_visible_geometry(node: Node3D) -> bool:
	if node == null or not node.is_visible_in_tree():
		return false
	if node is MeshInstance3D:
		return node.mesh != null
	if node is MultiMeshInstance3D:
		return node.multimesh != null and node.multimesh.mesh != null and node.multimesh.instance_count > 0
	for child: Node in node.find_children("*", "GeometryInstance3D", true, false):
		if _has_visible_geometry(child as Node3D):
			return true
	return false


func _inspect(owner: Node3D) -> Dictionary:
	var result: Dictionary = {"instances": 0, "unique_meshes": 0, "unverified_batch_instances": 0, "bounds": AABB(), "bounded": false, "errors": []}
	var seen: Dictionary = {}
	var inverse: Transform3D = owner.global_transform.affine_inverse()
	for child: Node in owner.find_children("*", "GeometryInstance3D", true, false):
		var geometry: GeometryInstance3D = child as GeometryInstance3D
		if not geometry.is_visible_in_tree():
			continue
		var mesh: Mesh
		var transforms: Array[Transform3D] = []
		var unverified_instances: int = 0
		if geometry is MeshInstance3D:
			mesh = geometry.mesh
			transforms.append(inverse * geometry.global_transform)
		elif geometry is MultiMeshInstance3D:
			var batch: MultiMesh = geometry.multimesh
			if batch == null or batch.transform_format != MultiMesh.TRANSFORM_3D:
				result["errors"].append(str(geometry.name) + ": missing 3D batch")
				continue
			mesh = batch.mesh
			var count: int = batch.instance_count if batch.visible_instance_count < 0 else batch.visible_instance_count
			if DisplayServer.get_name() == "headless":
				# The dummy renderer does not reliably retain MultiMesh instance transforms.
				unverified_instances = count
			else:
				for index: int in count:
					transforms.append(inverse * geometry.global_transform * batch.get_instance_transform(index))
		else:
			continue
		if mesh == null or (transforms.is_empty() and unverified_instances == 0):
			result["errors"].append(str(geometry.name) + ": empty visible geometry")
			continue
		if not seen.has(mesh.get_instance_id()):
			seen[mesh.get_instance_id()] = true
			var error: String = _mesh_error(mesh)
			if not error.is_empty():
				result["errors"].append(str(geometry.name) + ": " + error)
		result["instances"] += unverified_instances
		result["unverified_batch_instances"] += unverified_instances
		for pose: Transform3D in transforms:
			if not pose.is_finite():
				result["errors"].append(str(geometry.name) + ": nonfinite transform")
				continue
			var bounds: AABB = pose * mesh.get_aabb()
			if not bounds.position.is_finite() or not bounds.size.is_finite():
				result["errors"].append(str(geometry.name) + ": nonfinite bounds")
				continue
			result["bounds"] = result["bounds"].merge(bounds) if result["bounded"] else bounds
			result["bounded"] = true
			result["instances"] += 1
	result["unique_meshes"] = seen.size()
	return result


func _mesh_error(mesh: Mesh) -> String:
	if mesh.get_surface_count() == 0:
		return "no mesh surfaces"
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.size() != Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_VERTEX] == null:
			return "missing vertex data"
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.size() < 3:
			return "empty vertex data"
		for vertex: Vector3 in vertices:
			if not vertex.is_finite():
				return "nonfinite vertex"
		if arrays[Mesh.ARRAY_NORMAL] != null:
			for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
				if not normal.is_finite():
					return "nonfinite normal"
		if arrays[Mesh.ARRAY_INDEX] != null:
			for index: int in arrays[Mesh.ARRAY_INDEX]:
				if index < 0 or index >= vertices.size():
					return "index outside vertex data"
	return ""


func _same_colliders(server: Node3D, client: Node3D) -> bool:
	var expected: Array[Node] = server.find_children("*", "CollisionShape3D", true, false)
	var actual: Array[Node] = client.find_children("*", "CollisionShape3D", true, false)
	if expected.is_empty() or expected.size() != actual.size():
		return false
	for index: int in expected.size():
		var first: CollisionShape3D = expected[index] as CollisionShape3D
		var second: CollisionShape3D = actual[index] as CollisionShape3D
		if first.shape == null or second.shape == null or first.shape.get_class() != second.shape.get_class():
			return false
		if not first.global_transform.is_equal_approx(second.global_transform):
			return false
		if not first.shape.get_debug_mesh().get_aabb().is_equal_approx(second.shape.get_debug_mesh().get_aabb()):
			return false
		if first.disabled != second.disabled:
			return false
	return true


func _check_geometry(result: Dictionary, label: String) -> void:
	_check(result["instances"] > 0 and result["bounded"] and result["errors"].is_empty(), label + " has finite nonempty geometry: " + str(result["errors"]))


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)
