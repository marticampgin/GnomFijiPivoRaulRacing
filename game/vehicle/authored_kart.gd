extends Node3D

const MODEL_PATH: String = "res://art/vehicles/hero-blockout.glb"
const EXHAUST_SHADER = preload("res://vehicle/crystal_exhaust.gdshader")
const WHEEL_NAMES: Array[String] = ["FrontLeftRoll", "FrontRightRoll", "RearLeftRoll", "RearRightRoll"]
const STEER_NAMES: Array[String] = ["FrontLeftSteer", "FrontRightSteer"]
const WHEEL_RADII: Array[float] = [0.40, 0.40, 0.43, 0.43]
static var _scene: PackedScene

var _model: Node3D
var _wheels: Array[Node3D] = []
var _wheel_rest: Array[Basis] = []
var _wheel_angles: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _steers: Array[Node3D] = []
var _steer_rest: Array[Basis] = []
var _driver: Node3D
var _driver_rest: Transform3D
var _steering: Node3D
var _steering_rest: Basis
var _head: Node3D
var _head_rest: Basis
var _jets: Array[Node3D] = []
var _jet_material: ShaderMaterial
var _reduced_effects: bool = false
var _elapsed: float = 0.0
var _lean: float = 0.0


static func warm() -> void:
	if _scene == null:
		_scene = load(MODEL_PATH) as PackedScene
	assert(_scene != null, "The authored kart GLB must import before the client starts")


static func create(_color: Color) -> Node3D:
	warm()
	var kart := new()
	kart.name = "AuthoredCrystalKart"
	kart._build()
	return kart


func set_reduced_effects(enabled: bool) -> void:
	_reduced_effects = enabled
	if _jet_material != null:
		_jet_material.set_shader_parameter("pulse_strength", 0.0 if enabled else 1.0)
		_jet_material.set_shader_parameter("effect_opacity", 0.5 if enabled else 1.0)


func update_visual(delta: float, speed_mps: float, steering: float, drifting: bool, boost_amount: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	_elapsed += dt
	var turn: float = clampf(steering, -1.0, 1.0)
	for index: int in _wheels.size():
		_wheel_angles[index] = fmod(_wheel_angles[index] - speed_mps * dt / WHEEL_RADII[index], TAU)
		_wheels[index].basis = _wheel_rest[index] * Basis(Vector3.RIGHT, _wheel_angles[index])
	for index: int in _steers.size():
		_steers[index].basis = _steer_rest[index] * Basis(Vector3.UP, -turn * 0.38)
	var moving: float = clampf(absf(speed_mps) / 14.0, 0.0, 1.0)
	_lean = lerpf(_lean, -turn * (0.06 if drifting else 0.025) * moving, 1.0 - exp(-dt * 9.0))
	_driver.transform = _driver_rest
	_driver.basis = _driver_rest.basis * Basis(Vector3.BACK, _lean)
	if not _reduced_effects:
		_driver.position.y += sin(_elapsed * 10.0) * 0.004 * moving
	_head.basis = _head_rest * Basis(Vector3.BACK, -_lean * 0.28)
	_steering.basis = _steering_rest * Basis(Vector3(0.0, 0.48, -0.877).normalized(), turn * 0.3)
	var boost: float = clampf(boost_amount, 0.0, 1.0)
	for jet: Node3D in _jets:
		jet.visible = boost > 0.01
		jet.scale = Vector3(0.75, 0.75, 0.4) if _reduced_effects else Vector3(1.0, 1.0, 0.65 + boost * 0.7)


func _build() -> void:
	_model = _scene.instantiate()
	_model.position.y = -0.35
	add_child(_model)
	for key: String in WHEEL_NAMES:
		var wheel: Node3D = _part(key)
		_wheels.append(wheel)
		_wheel_rest.append(wheel.basis)
	for key: String in STEER_NAMES:
		var steer: Node3D = _part(key)
		_steers.append(steer)
		_steer_rest.append(steer.basis)
	_driver = _part("DriverLean")
	_driver_rest = _driver.transform
	_head = _part("HeadMotion")
	_head_rest = _head.basis
	_steering = _part("SteeringPivot")
	_steering_rest = _steering.basis
	_jet_material = ShaderMaterial.new()
	_jet_material.shader = EXHAUST_SHADER
	_jet_material.set_shader_parameter("jet_color", Color(0.32, 0.88, 1.0, 0.64))
	for key: String in ["ExhaustLeft", "ExhaustRight"]:
		var outlet: Node3D = _part(key)
		var jet := Node3D.new()
		jet.name = "BoostJet"
		outlet.add_child(jet)
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.003
		mesh.bottom_radius = 0.08
		mesh.height = 1.25
		mesh.radial_segments = 16
		mesh.rings = 1
		var plume := MeshInstance3D.new()
		plume.mesh = mesh
		plume.material_override = _jet_material
		plume.position.z = mesh.height * 0.5
		plume.rotation.x = PI * 0.5
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		jet.add_child(plume)
		jet.visible = false
		_jets.append(jet)


func _part(key: String) -> Node3D:
	var node := _model.find_child(key, true, false) as Node3D
	assert(node != null, "Authored kart is missing required pivot: " + key)
	return node
