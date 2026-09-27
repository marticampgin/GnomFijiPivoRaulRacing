extends RefCounted

const LAYER: int = 4


static func build_from(visual_root: Node3D, materials: Array[Material], batches: Dictionary) -> StaticBody3D:
	var faces := PackedVector3Array()
	var mesh_faces: Dictionary = {}
	for child: Node in visual_root.get_children():
		if not child is GeometryInstance3D or not materials.has(child.material_override):
			continue
		if child is MeshInstance3D:
			_append(faces, mesh_faces, child.mesh, [child.transform])
	# Use authored transforms, not GPU readback (dummy/headless returns identity).
	for batch: Dictionary in batches.values():
		if materials.has(batch.material):
			_append(faces, mesh_faces, batch.mesh, batch.transforms)
	if faces.is_empty():
		return null
	# Exact triangles preserve openings under arches; no solid bounding boxes.
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	var body := StaticBody3D.new()
	body.name = "CameraOnlyScenery"
	body.collision_layer = LAYER
	body.collision_mask = 0
	body.add_child(collider)
	body.set_meta("triangle_count", faces.size() / 3)
	visual_root.add_child(body)
	return body


static func _append(faces: PackedVector3Array, cache: Dictionary, mesh: Mesh, poses: Array) -> void:
	if mesh == null:
		return
	var id: int = mesh.get_instance_id()
	if not cache.has(id):
		cache[id] = mesh.get_faces()
	var local_faces: PackedVector3Array = cache[id]
	for pose: Transform3D in poses:
		for point: Vector3 in local_faces:
			faces.append(pose * point)
