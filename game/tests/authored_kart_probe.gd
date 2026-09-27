extends SceneTree

const Kart = preload("res://vehicle/authored_kart.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Kart.warm()
	var first: Node3D = Kart.create(Color.RED)
	var second: Node3D = Kart.create(Color.BLUE)
	root.add_child(first)
	root.add_child(second)
	_check(first.find_children("*", "CollisionObject3D", true, false).is_empty(), "imported art does not create gameplay bodies")
	_check(first._model.position == Vector3(0.0, -0.35, 0.0), "ground-origin GLB uses explicit collider-origin adapter")
	_check(_materials(first) == _materials(second), "base materials do not change with caller slot color")
	_check_imported_pbr(first._model, second._model)
	_check(first._wheels.size() == 4 and first._steers.size() == 2, "four wheel pivots and two steering pivots imported")
	var bounds: AABB = _bounds(first._model)
	_check(bounds.size.x > 1.7 and bounds.size.x < 2.5, "authored width stays within review envelope")
	_check(bounds.size.z > 2.3 and bounds.size.z < 3.1, "authored length stays within review envelope")
	_check(bounds.size.y > 1.7 and bounds.size.y < 2.5, "authored height stays within review envelope")
	_check(absf(bounds.position.y) < 0.05, "visible tires meet asset ground plane")
	var hands: Array[Node3D] = [first._part("LeftHand"), first._part("RightHand")]
	var grips: Array[Transform3D] = [hands[0].transform, hands[1].transform]
	var hand_heights: Vector2 = Vector2(_mesh_center(hands[0]).y, _mesh_center(hands[1]).y)
	for hand: Node3D in hands:
		_check(first._steering.is_ancestor_of(hand), "hand contact follows steering pivot")
	var wheel_basis: Basis = first._wheels[0].basis
	first.update_visual(0.1, 20.0, 0.5, true, 1.0)
	_check(first._wheels[0].basis != wheel_basis, "speed rotates tires")
	_check(first._steers[0].basis != first._steer_rest[0], "steering rotates front wheels")
	_check(first._steering.basis != first._steering_rest, "steering rotates wheel and hands")
	_check(_mesh_center(hands[0]).y > hand_heights.x and _mesh_center(hands[1]).y < hand_heights.y, "right steering lowers right hand and raises left hand")
	_check(first._driver.transform != first._driver_rest, "drift leans the driver")
	_check(hands[0].transform == grips[0] and hands[1].transform == grips[1], "grips remain attached during steering")
	_check(first._jets.all(func(jet: Node3D) -> bool: return jet.visible), "both outlets respond to boost")
	first.set_reduced_effects(true)
	first.update_visual(0.1, 20.0, 0.5, true, 1.0)
	_check(first._jets.all(func(jet: Node3D) -> bool: return jet.scale.z < 0.5), "reduced effects shorten both plumes")
	_check(is_zero_approx(first._jet_material.get_shader_parameter("pulse_strength")), "reduced effects remove plume flashing")
	_check(is_equal_approx(first._driver.position.y, first._driver_rest.origin.y), "reduced effects remove idle bounce")
	first.update_visual(0.1, 0.0, 0.0, false, 0.0)
	_check(first._jets.all(func(jet: Node3D) -> bool: return not jet.visible), "recovery state stops boost")
	_check(first._steers[0].basis.is_equal_approx(first._steer_rest[0]), "neutral input resets front steering")
	_check(first._steering.basis.is_equal_approx(first._steering_rest), "neutral input resets steering wheel")
	for node: Node in first.find_children("*", "Node3D", true, false):
		_check(node.transform.is_finite(), "finite animated transform: " + str(node.name))
	first.queue_free()
	second.queue_free()
	await process_frame
	print("AUTHORED_KART_PROBE %d/%d passed bounds=%s" % [checks - failures, checks, bounds])
	quit(0 if failures == 0 else 1)


func _mesh_center(node: MeshInstance3D) -> Vector3:
	# Hand mesh origins intentionally share the steering axle, not each palm.
	return node.global_transform * node.get_aabb().get_center()


func _bounds(model: Node3D) -> AABB:
	var merged := AABB()
	var started: bool = false
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		if node.get_parent().name == "BoostJet":
			continue
		var mesh: MeshInstance3D = node
		var local: AABB = (model.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		merged = merged.merge(local) if started else local
		started = true
	return merged


func _materials(model: Node3D) -> Array:
	var colors: Array = []
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(surface)
			if material is StandardMaterial3D:
				colors.append([material.resource_name, material.albedo_color, material.metallic, material.roughness])
	return colors


func _check_imported_pbr(first: Node3D, second: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	var second_count: int = 0
	for node: Node in first.find_children("*", "MeshInstance3D", true, false):
		if node.get_parent().name != "BoostJet":
			meshes.append(node)
	for node: Node in second.find_children("*", "MeshInstance3D", true, false):
		if node.get_parent().name != "BoostJet":
			second_count += 1
	_check(meshes.size() == 13 and second_count == 13, "cached PackedScene provides all 13 authored meshes for both callers")
	var shared: Dictionary = {}
	for mesh: MeshInstance3D in meshes:
		var peer := second.get_node_or_null(first.get_path_to(mesh)) as MeshInstance3D
		var same_mesh: bool = peer != null and peer.mesh == mesh.mesh
		_check(same_mesh, "%s shares the imported mesh between caller colors" % mesh.name)
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv := PackedVector2Array()
			if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
				uv = arrays[Mesh.ARRAY_TEX_UV]
			var valid_uv: bool = not vertices.is_empty() and uv.size() == vertices.size()
			for point: Vector2 in uv:
				valid_uv = valid_uv and point.is_finite() and point.x >= -0.0001 and point.y >= -0.0001 and point.x <= 1.0001 and point.y <= 1.0001
			_check(valid_uv, "%s surface %d cached UVs are complete, finite and inside the atlas" % [mesh.name, surface])
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			_check(material != null, "%s surface %d retains an authored PBR material" % [mesh.name, surface])
			if material == null:
				continue
			shared[material.get_instance_id()] = material
			_check(same_mesh and peer.get_active_material(surface) == material, "%s surface %d shares the same material resource between caller colors" % [mesh.name, surface])
	_check(shared.size() == 1, "all cached authored surfaces use one shared PBR material, excluding boost jets")
	if shared.size() != 1:
		return
	var material: StandardMaterial3D = shared.values()[0]
	var textures: Dictionary = {"albedo": material.albedo_texture, "roughness": material.roughness_texture,
		"metallic": material.metallic_texture, "emission": material.emission_texture}
	for label: String in textures:
		var texture: Texture2D = textures[label]
		_check(texture != null and texture.get_width() == 2048 and texture.get_height() == 2048, "cached PBR retains its 2048-square %s texture" % label)
	_check(material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN and material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE,
		"cached packed ORM preserves G roughness and B metallic channels")
	_check(material.emission_enabled and material.emission_energy_multiplier > 0.0 and material.roughness > 0.0 and material.metallic > 0.0,
		"cached material enables emission and preserves roughness/metallic map factors")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
