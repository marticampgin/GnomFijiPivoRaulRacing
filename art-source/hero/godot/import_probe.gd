extends SceneTree

var _checks := 0
var _failures: Array[String] = []
var _nodes: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 1:
		printerr("Usage: Godot --headless --path art-source/hero/godot --script import_probe.gd -- /absolute/hero-blockout.glb [report.json]")
		quit(2)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(arguments[0], state)
	_expect(error == OK, "self-contained GLB parses")
	if error != OK:
		quit(1)
		return
	var scene := document.generate_scene(state)
	_expect(scene != null, "scene generated")
	if scene == null:
		quit(1)
		return
	root.add_child(scene)
	_collect(scene)
	var hierarchy := {
		"Body": "HeroBlockout", "FrontLeftSteer": "HeroBlockout", "FrontRightSteer": "HeroBlockout",
		"RearLeftPivot": "HeroBlockout", "RearRightPivot": "HeroBlockout",
		"FrontLeftRoll": "FrontLeftSteer", "FrontRightRoll": "FrontRightSteer",
		"RearLeftRoll": "RearLeftPivot", "RearRightRoll": "RearRightPivot",
		"DriverLean": "HeroBlockout", "DriverBody": "DriverLean", "HeadMotion": "DriverLean",
		"Head": "HeadMotion", "Hat": "HeadMotion", "SteeringPivot": "HeroBlockout",
		"SteeringWheel": "SteeringPivot", "LeftHand": "SteeringPivot", "RightHand": "SteeringPivot",
		"CrystalPivot": "HeroBlockout", "Crystal": "CrystalPivot", "EngineCradle": "HeroBlockout",
		"ExhaustLeft": "HeroBlockout", "ExhaustRight": "HeroBlockout",
	}
	for node_name: String in hierarchy:
		_expect(_nodes.has(node_name), "%s named node exists" % node_name)
		if not _nodes.has(node_name):
			continue
		var node := _nodes[node_name] as Node3D
		_expect(node.get_parent().name == hierarchy[node_name], "%s hierarchy" % node_name)
		_expect(node.scale.is_equal_approx(Vector3.ONE), "%s unit scale" % node_name)
		_expect(node.position.is_finite() and node.basis.x.is_finite() and node.basis.y.is_finite() and node.basis.z.is_finite(), "%s finite transform" % node_name)
	if _failures.size() > 0:
		scene.free()
		quit(1)
		return
	var meshes: Array[MeshInstance3D] = []
	var surfaces := 0
	var triangles := 0
	var materials: Dictionary = {}
	var mesh_bounds: Dictionary = {}
	for node: Node in _nodes.values():
		_expect(not (node is Camera3D or node is Light3D or node is CollisionObject3D), "%s excludes studio/physics nodes" % node.name)
		if not node is MeshInstance3D:
			continue
		var mesh_node := node as MeshInstance3D
		meshes.append(mesh_node)
		var bound := _mesh_bounds(mesh_node)
		mesh_bounds[node.name] = _bounds_json(bound)
		for index in mesh_node.mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh_node.mesh.surface_get_arrays(index)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			triangles += indices.size() / 3 if indices.size() > 0 else vertices.size() / 3
			_expect(vertices.size() > 0 and arrays[Mesh.ARRAY_NORMAL] != null, "%s surface %d geometry/normals" % [node.name, index])
			var material := mesh_node.get_active_material(index) as StandardMaterial3D
			_expect(material != null, "%s surface %d PBR material" % [node.name, index])
			if material != null:
				materials[material.resource_name] = true
	var overall := _mesh_bounds(meshes[0])
	for mesh_node in meshes.slice(1):
		overall = overall.merge(_mesh_bounds(mesh_node))
	_expect(absf(overall.position.y) < 0.0001, "lowest geometry contacts ground y=0")
	_expect(overall.size.x > 2.0 and overall.size.x < 2.21, "width is bounded around 2.1m")
	_expect(overall.size.y > 2.0 and overall.size.y < 2.11, "height is bounded around 2.05m")
	_expect(overall.size.z > 2.6 and overall.size.z < 2.8, "length is bounded around 2.7m")
	for prefix: String in ["FrontLeft", "FrontRight", "RearLeft", "RearRight"]:
		var wheel := _nodes[prefix + "Roll"] as MeshInstance3D
		var local_bound := wheel.mesh.get_aabb()
		var world_bound := _mesh_bounds(wheel)
		_expect(wheel.basis.is_equal_approx(Basis.IDENTITY), "%s wheel has local-X identity rest" % prefix)
		_expect(local_bound.size.x < 0.55 and local_bound.size.y > 0.78 and local_bound.size.z > 0.78, "%s tire axis is X" % prefix)
		_expect(absf(world_bound.position.y) < 0.001, "%s tread contacts ground" % prefix)
		_expect(wheel.global_position.x < 0.0 if prefix.ends_with("Left") else wheel.global_position.x > 0.0, "%s lateral position" % prefix)
		_expect(wheel.global_position.z < 0.0 if prefix.begins_with("Front") else wheel.global_position.z > 0.0, "%s forward is -Z" % prefix)
		var rest := wheel.transform
		wheel.basis = Basis(Vector3.RIGHT, PI / 2.0)
		var spun_bound := _mesh_bounds(wheel)
		_expect(absf(spun_bound.size.y - world_bound.size.y) < 0.015 and absf(spun_bound.size.z - world_bound.size.z) < 0.015, "%s remains round when rolled" % prefix)
		wheel.transform = rest
	var crystal := _mesh_bounds(_nodes["Crystal"])
	_expect(crystal.end.y < 1.25 and crystal.position.z > 0.6, "compact crystal stays behind driver below shoulders")
	var left_exhaust := _nodes["ExhaustLeft"] as Node3D
	var right_exhaust := _nodes["ExhaustRight"] as Node3D
	_expect(left_exhaust.global_position.z > 1.2 and right_exhaust.global_position.z > 1.2, "exhaust attachments are at rear")
	_expect(is_equal_approx(left_exhaust.position.y, right_exhaust.position.y) and is_equal_approx(-left_exhaust.position.x, right_exhaust.position.x), "twin exhaust attachments are symmetric")
	_expect(left_exhaust.basis.z.is_equal_approx(Vector3.BACK) and right_exhaust.basis.z.is_equal_approx(Vector3.BACK), "exhaust local +Z points rearwards")
	var steering := _nodes["SteeringPivot"] as Node3D
	_expect(steering.basis.is_equal_approx(Basis.IDENTITY), "steering has identity rest basis")
	var hand_offsets: Dictionary = {}
	for hand_name: String in ["LeftHand", "RightHand"]:
		hand_offsets[hand_name] = steering.global_transform.affine_inverse() * (_nodes[hand_name] as Node3D).global_position
	var steering_rest := steering.transform
	steering.basis = Basis(Vector3(0, 0.48, -0.877).normalized(), 0.35)
	for hand_name: String in hand_offsets:
		var relative := steering.global_transform.affine_inverse() * (_nodes[hand_name] as Node3D).global_position
		_expect(relative.is_equal_approx(hand_offsets[hand_name]), "%s maintains wheel-local contact under steering" % hand_name)
	steering.transform = steering_rest
	var result := {
		"kind": "review-blockout-import-probe", "godotVersion": Engine.get_version_info().string,
		"assetSha256": FileAccess.get_sha256(arguments[0]),
		"checks": _checks, "failures": _failures, "meshCount": meshes.size(), "surfaces": surfaces,
		"triangles": triangles, "materials": materials.keys(), "bounds": _bounds_json(overall),
		"meshBounds": mesh_bounds, "nodeNames": _nodes.keys(),
		"notCovered": ["final aesthetic approval", "final UVs/textures", "skeletal rig", "browser renderer", "10-racer frame budget"],
	}
	var serialized := JSON.stringify(result, "  ")
	if arguments.size() > 1:
		var output := FileAccess.open(arguments[1], FileAccess.WRITE)
		if output != null:
			output.store_string(serialized + "\n")
	print("HERO_BLOCKOUT_PROBE " + serialized)
	scene.free()
	quit(0 if _failures.is_empty() else 1)


func _collect(node: Node) -> void:
	_nodes[str(node.name)] = node
	for child in node.get_children():
		_collect(child)


func _mesh_bounds(node: MeshInstance3D) -> AABB:
	var bound := AABB()
	var first := true
	for index in node.mesh.get_surface_count():
		var arrays := node.mesh.surface_get_arrays(index)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var point := node.global_transform * vertex
			if first:
				bound = AABB(point, Vector3.ZERO)
				first = false
			else:
				bound = bound.expand(point)
	return bound


func _bounds_json(bound: AABB) -> Dictionary:
	return {"min": _vector_json(bound.position), "max": _vector_json(bound.end), "size": _vector_json(bound.size)}


func _vector_json(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: " + description)
