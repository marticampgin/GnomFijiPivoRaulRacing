class_name AuthoredTrack
extends Node3D

const Baker = preload("res://track/track_baker.gd")
const Progress = preload("res://track/route_progress.gd")
const Event = preload("res://race/track_event.gd")
const PACKAGE_PATH: String = "res://track/baked/castle_waterfalls.json"

var data: Dictionary = {}
var load_errors: PackedStringArray = PackedStringArray()
var _built: bool = false
var _visual: Node3D
var _event_bodies: Array[StaticBody3D] = []
var _event_markers: Array[Node3D] = []
var _event_meshes: Array[Node3D] = []
var _event_state: Dictionary = {"phase": "idle", "remaining": 0.0, "active": [false, false], "trigger_tick": 0}


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
	_build_event(visuals)


func _build_event(visuals: bool) -> void:
	for definition: Dictionary in Event.definitions(self):
		var body := StaticBody3D.new()
		body.collision_layer = 0
		body.transform = definition.transform
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = definition.size
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
		_event_bodies.append(body)
		if visuals:
			var marker := Node3D.new()
			add_child(marker)
			marker.transform = definition.transform
			for side: float in [-1.0, 1.0]:
				_event_box(marker, Vector3(side * definition.size.x * 0.5, -definition.size.y * 0.5 + 0.04, 0), Vector3(0.12, 0.08, definition.size.z + 0.4), Color("ffd36b"))
			var mesh_root := Node3D.new()
			body.add_child(mesh_root)
			_event_box(mesh_root, Vector3.ZERO, definition.size, Color("596561"))
			_event_box(mesh_root, Vector3(0, definition.size.y * 0.3, -definition.size.z * 0.5 - 0.015), Vector3(definition.size.x, 0.22, 0.04), Color("64e3db"))
			_event_box(mesh_root, Vector3(0, definition.size.y * 0.3, definition.size.z * 0.5 + 0.015), Vector3(definition.size.x, 0.22, 0.04), Color("64e3db"))
			_event_meshes.append(mesh_root)
			_event_markers.append(marker)
	apply_event(_event_state)


func _event_box(parent: Node3D, location: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	mesh.position = location
	parent.add_child(mesh)


func apply_event(state: Dictionary) -> void:
	if not Event.validate_snapshot(state):
		return
	_event_state = state.duplicate(true)
	for index: int in _event_bodies.size():
		_event_bodies[index].collision_layer = 1 if state.active[index] else 0
		if index < _event_meshes.size():
			_event_meshes[index].visible = state.active[index]
			_event_markers[index].visible = state.phase != "idle" and not state.active[index]


func event_lane(distance: float, normal_lane: float) -> float:
	if _event_state.phase == "idle":
		return normal_lane
	var s: float = fposmod(distance, float(data.length))
	for definition: Dictionary in Event.definitions(self):
		var offset: float = s - float(definition.s)
		if offset >= -32.0 and offset <= 18.0:
			var weight: float = smoothstep(-32.0, -16.0, offset) * (1.0 - smoothstep(8.0, 18.0, offset))
			return lerpf(normal_lane, -signf(float(definition.lateral)) * 2.8, weight)
	return normal_lane


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
