class_name AuthoredTrack
extends Node3D

const Baker = preload("res://track/track_baker.gd")
const Progress = preload("res://track/route_progress.gd")
const PACKAGE_PATH: String = "res://track/baked/castle_waterfalls.json"

var data: Dictionary = {}
var load_errors: PackedStringArray = PackedStringArray()
var _built: bool = false
var _visual: Node3D


func _init() -> void:
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACKAGE_PATH))
	if decoded is Dictionary:
		load_errors = Baker.package_errors(decoded)
		if load_errors.is_empty():
			data = decoded
	else:
		load_errors.append("Track package is not a JSON object")


func build(visuals: bool) -> void:
	if _built or data.is_empty():
		return
	_built = true
	var body := StaticBody3D.new()
	body.name = "RoadCollision"
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array()
	for point: Array in data.collision.road_faces:
		faces.append(Baker.vector(point))
	shape.set_faces(faces)
	shape.backface_collision = bool(data.collision.road_backface)
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	for barrier: Dictionary in data.collision.barriers:
		var wall := StaticBody3D.new()
		var wall_collider := CollisionShape3D.new()
		var wall_shape := BoxShape3D.new()
		wall_shape.size = Baker.vector(barrier.size)
		wall_collider.shape = wall_shape
		wall.add_child(wall_collider)
		wall.transform = Transform3D(Basis.looking_at(Baker.vector(barrier.forward), Vector3.UP), Baker.vector(barrier.position))
		add_child(wall)
	if visuals:
		# Only the client loads material/mesh dependencies.
		var visual_script: Script = load("res://track/authored_track_study.gd")
		_visual = visual_script.new()
		add_child(_visual)
		_visual.build(data)


func set_quality(low: bool) -> void:
	if is_instance_valid(_visual):
		_visual.set_quality(low)


func set_reduced_effects(enabled: bool) -> void:
	if is_instance_valid(_visual):
		_visual.set_reduced_effects(enabled)


func identity() -> Dictionary:
	var result: Dictionary = {}
	if data.is_empty():
		return result
	for key: String in ["track_id", "schema_version", "simulation_revision", "simulation_hash", "art_revision"]:
		result[key] = data[key]
	return result


func descriptor() -> Dictionary:
	return Baker.compact(data) if not data.is_empty() else {}


func spawn_transform(slot: int) -> Transform3D:
	return _pose(data.starts[clampi(slot, 0, 9)]) if not data.is_empty() else Transform3D.IDENTITY


func sample_at(s: float) -> Dictionary:
	return Baker.sample_at(data, s)


func initial_progress() -> Dictionary:
	return Progress.initial_state()


func advance_progress(state: Dictionary, previous: Vector3, current: Vector3, discontinuity: bool = false) -> Array:
	return Progress.advance(data, state, previous, current, discontinuity)


func standings_distance(state: Dictionary, location: Vector3) -> float:
	return Progress.standings_distance(data, state, location)


func recovery_transform(state: Dictionary) -> Transform3D:
	return _pose(Progress.recovery_anchor(data, state))


func mark_recovered(state: Dictionary) -> void:
	Progress.recover(state)


func needs_recovery(location: Vector3) -> bool:
	return Progress.needs_recovery(data, location)


func _pose(anchor: Dictionary) -> Transform3D:
	var forward: Vector3 = Baker.vector(anchor.forward)
	forward.y = 0.0
	return Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), Baker.vector(anchor.position))
