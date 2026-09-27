extends SceneTree

const ChaseCamera = preload("res://view/race_camera.gd")
const Track = preload("res://track/authored_track.gd")
const Baker = preload("res://track/track_baker.gd")
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


func _check_route() -> void:
	root.size = Vector2i(1600, 900)
	var track: Node3D = Track.new()
	root.add_child(track)
	track.build(false)
	_check(not track.data.is_empty(), "authored route fixture is valid")
	if track.data.is_empty():
		return
	await physics_frame
	var route_length: float = float(track.data.length)
	var steps: int = ceili(route_length / (30.0 / 60.0))
	for step: int in steps:
		var offset: float = float(step) * (30.0 / 60.0)
		var sample: Dictionary = track.sample_at(offset)
		var tangent: Vector3 = Baker.vector(sample.tangent)
		_car.global_transform = Transform3D(Basis.looking_at(tangent.slide(Vector3.UP).normalized(), Vector3.UP), Baker.vector(sample.position) + Vector3.UP * 0.36)
		_car.velocity = tangent * 30.0
		if step == 0:
			_controller.reset(_car)
		_controller.update(_car, 1.0 / 60.0, false, Baker.vector(track.sample_at(offset + 12.0).position))
		if step % 20 == 0:
			_check_view("authored route s=%.1f" % offset)
			var point_query := PhysicsPointQueryParameters3D.new()
			point_query.position = _camera.position
			point_query.exclude = [_car.get_rid()]
			_check(_car.get_world_3d().direct_space_state.intersect_point(point_query).is_empty(), "authored route camera stays outside barrier volumes")
	track.queue_free()
	await physics_frame


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
