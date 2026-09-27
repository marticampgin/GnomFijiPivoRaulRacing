extends RefCounted

const CameraObstacles = preload("res://view/camera_obstacles.gd")
const COLLISION_MASK: int = 1 | CameraObstacles.LAYER
const BOOM_DISTANCE: float = 7.1
const BOOM_HEIGHT: float = 3.5
const POSITION_RESPONSE: float = 8.0
const AIM_RESPONSE: float = 9.0
const CAMERA_RADIUS: float = 0.28
const COLLISION_MARGIN: float = 0.12
const TELEPORT_DISTANCE: float = 12.0

var _camera: Camera3D
var _started: bool = false
var _last_target: Vector3 = Vector3.ZERO
var _last_look_back: bool = false
var _aim: Vector3 = Vector3.ZERO


func configure(camera: Camera3D) -> void:
	_camera = camera
	_started = false
	if is_instance_valid(_camera):
		_camera.near = 0.15
		_camera.fov = 58.0


func reset(target: CharacterBody3D) -> void:
	_started = false
	update(target, 0.0)


## Call in the client physics tick. The optional hint is a world-space road point.
func update(target: CharacterBody3D, delta: float, look_back: bool = false, route_look_ahead: Vector3 = Vector3.INF) -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(target):
		return
	if not _camera.is_inside_tree() or not target.is_inside_tree() or not is_finite(delta) or delta < 0.0:
		return
	if not target.global_transform.is_finite():
		return
	var origin: Vector3 = target.global_position
	var forward: Vector3 = -target.global_basis.z.slide(Vector3.UP)
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var velocity: Vector3 = target.velocity if target.velocity.is_finite() else Vector3.ZERO
	var horizontal_speed: float = velocity.slide(Vector3.UP).length()
	var slope: float = clampf(velocity.y / horizontal_speed, -0.3, 0.3) if horizontal_speed > 2.0 else 0.0
	if route_look_ahead.is_finite() and not look_back:
		var road_delta: Vector3 = route_look_ahead - origin
		var road_horizontal: Vector3 = road_delta.slide(Vector3.UP)
		var road_distance: float = road_horizontal.length()
		if road_distance > 2.0 and road_distance < 35.0 and road_horizontal.normalized().dot(forward) > 0.55:
			forward = forward.lerp(road_horizontal.normalized(), 0.2).normalized()
			slope = clampf(road_delta.y / road_distance, -0.3, 0.3)
	if look_back:
		forward = -forward
		slope = -slope
	var viewport_size: Vector2 = _camera.get_viewport().get_visible_rect().size
	var portrait: bool = viewport_size.x < viewport_size.y
	var distance: float = BOOM_DISTANCE * (1.25 if portrait else 1.0) + clampf(horizontal_speed / 34.0, 0.0, 1.0) * 0.6
	var height: float = BOOM_HEIGHT * (1.1 if portrait else 1.0)
	var desired: Vector3 = origin - forward * distance + Vector3.UP * (height - slope * distance * 0.6)
	var desired_aim: Vector3 = origin + forward * 2.2 + Vector3.UP * (1.15 + slope * 2.2)
	var anchor: Vector3 = origin + Vector3.UP * 1.05
	var space: PhysicsDirectSpaceState3D = target.get_world_3d().direct_space_state
	var exclude: Array[RID] = [target.get_rid()]
	desired = _clear_boom(anchor, desired, space, exclude)
	var snap: bool = not _started or look_back != _last_look_back or origin.distance_to(_last_target) > TELEPORT_DISTANCE
	var position: Vector3 = desired
	if snap:
		_aim = desired_aim
	else:
		var dt: float = minf(delta, 0.1)
		# Carry target translation immediately; only the relative framing eases.
		var translation: Vector3 = origin - _last_target
		position = (_camera.global_position + translation).lerp(desired, 1.0 - exp(-POSITION_RESPONSE * dt))
		_aim = (_aim + translation).lerp(desired_aim, 1.0 - exp(-AIM_RESPONSE * dt))
	# Clip again after smoothing: pulling inward must never lag behind a wall.
	_camera.global_position = _clear_boom(anchor, position, space, exclude)
	if _camera.global_position.distance_squared_to(_aim) > 0.0001:
		_camera.look_at(_aim, Vector3.UP)
	_last_target = origin
	_last_look_back = look_back
	_started = true


func _clear_boom(anchor: Vector3, desired: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> Vector3:
	var boom: Vector3 = desired - anchor
	var length: float = boom.length()
	if length < 0.001:
		return desired
	var right: Vector3 = boom.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	var up: Vector3 = right.cross(boom.normalized()).normalized()
	var offsets: Array[Vector3] = [Vector3.ZERO]
	for side: float in [-1.0, 1.0]:
		for vertical: float in [-1.0, 1.0]:
			offsets.append((right * side + up * vertical).normalized() * CAMERA_RADIUS)
	var allowed: float = length
	for offset: Vector3 in offsets:
		var query := PhysicsRayQueryParameters3D.create(anchor + offset, desired + offset, COLLISION_MASK, exclude)
		query.hit_from_inside = true
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			allowed = minf(allowed, maxf(0.0, (Vector3(hit["position"]) - anchor - offset).length() - COLLISION_MARGIN))
	return anchor + boom * (allowed / length)
