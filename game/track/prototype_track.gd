class_name PrototypeTrack
extends Node3D

const Visuals = preload("res://track/fantasy_track_visuals.gd")

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
		_box(Vector3(ROAD_WIDTH, 1.0, length), Transform3D(orientation, center + Vector3.DOWN * 0.5))
		for side: float in [-1.0, 1.0]:
			var barrier_at: Vector3 = center + normal * side * (ROAD_WIDTH * 0.5 + 0.3)
			_box(Vector3(0.45, 1.0, length), Transform3D(orientation, barrier_at + Vector3.UP * 0.5))
	if visuals:
		var scenery: Node3D = Visuals.new()
		scenery.name = "FantasyScenery"
		add_child(scenery)
		scenery.build(RADIUS_X, RADIUS_Z, ROAD_WIDTH)


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


func _box(size: Vector3, pose: Transform3D) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	body.transform = pose
	add_child(body)
