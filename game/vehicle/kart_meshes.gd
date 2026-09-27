extends RefCounted


static func material(color: Color, roughness: float = 0.55, metallic: float = 0.0, emission: float = 0.0) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	if emission > 0.0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = emission
	return result


static func add(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3 = Vector3.ZERO, angles: Vector3 = Vector3.ZERO, size: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var result: MeshInstance3D = MeshInstance3D.new()
	result.mesh = mesh
	result.material_override = mat
	result.position = at
	result.rotation = angles
	result.scale = size
	parent.add_child(result)
	return result


static func ellipsoid(parent: Node3D, at: Vector3, radii: Vector3, mat: Material, segments: int = 20) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = segments
	mesh.rings = 12
	return add(parent, mesh, mat, at, Vector3.ZERO, radii)


static func cylinder(parent: Node3D, at: Vector3, radius: float, length: float, mat: Material, angles: Vector3 = Vector3.ZERO, top: float = -1.0) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius if top < 0.0 else top
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 24
	return add(parent, mesh, mat, at, angles)


static func box(parent: Node3D, at: Vector3, size: Vector3, mat: Material, angles: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return add(parent, mesh, mat, at, angles)


## Smooth cross-section lofts author the bodywork, hat, beard and tire profiles.
static func loft(rings: Array[PackedVector3Array], smooth: bool = true, close_ends: bool = true) -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_normal(Vector3.UP)
	var count: int = rings[0].size()
	for row: int in range(rings.size() - 1):
		for col: int in range(count):
			var next: int = (col + 1) % count
			_triangle(surface, rings[row][col], rings[row + 1][col], rings[row][next], smooth)
			_triangle(surface, rings[row][next], rings[row + 1][col], rings[row + 1][next], smooth)
	if close_ends:
		for end: int in [0, rings.size() - 1]:
			var center: Vector3 = Vector3.ZERO
			for point: Vector3 in rings[end]:
				center += point / float(count)
			for col: int in range(count):
				var next: int = (col + 1) % count
				if end == 0:
					_triangle(surface, center, rings[end][col], rings[end][next], false)
				else:
					_triangle(surface, center, rings[end][next], rings[end][col], false)
	if smooth:
		surface.index()
		surface.generate_normals()
	return surface.commit()


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, smooth: bool) -> void:
	# Godot front faces are clockwise; the parameterized rings are clockwise outside.
	if not smooth:
		surface.set_normal((c - a).cross(b - a).normalized())
	for point: Vector3 in [a, b, c]:
		surface.add_vertex(point)


static func tube(points: PackedVector3Array, radii: PackedFloat32Array, sides: int = 10) -> ArrayMesh:
	var rings: Array[PackedVector3Array] = []
	for i: int in range(points.size()):
		var tangent: Vector3 = points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		tangent = tangent.normalized()
		var axis: Vector3 = Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
		var u: Vector3 = tangent.cross(axis).normalized()
		var v: Vector3 = tangent.cross(u).normalized()
		var ring: PackedVector3Array = []
		for j: int in range(sides):
			var angle: float = TAU * float(j) / float(sides)
			ring.append(points[i] + (u * cos(angle) + v * sin(angle)) * radii[mini(i, radii.size() - 1)])
		rings.append(ring)
	return loft(rings)


static func line(parent: Node3D, points: PackedVector3Array, radius: float, mat: Material, smooth_path: bool = false) -> MeshInstance3D:
	var path: PackedVector3Array = curve(points) if smooth_path else points
	return add(parent, tube(path, PackedFloat32Array([radius])), mat)


static func curve(points: PackedVector3Array, subdivisions: int = 4) -> PackedVector3Array:
	var result: PackedVector3Array = []
	for i: int in range(points.size() - 1):
		for j: int in range(subdivisions):
			var t: float = float(j) / float(subdivisions)
			result.append(points[i].cubic_interpolate(points[i + 1], points[maxi(0, i - 1)], points[mini(points.size() - 1, i + 2)], t))
	result.append(points[points.size() - 1])
	return result


static func circle(center: Vector3, u: Vector3, v: Vector3, radius: float, segments: int = 32) -> PackedVector3Array:
	var points: PackedVector3Array = []
	for i: int in range(segments + 1):
		var angle: float = TAU * float(i) / float(segments)
		points.append(center + radius * (u * cos(angle) + v * sin(angle)))
	return points


static func horizontal_ring(center: Vector3, radius_x: float, radius_z: float, segments: int = 24, ripple: float = 0.0) -> PackedVector3Array:
	var ring: PackedVector3Array = []
	for i: int in range(segments):
		var angle: float = -TAU * float(i) / float(segments)
		var fold: float = 1.0 + ripple * sin(angle * 5.0 + center.y * 9.0)
		ring.append(center + Vector3(cos(angle) * radius_x * fold, 0.0, sin(angle) * radius_z * fold))
	return ring


## Merge rigid decorative parts by material to keep the authored detail browser-friendly.
static func bake(root: Node3D) -> void:
	var batches: Dictionary = {}
	_collect(root, Transform3D.IDENTITY, batches)
	for child: Node in root.get_children():
		root.remove_child(child)
		child.free()
	for key: int in batches:
		var batch: Dictionary = batches[key]
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part: Dictionary in batch["parts"]:
			surface.append_from(part["mesh"], part["surface"], part["transform"])
		var visual: MeshInstance3D = add(root, surface.commit(), batch["material"])
		visual.name = "MaterialBatch%d" % root.get_child_count()


static func _collect(root: Node3D, transform: Transform3D, batches: Dictionary) -> void:
	for child: Node in root.get_children():
		if not child is Node3D:
			continue
		var node: Node3D = child
		var relative: Transform3D = transform * node.transform
		if node is MeshInstance3D:
			var instance: MeshInstance3D = node
			for surface: int in range(instance.mesh.get_surface_count()):
				var mat: Material = instance.material_override
				if mat == null:
					mat = instance.mesh.surface_get_material(surface)
				var key: int = mat.get_instance_id()
				if not batches.has(key):
					batches[key] = {"material": mat, "parts": []}
				batches[key]["parts"].append({"mesh": instance.mesh, "surface": surface, "transform": relative})
		_collect(node, relative, batches)
