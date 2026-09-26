class_name PrototypeTrack
extends Node3D

const RADIUS_X: float = 62.0
const RADIUS_Z: float = 42.0
const ROAD_WIDTH: float = 12.0
const SEGMENTS: int = 64
const SECTORS: int = 16
var _built: bool = false


func build(visuals: bool) -> void:
	if _built:
		return
	_built = true
	var road: StandardMaterial3D = _material(Color("566064")) if visuals else null
	var edge: StandardMaterial3D = _material(Color("d9eeee")) if visuals else null
	var cyan: StandardMaterial3D = _material(Color("64e3db")) if visuals else null
	var lime: StandardMaterial3D = _material(Color("e5ff58")) if visuals else null
	for index: int in SEGMENTS:
		var a: float = TAU * float(index) / SEGMENTS
		var b: float = TAU * float(index + 1) / SEGMENTS
		var start: Vector3 = _point(a)
		var end: Vector3 = _point(b)
		var center: Vector3 = (start + end) * 0.5
		var direction: Vector3 = (end - start).normalized()
		var normal: Vector3 = Vector3(direction.z, 0.0, -direction.x)
		var orientation: Basis = Basis.looking_at(direction, Vector3.UP)
		var length: float = start.distance_to(end) + 0.2
		_box(Vector3(ROAD_WIDTH, 1.0, length), Transform3D(orientation, center + Vector3.DOWN * 0.5), road, true)
		for side: float in [-1.0, 1.0]:
			var barrier_at: Vector3 = center + normal * side * (ROAD_WIDTH * 0.5 + 0.3)
			_box(Vector3(0.45, 1.0, length), Transform3D(orientation, barrier_at + Vector3.UP * 0.5), edge, true)
			if visuals:
				var curb: StandardMaterial3D = cyan if index % 2 == 0 else lime
				_box(Vector3(0.65, 0.035, length), Transform3D(orientation, center + normal * side * 5.65 + Vector3.UP * 0.02), curb, false)
		if visuals and index % 2 == 0:
			_box(Vector3(0.16, 0.025, 1.6), Transform3D(orientation, center + Vector3.UP * 0.025), edge, false)
	if visuals:
		_scenery(cyan, lime, edge)


func spawn_transform(slot: int) -> Transform3D:
	var row: int = maxi(slot, 0) / 2
	var angle: float = -0.018 - float(row) * 0.07
	var tangent: Vector3 = Vector3(-RADIUS_X * sin(angle), 0.0, RADIUS_Z * cos(angle)).normalized()
	var normal: Vector3 = Vector3(tangent.z, 0.0, -tangent.x)
	var lane: float = -2.4 if slot % 2 == 0 else 2.4
	return Transform3D(Basis.looking_at(tangent, Vector3.UP), _point(angle) + normal * lane + Vector3.UP * 0.65)


func sector_at(location: Vector3) -> int:
	return mini(SECTORS - 1, int(floor(progress_at(location) * SECTORS)))


func progress_at(location: Vector3) -> float:
	return fposmod(atan2(location.z / RADIUS_Z, location.x / RADIUS_X), TAU) / TAU


func _point(angle: float) -> Vector3:
	return Vector3(RADIUS_X * cos(angle), 0.0, RADIUS_Z * sin(angle))


func _box(size: Vector3, pose: Transform3D, material: StandardMaterial3D, collidable: bool) -> void:
	var parent: Node3D = self
	if collidable:
		var body: StaticBody3D = StaticBody3D.new()
		var collider: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		body.transform = pose
		add_child(body)
		parent = body
	if material != null:
		var visual: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = size
		visual.mesh = mesh
		visual.material_override = material
		if not collidable:
			visual.transform = pose
		parent.add_child(visual)


func _scenery(cyan: StandardMaterial3D, lime: StandardMaterial3D, edge: StandardMaterial3D) -> void:
	var water: StandardMaterial3D = _material(Color("329ba4"))
	var grass: StandardMaterial3D = _material(Color("3f8262"))
	_box(Vector3(1000.0, 1.0, 1000.0), Transform3D(Basis.IDENTITY, Vector3(0.0, -2.0, 0.0)), water, false)
	var island: MeshInstance3D = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.05
	cylinder.height = 1.0
	cylinder.radial_segments = 64
	island.mesh = cylinder
	island.scale = Vector3(53.0, 1.8, 33.0)
	island.position.y = -0.9
	island.material_override = grass
	add_child(island)
	for index: int in 12:
		var angle: float = float(index) * TAU / 12.0
		var position: Vector3 = Vector3(cos(angle) * 38.0, 0.0, sin(angle) * 21.0)
		_box(Vector3(0.9, 2.4, 0.9), Transform3D(Basis.IDENTITY, position + Vector3.UP * 1.2), edge, false)
		_box(Vector3(3.5, 3.0, 3.5), Transform3D(Basis(Vector3.UP, angle), position + Vector3.UP * 3.3), lime if index % 3 == 0 else grass, false)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.7, 5.5, 0.7), Transform3D(Basis.IDENTITY, Vector3(RADIUS_X + side * 6.9, 2.75, 0.0)), cyan, false)
	_box(Vector3(14.4, 0.8, 0.8), Transform3D(Basis.IDENTITY, Vector3(RADIUS_X, 5.1, 0.0)), lime, false)
	for index: int in 12:
		_box(Vector3(0.9, 0.03, 0.7), Transform3D(Basis.IDENTITY, Vector3(RADIUS_X - 5.0 + index * 0.9, 0.035, 0.0)), edge if index % 2 == 0 else cyan, false)


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material
