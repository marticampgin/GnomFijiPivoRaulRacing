extends "res://track/fantasy_track_visuals.gd"


func prepare() -> void:
	_materials_init()
	_materials.road.albedo_color = Color("b0b2a5")
	_materials.stone.albedo_color = Color("b5beb8")
	_materials.cap.albedo_color = Color("8f9e97")
	_materials.roof.albedo_color = Color("556b7a")
	_materials.roof_dark.albedo_color = Color("485967")
	_materials.foliage.albedo_color = Color("9bb887")
	_materials.trunk.albedo_color = Color("736456")
	_materials.castle_stone.albedo_color = Color("c3c7b9")
	_materials.castle_stone.albedo_texture = _materials.stone.albedo_texture
	_materials.castle_stone.uv1_triplanar = true
	_materials.castle_stone.uv1_world_triplanar = true
	_materials.castle_stone.uv1_scale = Vector3.ONE * 0.19


func _place(mesh: Mesh, material: Material, pose: Transform3D, shadow: bool = true) -> void:
	var world_pose: Transform3D = _placement_transform * pose
	var chunk := Vector2i(floori(world_pose.origin.x / 40.0), floori(world_pose.origin.z / 40.0))
	var key: String = "%s_%s_%s_%s" % [mesh.get_instance_id(), material.get_instance_id(), shadow, chunk]
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "material": material, "transforms": [], "shadow": shadow}
	_batches[key].transforms.append(world_pose)


func finish() -> void:
	_flush_batches()
	for visual: Node in get_children():
		if visual is MultiMeshInstance3D:
			var foliage: bool = visual.material_override == _materials.foliage
			visual.set_meta("study_foliage", foliage)
			if foliage:
				visual.visibility_range_end = 230.0
				visual.visibility_range_end_margin = 35.0


func set_quality(low: bool) -> void:
	for visual: Node in get_children():
		if visual is MultiMeshInstance3D and visual.get_meta("study_foliage", false):
			visual.multimesh.visible_instance_count = maxi(1, roundi(visual.multimesh.instance_count * 0.6)) if low else -1
			visual.visibility_range_end = 155.0 if low else 230.0
			visual.visibility_range_end_margin = 24.0 if low else 35.0


func castle(origin: Vector3) -> void:
	_island("CastleRockFoundation", origin - Vector3.UP * 0.3, Vector2(37, 29), -11.0, 48, 1.1)
	var old_stone: Material = _materials.stone
	_materials.stone = _materials.castle_stone
	var stone: Material = _materials.stone
	_box(origin + Vector3(0, 0.2, 0), Vector3(55, 0.8, 39), _materials.cap)
	_box(origin + Vector3(0, 9, 0), Vector3(24, 18, 18), stone)
	_place(_pyramid_mesh(), _materials.roof_dark, _pose(origin + Vector3(0, 23, 0), Vector3(28, 11, 21)))
	_tower(origin + Vector3(-9, 0, -2), 4.0, 34.0, 12.0)
	_tower(origin + Vector3(13, 0, -8), 3.1, 27.0, 10.0)
	_tower(origin + Vector3(-21, 0, 8), 3.3, 19.0, 8.0)
	_tower(origin + Vector3(18, 0, 13), 4.0, 21.0, 8.0)
	_tower(origin + Vector3(3, 17, 4), 1.5, 13.0, 6.0)
	_box(origin + Vector3(-16, 6, -9), Vector3(13, 12, 12), stone)
	_place(_pyramid_mesh(), _materials.roof, _pose(origin + Vector3(-16, 15, -9), Vector3(15, 7, 14)))
	for side: float in [-1.0, 1.0]:
		_box(origin + Vector3(side * 16, 4.5, 19), Vector3(21, 9, 2.0), stone)
		_crenels(origin + Vector3(side * 16, 9.2, 19), 21.0, 10)
	_arch(origin + Vector3(0, 0, 19), 4.8, 5.0, 2.0)
	for floor_index: int in 3:
		for x: float in [-7.0, 0.0, 7.0]:
			_place(_window_mesh(), _materials.window, _pose(origin + Vector3(x, 4.5 + floor_index * 5.5, 9.07), Vector3(1.6, 2.0, 1.0)), false)
	for x: float in [-6.2, 6.2]:
		_banner(origin + Vector3(x, 8, 20.2), 1.7)
	_materials.stone = old_stone
