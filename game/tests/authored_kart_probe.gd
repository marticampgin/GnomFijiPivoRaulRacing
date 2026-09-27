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


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
