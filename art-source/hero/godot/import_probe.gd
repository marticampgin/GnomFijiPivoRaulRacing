extends SceneTree

const ATLAS_SIZE: int = 2048
const UV_TOLERANCE: float = 0.0001

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
	var uv_surfaces: Array[Dictionary] = []
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
			uv_surfaces.append(_check_uvs(str(node.name), index, arrays))
			var material := mesh_node.get_active_material(index) as StandardMaterial3D
			_expect(material != null, "%s surface %d PBR material" % [node.name, index])
			if material != null:
				materials[material.get_instance_id()] = material
	_expect(not meshes.is_empty(), "import contains geometry")
	if meshes.is_empty():
		scene.free()
		quit(1)
		return
	var pbr := _check_pbr(state, materials)
	var material_names: Array[String] = []
	for material: StandardMaterial3D in materials.values():
		material_names.append(material.resource_name)
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
		"kind": "hero-uv-pbr-import-probe", "godotVersion": Engine.get_version_info().string,
		"assetSha256": FileAccess.get_sha256(arguments[0]),
		"checks": _checks, "failures": _failures, "meshCount": meshes.size(), "surfaces": surfaces,
		"triangles": triangles, "materials": material_names, "bounds": _bounds_json(overall),
		"meshBounds": mesh_bounds, "nodeNames": _nodes.keys(),
		"uv": {"channel": "UV1 / TEXCOORD_0", "boundsTolerance": UV_TOLERANCE, "surfaces": uv_surfaces},
		"pbr": pbr,
		"notCovered": ["final aesthetic approval", "UV island overlap, padding and texel-density quality", "GPU mipmap sampling when running headless", "normal map", "skeletal rig", "browser renderer and color-space appearance", "10-racer frame budget"],
	}
	var serialized := JSON.stringify(result, "  ")
	if arguments.size() > 1:
		var output := FileAccess.open(arguments[1], FileAccess.WRITE)
		if output != null:
			output.store_string(serialized + "\n")
	print("HERO_BLOCKOUT_PROBE " + serialized)
	scene.free()
	quit(0 if _failures.is_empty() else 1)


func _check_uvs(node_name: String, surface: int, arrays: Array) -> Dictionary:
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var uv := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		uv = arrays[Mesh.ARRAY_TEX_UV]
	var complete: bool = not uv.is_empty() and uv.size() == vertices.size()
	var finite: bool = complete
	var in_atlas: bool = complete
	var minimum := Vector2.ONE
	var maximum := Vector2.ZERO
	for point: Vector2 in uv:
		finite = finite and point.is_finite()
		in_atlas = in_atlas and point.is_finite() and point.x >= -UV_TOLERANCE and point.y >= -UV_TOLERANCE and point.x <= 1.0 + UV_TOLERANCE and point.y <= 1.0 + UV_TOLERANCE
		if point.is_finite():
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	var area: float = 0.0
	if complete and finite:
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for offset: int in range(0, count - 2, 3):
			var a: Vector2 = uv[indices[offset] if not indices.is_empty() else offset]
			var b: Vector2 = uv[indices[offset + 1] if not indices.is_empty() else offset + 1]
			var c: Vector2 = uv[indices[offset + 2] if not indices.is_empty() else offset + 2]
			area += absf((b - a).cross(c - a)) * 0.5
	var label: String = "%s surface %d" % [node_name, surface]
	_expect(complete, label + " UVs cover every imported vertex")
	_expect(finite and in_atlas, label + " UVs are finite and inside the atlas")
	_expect(is_finite(area) and area > 0.00000001, label + " UV projection has nonzero area")
	return {"node": node_name, "surface": surface, "vertices": vertices.size(), "uvCount": uv.size(),
		"complete": complete, "finite": finite, "withinAtlas": in_atlas, "triangleUvArea": area,
		"minimum": [minimum.x, minimum.y], "maximum": [maximum.x, maximum.y]}


func _check_pbr(state: GLTFState, materials: Dictionary) -> Dictionary:
	var result: Dictionary = {"runtimeMaterialCount": materials.size(), "expectedAtlasSize": ATLAS_SIZE,
		"textureEvidence": "embedded GLB image decode; runtime bindings checked separately", "ambientOcclusion": "constant-one packed R channel; AO binding not required"}
	_expect(materials.size() == 1, "all surfaces share one runtime material resource")
	var source_materials: Array = state.json.get("materials", [])
	_expect(source_materials.size() == 1, "GLB contains one shared material")
	if materials.is_empty() or source_materials.size() != 1:
		return result
	var material: StandardMaterial3D = materials.values()[0]
	var source: Dictionary = source_materials[0]
	var metallic_roughness: Dictionary = source.get("pbrMetallicRoughness", {})
	var infos: Dictionary = {"albedo": metallic_roughness.get("baseColorTexture", {}),
		"orm": metallic_roughness.get("metallicRoughnessTexture", {}), "emission": source.get("emissiveTexture", {})}
	var textures: Dictionary = {"albedo": material.albedo_texture, "roughness": material.roughness_texture,
		"metallic": material.metallic_texture, "emission": material.emission_texture}
	var bindings: Dictionary = {}
	for label: String in textures:
		var texture: Texture2D = textures[label]
		_expect(texture != null, label + " runtime texture is bound")
		if texture == null:
			bindings[label] = {"bound": false}
			continue
		var size := Vector2i(texture.get_width(), texture.get_height())
		_expect(size == Vector2i(ATLAS_SIZE, ATLAS_SIZE), label + " runtime texture dimensions are 2048 square")
		var evidence: Dictionary = {"bound": true, "width": size.x, "height": size.y,
			"runtimeMipmaps": null, "runtimeImageReadback": "not attempted with headless renderer"}
		if DisplayServer.get_name() != "headless":
			var image: Image = texture.get_image()
			evidence.runtimeImageReadback = "unavailable" if image == null or image.is_empty() else "available"
			if image != null and not image.is_empty():
				evidence.runtimeMipmaps = image.has_mipmaps()
				_expect(image.has_mipmaps(), label + " runtime image has mipmaps")
		bindings[label] = evidence
	_expect(material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN and material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, "packed ORM uses G roughness and B metallic")
	_expect(material.emission_enabled and material.emission_energy_multiplier > 0.0, "imported emission is enabled")
	_expect(material.roughness > 0.0 and material.metallic > 0.0, "roughness and metallic factors preserve their maps")
	result.bindings = bindings
	result.textureFilter = material.texture_filter
	result.emissionEnabled = material.emission_enabled
	result.normalMapBound = material.normal_texture != null
	result.textures = {}
	for label: String in infos:
		result.textures[label] = _check_embedded_texture(state, infos[label], label)
	return result


func _check_embedded_texture(state: GLTFState, info: Dictionary, label: String) -> Dictionary:
	var result: Dictionary = {}
	var textures: Array = state.json.get("textures", [])
	var texture_index: int = int(info.get("index", -1))
	_expect(texture_index >= 0 and texture_index < textures.size(), label + " GLB texture reference exists")
	_expect(int(info.get("texCoord", 0)) == 0, label + " texture uses the checked UV channel")
	if texture_index < 0 or texture_index >= textures.size():
		return result
	var images: Array = state.json.get("images", [])
	var image_index: int = int(textures[texture_index].get("source", -1))
	_expect(image_index >= 0 and image_index < images.size(), label + " GLB image reference exists")
	if image_index < 0 or image_index >= images.size():
		return result
	var source: Dictionary = images[image_index]
	var views: Array = state.json.get("bufferViews", [])
	var view_index: int = int(source.get("bufferView", -1))
	var embedded: bool = not source.has("uri") and view_index >= 0 and view_index < views.size()
	_expect(embedded, label + " image is embedded rather than an external dependency")
	if not embedded:
		return result
	var view: Dictionary = views[view_index]
	var buffer_index: int = int(view.get("buffer", -1))
	var offset: int = int(view.get("byteOffset", 0))
	var length: int = int(view.get("byteLength", 0))
	var buffers: Array[PackedByteArray] = state.buffers
	var valid: bool = buffer_index >= 0 and buffer_index < buffers.size() and offset >= 0 and length > 0
	if valid:
		valid = offset + length <= buffers[buffer_index].size() and not state.json.buffers[buffer_index].has("uri")
	_expect(valid, label + " image bytes are contained in the GLB buffer")
	if not valid:
		return result
	var bytes: PackedByteArray = buffers[buffer_index].slice(offset, offset + length)
	var image := Image.new()
	var mime: String = source.get("mimeType", "")
	var error: Error = ERR_FILE_UNRECOGNIZED
	if mime == "image/png":
		error = image.load_png_from_buffer(bytes)
	elif mime == "image/jpeg":
		error = image.load_jpg_from_buffer(bytes)
	_expect(error == OK and not image.is_empty(), label + " embedded image decodes")
	if error != OK or image.is_empty():
		return result
	_expect(image.get_width() == ATLAS_SIZE and image.get_height() == ATLAS_SIZE, label + " decoded image is 2048 square")
	_expect(not image.get_data().is_empty(), label + " decoded image contains pixel data")
	var nonblack: int = 0
	var sampled: int = 0
	var orm_covered: int = 0
	var orm_channels: Dictionary = {
		"roughness": {"channel": "G", "minimum": 1.0, "maximum": 0.0, "nonzeroSamples": 0},
		"metallic": {"channel": "B", "minimum": 1.0, "maximum": 0.0, "nonzeroSamples": 0},
	}
	var stride: int = maxi(1, floori(float(image.get_width()) / 128.0))
	for y: int in range(0, image.get_height(), stride):
		for x: int in range(0, image.get_width(), stride):
			var color: Color = image.get_pixel(x, y)
			sampled += 1
			if maxf(color.r, maxf(color.g, color.b)) > 0.00001:
				nonblack += 1
			# Authored ORM uses R=1; ignore unused black atlas space in ranges.
			if label == "orm" and color.r > 0.5:
				orm_covered += 1
				for channel_name: String in orm_channels:
					var value: float = color.g if channel_name == "roughness" else color.b
					var channel: Dictionary = orm_channels[channel_name]
					channel.minimum = minf(channel.minimum, value)
					channel.maximum = maxf(channel.maximum, value)
					if value > 0.00001:
						channel.nonzeroSamples += 1
	_expect(nonblack > 0, label + " decoded pixels are not an empty black bake")
	result = {"sourceImage": image_index, "mimeType": mime, "embeddedBytes": bytes.size(),
		"width": image.get_width(), "height": image.get_height(), "decodedBytes": image.get_data().size(),
		"decodedMipmaps": image.has_mipmaps(), "sampledPixels": sampled, "nonblackSamples": nonblack}
	if label == "orm":
		_expect(orm_covered > 0, "ORM contains sampled authored regions with constant-one R")
		for channel_name: String in orm_channels:
			var channel: Dictionary = orm_channels[channel_name]
			channel.sampledPixels = orm_covered
			_expect(channel.nonzeroSamples > 0, "ORM %s channel contains nonzero material data" % channel_name)
			_expect(orm_covered > 0 and float(channel.maximum) - float(channel.minimum) > 1.0 / 255.0,
				"ORM %s varies within authored regions, not only against the atlas background" % channel_name)
		result.authoredCoverage = {"criterion": "R > 0.5; authored R is constant one", "sampledPixels": orm_covered}
		result.channels = orm_channels
	return result


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
