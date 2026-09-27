extends SceneTree

const ChaseCamera = preload("res://view/race_camera.gd")
const CameraObstacles = preload("res://view/camera_obstacles.gd")
const Track = preload("res://track/authored_track.gd")
const Baker = preload("res://track/track_baker.gd")
const CAMERA_ONLY_LAYER: int = 4
const CAMERA_MASK: int = 1 | CAMERA_ONLY_LAYER
var checks: int = 0
var failures: int = 0
var _car: CharacterBody3D
var _camera: Camera3D
var _controller: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	_car = CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var car_shape := BoxShape3D.new()
	car_shape.size = Vector3(2.1, 2.0, 2.7)
	collision.shape = car_shape
	collision.position.y = 0.7
	_car.add_child(collision)
	root.add_child(_car)
	_camera = Camera3D.new()
	root.add_child(_camera)
	_controller = ChaseCamera.new()
	_controller.configure(_camera)
	await physics_frame
	_controller.reset(_car)
	_check(_camera.position.z > 6.0, "player collider is excluded from boom queries")
	_check(_camera.position.y > 3.0, "normal chase is above the car")
	_check(_camera.near <= 0.151, "near plane remains close enough for compressed booms")
	_check_view("flat chase")
	_check_translation_follow()
	var base_pose: Transform3D = _camera.transform
	var velocity_before: Vector3 = _car.velocity
	var transform_before: Transform3D = _car.transform
	_controller.update(_car, 1.0 / 60.0, false, Vector3(5.0, 3.5, -12.0))
	_check(_camera.position.x < 0.0, "turn hint gently exposes the road toward the bend")
	_check(_camera.transform != base_pose, "uphill hint adjusts framing")
	_check(_car.velocity == velocity_before and _car.transform == transform_before, "camera cannot mutate simulation")
	_check_view("uphill turn")

	for frame: int in 90:
		_car.position += Vector3(0.0, 0.03, -0.2)
		_car.velocity = Vector3(0.0, 1.8, -12.0)
		_controller.update(_car, 1.0 / 60.0, false, _car.position + Vector3(0.0, -2.0, -12.0))
	_check_view("crest")
	_check(absf(_camera.global_basis.x.y) < 0.0001, "crest keeps the horizon level")
	_check(_camera.position.y > _car.position.y + 2.0, "crest keeps an elevated road view")

	_controller.update(_car, 1.0 / 60.0, true)
	_check(_camera.position.z < _car.position.z - 6.0, "look-back switches sides without an orbit")
	_check_view("look-back")
	_controller.update(_car, 1.0 / 60.0, false)
	_check(_camera.position.z > _car.position.z + 6.0, "clearing look-back immediately restores chase")
	_car.position = Vector3(80.0, 14.0, 40.0)
	_controller.update(_car, 1.0 / 60.0)
	_check(_camera.position.distance_to(_car.position) < 10.0, "recovery snaps instead of flying across the track")
	_check_view("recovery")
	var pose_before: Transform3D = _camera.transform
	_controller.update(_car, NAN)
	_check(_camera.transform == pose_before, "invalid delta does not poison camera state")

	_car.position = Vector3.ZERO
	_car.velocity = Vector3.ZERO
	_controller.reset(_car)
	var wall: StaticBody3D = _box(Vector3(0.0, 3.0, 3.0), Vector3(10.0, 6.0, 0.5))
	await physics_frame
	_controller.update(_car, 1.0 / 60.0)
	_check(_camera.position.z < 2.6, "wall immediately compresses the boom after smoothing")
	_check(_camera.position.z > 1.0, "wall test does not collapse the camera into the car")
	_check_view("wall compression")
	wall.queue_free()
	await physics_frame
	var compressed: Vector3 = _camera.position
	_controller.update(_car, 1.0 / 60.0)
	_check(_camera.position.z > compressed.z and _camera.position.z < 6.0, "boom extends smoothly after obstruction clears")
	for frame: int in 90:
		_controller.update(_car, 1.0 / 60.0)
	_check(_camera.position.z > 7.0, "boom returns to normal length")

	var edge: StaticBody3D = _box(Vector3(0.22, 3.0, 3.0), Vector3(0.2, 6.0, 0.5))
	await physics_frame
	_controller.reset(_car)
	_check(_camera.position.z < 2.6, "near-plane corner rays catch obstacles missed by the centre ray")
	edge.queue_free()
	await physics_frame
	var bank: StaticBody3D = _box(Vector3(0.0, 1.0, 3.0), Vector3(20.0, 1.0, 20.0))
	bank.rotation.x = deg_to_rad(-28.0)
	await physics_frame
	_controller.reset(_car)
	var point_query := PhysicsPointQueryParameters3D.new()
	point_query.position = _camera.position
	point_query.exclude = [_car.get_rid()]
	_check(_car.get_world_3d().direct_space_state.intersect_point(point_query).is_empty(), "steep road behind the car cannot contain the camera")
	_check(_camera.position.z < 7.0, "road rise shortens the boom")
	_check_view("road collision")
	bank.queue_free()
	await physics_frame
	await _check_camera_layers()
	await _check_obstacle_factory()

	root.size = Vector2i(390, 844)
	_controller.reset(_car)
	_check(_camera.position.z > 8.0, "portrait adds room for the kart silhouette")
	_check_view("portrait chase")
	root.size = Vector2i(844, 390)
	_controller.reset(_car)
	_check(_camera.position.z < 8.0, "landscape restores the closer chase distance")
	_check_view("landscape chase")
	await _check_route()
	print("CAMERA_PROBE ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures == 0 else 1)


func _check_translation_follow() -> void:
	_car.position = Vector3.ZERO
	_car.velocity = Vector3.FORWARD * 30.0
	_controller.reset(_car)
	var initial_hero: Vector2 = _camera.unproject_position(_car.position + Vector3.UP * 0.8)
	for frame: int in 180:
		_car.position += _car.velocity / 60.0
		_controller.update(_car, 1.0 / 60.0)
	var expected_distance: float = ChaseCamera.BOOM_DISTANCE + (30.0 / 34.0) * 0.6
	var relative_camera: Vector3 = _camera.position - _car.position
	_check(absf(relative_camera.z - expected_distance) < 0.01, "30 m/s translation does not add speed/response to the boom")
	_check(absf(relative_camera.y - ChaseCamera.BOOM_HEIGHT) < 0.01, "translation preserves configured boom height")
	_check(absf((_controller._aim - _car.position).z + 2.2) < 0.01, "moving aim preserves the intended look-ahead")
	var moving_hero: Vector2 = _camera.unproject_position(_car.position + Vector3.UP * 0.8)
	_check(initial_hero.distance_to(moving_hero) < 0.5, "constant translation keeps hero screen placement stable")
	_check_view("30 m/s translation")
	_car.position = Vector3.ZERO
	_car.velocity = Vector3.ZERO
	_controller.reset(_car)


func _check_camera_layers() -> void:
	_car.transform = Transform3D.IDENTITY
	_car.velocity = Vector3.ZERO
	var other_kart: StaticBody3D = _box(Vector3(0.0, 3.0, 3.0), Vector3(10.0, 6.0, 0.5))
	other_kart.collision_layer = 2
	other_kart.collision_mask = 0
	await physics_frame
	_controller.reset(_car)
	_check(_camera.position.z > 7.0, "other karts on layer 2 do not compress the camera")
	other_kart.queue_free()
	await physics_frame
	var obstacle: StaticBody3D = _box(Vector3(0.0, 3.0, 3.0), Vector3(10.0, 6.0, 0.5))
	obstacle.collision_layer = CAMERA_ONLY_LAYER
	obstacle.collision_mask = 0
	await physics_frame
	_controller.reset(_car)
	_check(_camera.position.z > 1.0 and _camera.position.z < 2.6, "camera-only layer compresses the boom")
	_check_view("camera-only obstruction")
	var previous_layer: int = _car.collision_layer
	var previous_mask: int = _car.collision_mask
	_car.collision_layer = 2
	_car.collision_mask = 1
	for tick: int in 60:
		await physics_frame
		_car.velocity = Vector3.BACK * 6.0
		_car.move_and_slide()
	_check(_car.position.z > 5.9, "vehicle mask 1 passes through camera-only geometry")
	_check(_car.get_slide_collision_count() == 0, "camera-only geometry does not register a vehicle contact")
	_car.collision_layer = previous_layer
	_car.collision_mask = previous_mask
	_car.transform = Transform3D.IDENTITY
	_car.velocity = Vector3.ZERO
	obstacle.queue_free()
	await physics_frame
	_controller.reset(_car)
	_check(_camera.position.z > 7.0, "camera-only obstacle removal restores an unobstructed boom")


func _check_obstacle_factory() -> void:
	var visual_root := Node3D.new()
	visual_root.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(50.0, 0.0, -20.0))
	root.add_child(visual_root)
	var opaque := StandardMaterial3D.new()
	var transparent := StandardMaterial3D.new()
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 5.0, 0.5)
	var direct := MeshInstance3D.new()
	direct.mesh = mesh
	direct.material_override = opaque
	direct.transform = Transform3D(Basis(Vector3.UP, -0.3).scaled(Vector3(1.1, 0.8, 1.2)), Vector3(-12.0, 2.0, 3.0))
	visual_root.add_child(direct)
	var excluded := MeshInstance3D.new()
	excluded.mesh = mesh
	excluded.material_override = transparent
	excluded.position = Vector3(0.0, 2.0, 3.0)
	visual_root.add_child(excluded)
	var poses: Array[Transform3D] = [
		Transform3D(Basis(Vector3.UP, 0.2).scaled(Vector3(0.8, 1.2, 1.0)), Vector3(8.0, 2.0, 3.0)),
		Transform3D(Basis(Vector3.UP, -0.15).scaled(Vector3(1.3, 0.9, 0.8)), Vector3(16.0, 2.0, 3.0)),
	]
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = poses.size()
	for index: int in poses.size():
		multi.set_instance_transform(index, poses[index])
	var batched_visual := MultiMeshInstance3D.new()
	batched_visual.multimesh = multi
	batched_visual.material_override = opaque
	visual_root.add_child(batched_visual)
	var batches: Dictionary = {
		"opaque": {"mesh": mesh, "material": opaque, "transforms": poses},
		"transparent": {"mesh": mesh, "material": transparent, "transforms": [Transform3D(Basis.IDENTITY, Vector3(24.0, 2.0, 3.0))]},
	}
	var materials: Array[Material] = [opaque]
	var obstacle: StaticBody3D = CameraObstacles.build_from(visual_root, materials, batches)
	_check(obstacle != null, "obstacle factory creates a body for whitelisted geometry")
	if obstacle == null:
		visual_root.queue_free()
		await physics_frame
		return
	var shapes: Array[Node] = obstacle.find_children("*", "CollisionShape3D", true, false)
	_check(shapes.size() == 1 and shapes[0].shape is ConcavePolygonShape3D, "obstacle factory aggregates geometry into one concave shape")
	if shapes.size() == 1 and shapes[0].shape is ConcavePolygonShape3D:
		var shape: ConcavePolygonShape3D = shapes[0].shape
		var local_faces: PackedVector3Array = mesh.get_faces()
		var expected := PackedVector3Array()
		var expected_poses: Array[Transform3D] = [direct.transform, poses[0], poses[1]]
		for pose: Transform3D in expected_poses:
			for point: Vector3 in local_faces:
				expected.append(pose * point)
		var actual: PackedVector3Array = shape.get_faces()
		var matches: bool = actual.size() == expected.size()
		for index: int in mini(actual.size(), expected.size()):
			matches = matches and actual[index].is_equal_approx(expected[index])
		_check(matches, "factory preserves exact MeshInstance and CPU batch transforms while excluding both transparent sources")
		_check(shape.backface_collision and int(obstacle.get_meta("triangle_count")) == expected.size() / 3, "factory retains backfaces and the exact triangle count")
	await physics_frame
	var previous_transform: Transform3D = _car.transform
	var previous_velocity: Vector3 = _car.velocity
	_car.global_transform = visual_root.global_transform * Transform3D(Basis.IDENTITY, Vector3(8.0, 0.0, 0.0))
	_car.velocity = Vector3.ZERO
	_controller.reset(_car)
	var batch_camera: Vector3 = visual_root.to_local(_camera.global_position)
	_check(batch_camera.z > 1.0 and batch_camera.z < 2.9, "camera clips at the transformed CPU batch location")
	_car.global_transform = visual_root.global_transform
	_controller.reset(_car)
	_check(visual_root.to_local(_camera.global_position).z > 7.0, "GPU identity readback and excluded transparent mesh do not create an origin obstruction")
	_car.global_transform = visual_root.global_transform * Transform3D(Basis.IDENTITY, Vector3(24.0, 0.0, 0.0))
	_controller.reset(_car)
	_check(visual_root.to_local(_camera.global_position).z > 7.0, "excluded transparent batch does not obstruct the camera")
	_car.transform = previous_transform
	_car.velocity = previous_velocity
	visual_root.queue_free()
	await physics_frame
	_controller.reset(_car)


func _check_route() -> void:
	root.size = Vector2i(1600, 900)
	var track: Node3D = Track.new()
	root.add_child(track)
	_check(not track.data.is_empty(), "authored route fixture is valid")
	if track.data.is_empty():
		track.queue_free()
		return
	var simulation_hash: String = Baker.simulation_hash(track.data)
	track.build(true)
	var camera_only_bodies: int = 0
	for body: CollisionObject3D in track.find_children("*", "CollisionObject3D", true, false):
		if body.collision_layer & CAMERA_ONLY_LAYER:
			camera_only_bodies += 1
			_check(body.collision_layer == CAMERA_ONLY_LAYER and body.collision_mask == 0, "authored camera obstacle has an isolated layer and no response mask")
	_check(camera_only_bodies > 0, "client route builds camera-only environment obstacles")
	_check(Baker.simulation_hash(track.data) == simulation_hash, "camera obstacles preserve the baked simulation identity")
	await physics_frame
	var route_length: float = float(track.data.length)
	var steps: int = ceili(route_length / (30.0 / 60.0))
	for low: bool in [false, true]:
		track.set_quality(low)
		for look_back: bool in [false, true]:
			for step: int in steps:
				var offset: float = float(step) * (30.0 / 60.0)
				var sample: Dictionary = track.sample_at(offset)
				var tangent: Vector3 = Baker.vector(sample.tangent)
				_car.global_transform = Transform3D(Basis.looking_at(tangent.slide(Vector3.UP).normalized(), Vector3.UP), Baker.vector(sample.position) + Vector3.UP * 0.36)
				_car.velocity = tangent * 30.0
				if step == 0:
					_controller.reset(_car)
				_controller.update(_car, 1.0 / 60.0, look_back, Baker.vector(track.sample_at(offset + 12.0).position))
				if step % 20 == 0:
					var label: String = "authored %s %s s=%.1f" % ["Low" if low else "Standard", "look-back" if look_back else "chase", offset]
					_check_view(label)
					var point_query := PhysicsPointQueryParameters3D.new()
					point_query.position = _camera.position
					point_query.collision_mask = CAMERA_MASK
					point_query.exclude = [_car.get_rid()]
					_check(_car.get_world_3d().direct_space_state.intersect_point(point_query).is_empty(), label + ": camera stays outside solid obstacle volumes")
					_check_boom_clear(label)
		_check(Baker.simulation_hash(track.data) == simulation_hash, "quality switch preserves simulation identity with camera obstacles")
	track.queue_free()
	await physics_frame
	var server_track: Node3D = Track.new()
	root.add_child(server_track)
	server_track.build(false)
	var server_camera_bodies: int = 0
	for body: CollisionObject3D in server_track.find_children("*", "CollisionObject3D", true, false):
		if body.collision_layer & CAMERA_ONLY_LAYER:
			server_camera_bodies += 1
	_check(server_camera_bodies == 0, "headless route does not build client camera obstacles")
	_check(Baker.simulation_hash(server_track.data) == simulation_hash, "client and headless route retain identical simulation data")
	server_track.queue_free()
	await physics_frame


func _check_boom_clear(label: String) -> void:
	var anchor: Vector3 = _car.global_position + Vector3.UP * 1.05
	var boom: Vector3 = _camera.global_position - anchor
	if boom.length_squared() < 0.0001:
		_check(false, label + ": boom must not collapse into its anchor")
		return
	var right: Vector3 = boom.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	var up: Vector3 = right.cross(boom.normalized()).normalized()
	var offsets: Array[Vector3] = [Vector3.ZERO]
	for side: float in [-1.0, 1.0]:
		for vertical: float in [-1.0, 1.0]:
			offsets.append((right * side + up * vertical).normalized() * ChaseCamera.CAMERA_RADIUS)
	var clear: bool = true
	var space: PhysicsDirectSpaceState3D = _car.get_world_3d().direct_space_state
	for offset: Vector3 in offsets:
		var query := PhysicsRayQueryParameters3D.create(anchor + offset, _camera.global_position + offset, CAMERA_MASK, [_car.get_rid()])
		query.hit_from_inside = true
		clear = clear and space.intersect_ray(query).is_empty()
	_check(clear, label + ": boom and near-plane corner rays do not cross opaque geometry")


func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	root.add_child(body)
	return body


func _check_view(label: String) -> void:
	_check(_camera.global_transform.is_finite(), label + ": finite pose")
	var head: Vector3 = _car.global_position + Vector3.UP * 1.6
	var body: Vector3 = _car.global_position + Vector3.UP * 0.8
	_check(not _camera.is_position_behind(head) and not _camera.is_position_behind(body), label + ": kart stays in front of camera")
	var viewport_size: Vector2 = _camera.get_viewport().get_visible_rect().size
	var image_point: Vector2 = _camera.unproject_position(body) / viewport_size
	_check(image_point.x > 0.15 and image_point.x < 0.85 and image_point.y > 0.25 and image_point.y < 0.78, label + ": kart body stays above the bottom HUD band")


func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + description)
