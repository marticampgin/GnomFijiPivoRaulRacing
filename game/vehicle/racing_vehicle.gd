class_name RacingVehicle
extends CharacterBody3D

const STATE_VERSION: int = 1
const BALANCE_VERSION: String = "vehicle-prototype-v8"
const COLLISION_SIZE: Vector3 = Vector3(2.18, 0.7, 2.696)
const COLLISION_BEVEL: float = 0.1
const DEFAULT_STATS: Dictionary = {
	"top_speed": 34.0,
	"acceleration": 17.0,
	"handling": 1.0,
	"drift": 1.0,
	"durability": 100.0,
}
const GRAVITY: float = 28.0
const DRIFT_MIN_SPEED: float = 8.0
const DRIFT_MIN_STEERING: float = 0.18
const DRIFT_MIN_SLIP: float = 0.05
const DRIFT_MAX_SLIP: float = 1.2
const BOOST_MIN_CHARGE: float = 0.25
const REVERSE_MAX_SPEED: float = 8.0
const REVERSE_ACCELERATION: float = 10.0

var stats: Dictionary = DEFAULT_STATS.duplicate()
var grounded: bool = false
var is_drifting: bool = false
var drift_charge: float = 0.0
var boost_remaining: float = 0.0
var speed_mps: float = 0.0
var steering_amount: float = 0.0
var _drift_was_pressed: bool = false


static func create_collision_shape() -> ConvexPolygonShape3D:
	# Chamfer the box edges so internal road triangles do not act as walls.
	var half: Vector3 = COLLISION_SIZE * 0.5
	var inset: Vector3 = half - Vector3.ONE * COLLISION_BEVEL
	var points := PackedVector3Array()
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				points.append(Vector3(x * half.x, y * inset.y, z * inset.z))
				points.append(Vector3(x * inset.x, y * half.y, z * inset.z))
				points.append(Vector3(x * inset.x, y * inset.y, z * half.z))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(55.0)
	floor_constant_speed = true
	floor_stop_on_slope = true
	safe_margin = 0.01


func configure(overrides: Dictionary = {}) -> void:
	stats = DEFAULT_STATS.duplicate()
	for key: String in DEFAULT_STATS:
		var value: float = float(overrides.get(key, DEFAULT_STATS[key]))
		if not is_finite(value):
			continue
		if key == "handling" or key == "drift":
			stats[key] = clampf(value, 0.35, 2.0)
		else:
			stats[key] = clampf(value, 1.0, 200.0)


## Call once from the physics tick; body forward is -Z. Track supplies local up.
func step(input: Dictionary, delta: float, gravity_up: Vector3 = Vector3.UP) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var dt: float = minf(delta, 0.05)
	if gravity_up.is_finite() and gravity_up.length_squared() > 0.0001:
		up_direction = gravity_up.normalized()
	var forward: Vector3 = -global_basis.z
	forward = forward.slide(up_direction)
	if forward.length_squared() < 0.0001:
		forward = global_basis.x.cross(up_direction)
	forward = forward.normalized()
	var right: Vector3 = forward.cross(up_direction).normalized()
	global_basis = Basis(right, up_direction, -forward).orthonormalized()

	var steering: float = _axis(input, "steering", -1.0, 1.0)
	var throttle: float = _axis(input, "throttle", 0.0, 1.0)
	var brake: float = _axis(input, "brake", 0.0, 1.0)
	var drift_pressed: bool = bool(input.get("drift", false))
	var drive_blocked: bool = bool(input.get("drive_blocked", false))
	if drive_blocked:
		steering = 0.0
		throttle = 0.0
		brake = 1.0
		drift_pressed = false
		is_drifting = false
		drift_charge = 0.0
	var vertical_speed: float = velocity.dot(up_direction)
	var planar: Vector3 = velocity.slide(up_direction)
	var forward_speed: float = planar.dot(forward)
	var on_surface: bool = grounded and vertical_speed <= 0.5
	# Godot's slope-stop correction can pin a powered box collider to a seam.
	# Retain idle slope holding, but let active driving slide across triangles.
	floor_stop_on_slope = (drive_blocked or (throttle <= 0.01 and brake <= 0.01)) and planar.length_squared() < 0.25
	boost_remaining = maxf(0.0, boost_remaining - dt)

	if _drift_was_pressed and not drift_pressed:
		if on_surface and is_drifting and drift_charge >= BOOST_MIN_CHARGE:
			boost_remaining = 0.5 + drift_charge * 1.5
		drift_charge = 0.0
	is_drifting = (drift_pressed and on_surface and forward_speed >= DRIFT_MIN_SPEED
		and absf(steering) >= DRIFT_MIN_STEERING)
	if is_drifting:
		var slip_angle: float = absf(atan2(planar.dot(right), forward_speed))
		if slip_angle >= DRIFT_MIN_SLIP and slip_angle <= DRIFT_MAX_SLIP:
			drift_charge = minf(1.0, drift_charge + dt * 0.52 * float(stats["drift"]))
		elif slip_angle > DRIFT_MAX_SLIP:
			drift_charge = 0.0
	elif drift_pressed or not on_surface:
		drift_charge = 0.0
	_drift_was_pressed = drift_pressed
	steering_amount = steering

	var speed_ratio: float = clampf(absf(forward_speed) / 8.0, 0.0, 1.0)
	# A small powered-steering assist lets the kart leave a head-on barrier stop.
	if on_surface and throttle > 0.1 and brake < 0.1:
		speed_ratio = maxf(speed_ratio, 0.35 * throttle)
	var turn_rate: float = 1.32 * float(stats["handling"])
	if is_drifting:
		turn_rate *= 1.15 + 0.2 * float(stats["drift"])
	if not on_surface:
		turn_rate *= 0.22
	var travel_direction: float = -1.0 if forward_speed < -0.1 else 1.0
	forward = forward.rotated(up_direction, -steering * turn_rate * speed_ratio * travel_direction * dt)
	right = forward.cross(up_direction).normalized()
	global_basis = Basis(right, up_direction, -forward).orthonormalized()

	var longitudinal: float = planar.dot(forward)
	var lateral: float = planar.dot(right)
	if on_surface:
		var acceleration: float = float(stats["acceleration"]) * throttle
		var max_speed: float = float(stats["top_speed"])
		if boost_remaining > 0.0 and brake <= 0.01 and longitudinal >= 0.0 and not drive_blocked:
			acceleration += 22.0
			max_speed *= 1.28
		# Opposite pedals first stop travel. Reverse begins only on the next tick.
		if drive_blocked or (brake > 0.01 and (longitudinal > 0.0 or throttle > 0.01)):
			longitudinal = move_toward(longitudinal, 0.0, (brake * 34.0 + 1.2) * dt)
		elif brake > 0.01:
			if longitudinal < -REVERSE_MAX_SPEED:
				longitudinal = move_toward(longitudinal, -REVERSE_MAX_SPEED, 4.0 * dt)
			else:
				longitudinal = maxf(-REVERSE_MAX_SPEED, longitudinal - REVERSE_ACCELERATION * brake * dt)
		elif longitudinal < 0.0:
			longitudinal = move_toward(longitudinal, 0.0, (throttle * 34.0 + 1.2) * dt)
		# Contact momentum and expired boost coast down instead of vanishing at the cap.
		elif longitudinal > max_speed:
			longitudinal = move_toward(longitudinal, max_speed, 4.0 * dt)
		else:
			longitudinal = minf(max_speed, longitudinal + acceleration * dt)
		if longitudinal >= 0.0 and brake <= 0.01:
			longitudinal = move_toward(longitudinal, 0.0, 1.2 * dt)
		var grip: float = 11.0 * float(stats["handling"])
		if is_drifting:
			grip = 1.5 + float(stats["drift"]) * 0.5
		lateral *= exp(-grip * dt)
		vertical_speed = minf(vertical_speed, 0.0)
	velocity = forward * longitudinal + right * lateral + up_direction * (vertical_speed - GRAVITY * dt)
	move_and_slide()
	grounded = is_on_floor()
	if not grounded:
		is_drifting = false
		drift_charge = 0.0
	speed_mps = velocity.slide(up_direction).length()


func capture_state() -> Dictionary:
	return {
		"version": STATE_VERSION,
		"balance_version": BALANCE_VERSION,
		"transform": global_transform,
		"velocity": velocity,
		"up_direction": up_direction,
		"grounded": grounded,
		"is_drifting": is_drifting,
		"drift_charge": drift_charge,
		"boost_remaining": boost_remaining,
		"drift_was_pressed": _drift_was_pressed,
		"steering_amount": steering_amount,
	}


## Trusted simulation state only; the network boundary must validate payloads.
func restore_state(state: Dictionary) -> void:
	if int(state.get("version", -1)) != STATE_VERSION:
		return
	global_transform = state.get("transform", global_transform)
	velocity = state.get("velocity", Vector3.ZERO)
	up_direction = state.get("up_direction", Vector3.UP)
	grounded = bool(state.get("grounded", false))
	is_drifting = bool(state.get("is_drifting", false))
	drift_charge = clampf(float(state.get("drift_charge", 0.0)), 0.0, 1.0)
	boost_remaining = clampf(float(state.get("boost_remaining", 0.0)), 0.0, 2.0)
	_drift_was_pressed = bool(state.get("drift_was_pressed", false))
	steering_amount = float(state.get("steering_amount", 0.0))
	speed_mps = velocity.slide(up_direction).length()
	reset_physics_interpolation()


func reset_at(location: Transform3D) -> void:
	global_transform = location
	velocity = Vector3.ZERO
	up_direction = location.basis.y.normalized()
	grounded = false
	is_drifting = false
	drift_charge = 0.0
	boost_remaining = 0.0
	speed_mps = 0.0
	steering_amount = 0.0
	_drift_was_pressed = false
	reset_physics_interpolation()


func _axis(input: Dictionary, key: String, minimum: float, maximum: float) -> float:
	var value: float = float(input.get(key, 0.0))
	return clampf(value, minimum, maximum) if is_finite(value) else 0.0
