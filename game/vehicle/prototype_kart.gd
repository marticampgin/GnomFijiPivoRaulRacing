class_name PrototypeKart
extends Node3D

const Shape = preload("res://vehicle/kart_meshes.gd")
const Gnome = preload("res://vehicle/gnome_driver.gd")
const ExhaustShader = preload("res://vehicle/crystal_exhaust.gdshader")

var _wheels: Array[Node3D] = []
var _front_pivots: Array[Node3D] = []
var _driver: Node3D
var _crystal: Node3D
var _trails: Node3D
var _wheel_angle: float = 0.0
var _elapsed: float = 0.0
var _reduced_effects: bool = false


func set_reduced_effects(enabled: bool) -> void:
	_reduced_effects = enabled


static func create(color: Color) -> Node3D:
	var kart: PrototypeKart = PrototypeKart.new()
	kart.name = "CrystalKart"
	kart._build(color)
	return kart


func update_visual(delta: float, speed_mps: float, steering: float, drifting: bool, boost_amount: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.1)
	_elapsed += dt
	_wheel_angle = fmod(_wheel_angle - speed_mps * dt / 0.395, TAU)
	for wheel: Node3D in _wheels:
		wheel.rotation.x = _wheel_angle
	for pivot: Node3D in _front_pivots:
		pivot.rotation.y = -clampf(steering, -1.0, 1.0) * 0.4
	var lean: float = -steering * (0.055 if drifting else 0.022) * clampf(speed_mps / 12.0, 0.0, 1.0)
	_driver.rotation.z = lerpf(_driver.rotation.z, lean, 1.0 - exp(-dt * 9.0))
	_driver.position.y = 0.0 if _reduced_effects else sin(_elapsed * 12.0) * 0.007 * clampf(speed_mps / 18.0, 0.0, 1.0)
	_crystal.position.y = 0.0 if _reduced_effects else sin(_elapsed * 2.5) * 0.009
	_trails.visible = boost_amount > 0.01
	_trails.scale = Vector3(1.0, 1.0, 0.4) if _reduced_effects else Vector3(1.0, 1.0, 0.65 + clampf(boost_amount, 0.0, 1.0) * 0.7 + sin(_elapsed * 32.0) * 0.06)


func _build(color: Color) -> void:
	var enamel_color: Color = color.darkened(0.25)
	var enamel: StandardMaterial3D = Shape.material(enamel_color, 0.52, 0.24)
	var enamel_edge: StandardMaterial3D = Shape.material(enamel_color.lightened(0.12), 0.52, 0.22)
	var brass: StandardMaterial3D = Shape.material(Color("b58b47"), 0.34, 0.72)
	var brass_light: StandardMaterial3D = Shape.material(Color("ddbd78"), 0.3, 0.70)
	var steel: StandardMaterial3D = Shape.material(Color("60736f"), 0.36, 0.78)
	var frame: StandardMaterial3D = Shape.material(Color("293330"), 0.5, 0.48)
	var rubber: StandardMaterial3D = Shape.material(Color("262a29"), 0.9)
	var tread: StandardMaterial3D = Shape.material(Color("373c38"), 0.88)
	var leather: StandardMaterial3D = Shape.material(Color("6b4331"), 0.83)
	var light: StandardMaterial3D = Shape.material(Color("ffe1a0"), 0.28, 0.15, 0.65)
	var cyan: StandardMaterial3D = Shape.material(Color("46e3ef"), 0.2, 0.18, 0.75)
	var body: Node3D = _part("Chassis")
	_hull(body, enamel, enamel_edge, brass, frame)
	for side: float in [-1.0, 1.0]:
		for axle: float in [-0.74, 0.74]:
			_fender(body, Vector3(side * 0.78, 0.045, axle), enamel, brass)
			_suspension(body, side, axle, brass, steel, frame)
		Shape.line(body, PackedVector3Array([Vector3(side * 0.4, 0.10, -0.7), Vector3(side * 0.5, 0.09, -0.18), Vector3(side * 0.47, 0.18, 0.69)]), 0.05, frame, true)
		Shape.line(body, PackedVector3Array([Vector3(side * 0.4, 0.16, -0.2), Vector3(side * 0.45, 0.44, 0.26), Vector3(side * 0.4, 0.85, 0.43)]), 0.044, frame, true)
		Shape.cylinder(body, Vector3(side * 0.49, 0.35, -1.04), 0.146, 0.13, brass, Vector3(PI * 0.5, 0.0, 0.0))
		Shape.cylinder(body, Vector3(side * 0.49, 0.35, -1.12), 0.119, 0.018, light, Vector3(PI * 0.5, 0.0, 0.0))
		Shape.line(body, Shape.circle(Vector3(side * 0.49, 0.35, -1.137), Vector3.RIGHT, Vector3.UP, 0.126), 0.012, brass_light)
		for rib: int in range(-2, 3):
			Shape.line(body, PackedVector3Array([Vector3(side * 0.49 + rib * 0.034, 0.27, -1.142), Vector3(side * 0.49 + rib * 0.034, 0.43, -1.142)]), 0.004, brass)
		Shape.line(body, PackedVector3Array([Vector3(side * 0.56, -0.02, -1.19), Vector3(side * 0.43, -0.065, -1.3), Vector3(side * 0.04, -0.065, -1.31)]), 0.051, steel, true)
		Shape.cylinder(body, Vector3(side * 0.49, 0.24, 0.58), 0.08, 0.36, steel, Vector3(PI * 0.5, 0.0, 0.0))
		Shape.line(body, Shape.circle(Vector3(side * 0.49, 0.24, 0.45), Vector3.RIGHT, Vector3.UP, 0.082), 0.013, brass)
	Shape.line(body, PackedVector3Array([Vector3(-0.4, 0.84, 0.43), Vector3(-0.28, 0.94, 0.45), Vector3(0.28, 0.94, 0.45), Vector3(0.4, 0.84, 0.43)]), 0.045, frame, true)
	Shape.ellipsoid(body, Vector3(0.0, 0.34, 0.15), Vector3(0.33, 0.11, 0.29), leather)
	Shape.ellipsoid(body, Vector3(0.0, 0.60, 0.35), Vector3(0.32, 0.35, 0.10), leather)
	for x: float in [-0.22, -0.11, 0.0, 0.11, 0.22]:
		Shape.line(body, PackedVector3Array([Vector3(x, 0.42, 0.262), Vector3(x, 0.66, 0.255), Vector3(x * 0.9, 0.82, 0.27)]), 0.007, brass, true)
	_steering_wheel(body, frame, brass)
	Shape.bake(body)
	for side: float in [-1.0, 1.0]:
		for front: bool in [true, false]:
			_wheel(side, front, rubber, tread, brass, brass_light, steel, frame)
	_driver = Gnome.create()
	add_child(_driver)
	_engine(brass, brass_light, frame, cyan)
	_exhaust(brass, steel, frame, cyan)


func _part(title: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = title
	add_child(node)
	return node


func _hull(parent: Node3D, enamel: Material, edge: Material, brass: Material, frame: Material) -> void:
	var base_rings: Array[PackedVector3Array] = []
	for row: Vector4 in [Vector4(-1.1, 0.0, 0.29, 0.075), Vector4(-0.91, -0.03, 0.48, 0.12), Vector4(-0.45, -0.04, 0.55, 0.13), Vector4(0.4, -0.04, 0.53, 0.13), Vector4(0.89, -0.015, 0.48, 0.15), Vector4(1.02, 0.02, 0.33, 0.105)]:
		base_rings.append(_body_ring(row))
	Shape.add(parent, Shape.loft(base_rings), enamel)
	var hood_rings: Array[PackedVector3Array] = []
	for row: Vector4 in [Vector4(-1.115, 0.15, 0.24, 0.115), Vector4(-0.98, 0.16, 0.37, 0.19), Vector4(-0.77, 0.15, 0.46, 0.235), Vector4(-0.48, 0.13, 0.46, 0.24), Vector4(-0.30, 0.115, 0.43, 0.175)]:
		hood_rings.append(_body_ring(row))
	Shape.add(parent, Shape.loft(hood_rings), enamel)
	Shape.ellipsoid(parent, Vector3(0.0, 0.09, -1.135), Vector3(0.235, 0.16, 0.025), frame)
	for slat: int in range(-3, 4):
		Shape.line(parent, PackedVector3Array([Vector3(slat * 0.056, -0.015, -1.158), Vector3(slat * 0.052, 0.205, -1.15)]), 0.012, brass)
	for side: float in [-1.0, 1.0]:
		Shape.line(parent, PackedVector3Array([Vector3(side * 0.22, 0.275, -1.04), Vector3(side * 0.33, 0.36, -0.76), Vector3(side * 0.35, 0.337, -0.43)]), 0.01, edge, true)
		for rivet: int in range(4):
			Shape.ellipsoid(parent, Vector3(side * 0.34, 0.33, -0.84 + float(rivet) * 0.12), Vector3(0.013, 0.012, 0.013), brass, 12)
	for vent: int in range(3):
		Shape.line(parent, PackedVector3Array([Vector3(-0.12, 0.389, -0.73 + vent * 0.065), Vector3(0.12, 0.389, -0.73 + vent * 0.065)]), 0.012, frame)
	Shape.ellipsoid(parent, Vector3(0.0, 0.283, -1.04), Vector3(0.057, 0.049, 0.018), brass)


func _body_ring(row: Vector4) -> PackedVector3Array:
	var ring: PackedVector3Array = []
	for i: int in range(24):
		var angle: float = TAU * float(i) / 24.0
		ring.append(Vector3(cos(angle) * row.z, row.y + sin(angle) * row.w, row.x))
	return ring


func _fender(parent: Node3D, center: Vector3, enamel: Material, trim: Material) -> void:
	var rings: Array[PackedVector3Array] = []
	var outer: PackedVector3Array = []
	var inner: PackedVector3Array = []
	for i: int in range(19):
		var theta: float = lerpf(0.68, PI - 0.68, float(i) / 18.0)
		var radial: Vector3 = Vector3(0.0, sin(theta), cos(theta))
		rings.append(PackedVector3Array([center + Vector3(-0.185, 0.0, 0.0) + radial * 0.465, center + Vector3(0.185, 0.0, 0.0) + radial * 0.465, center + Vector3(0.185, 0.0, 0.0) + radial * 0.440, center + Vector3(-0.185, 0.0, 0.0) + radial * 0.440]))
		outer.append(center + Vector3(signf(center.x) * 0.187, 0.0, 0.0) + radial * 0.461)
		inner.append(center + Vector3(-signf(center.x) * 0.16, 0.0, 0.0) + radial * 0.467)
	Shape.add(parent, Shape.loft(rings), enamel)
	Shape.line(parent, outer, 0.012, trim)
	Shape.line(parent, inner, 0.006, trim)
	for theta: float in [0.85, 1.6, 2.3]:
		Shape.ellipsoid(parent, center + Vector3(signf(center.x) * 0.14, sin(theta) * 0.473, cos(theta) * 0.473), Vector3(0.014, 0.011, 0.014), trim, 12)


func _suspension(parent: Node3D, side: float, axle: float, brass: Material, steel: Material, frame: Material) -> void:
	Shape.line(parent, PackedVector3Array([Vector3(side * 0.28, -0.04, axle - 0.13), Vector3(side * 0.78, 0.02, axle), Vector3(side * 0.31, -0.04, axle + 0.13)]), 0.023, brass)
	var bottom: Vector3 = Vector3(side * 0.72, 0.035, axle)
	var top: Vector3 = Vector3(side * 0.44, 0.39, axle + 0.01)
	Shape.line(parent, PackedVector3Array([bottom, top]), 0.027, steel)
	Shape.line(parent, PackedVector3Array([bottom.lerp(top, 0.1), bottom.lerp(top, 0.7)]), 0.047, frame)
	var tangent: Vector3 = (top - bottom).normalized()
	var u: Vector3 = tangent.cross(Vector3.FORWARD).normalized()
	var v: Vector3 = tangent.cross(u)
	var coil: PackedVector3Array = []
	for i: int in range(65):
		var t: float = float(i) / 64.0
		coil.append(bottom.lerp(top, 0.18 + t * 0.69) + (u * cos(t * TAU * 7.0) + v * sin(t * TAU * 7.0)) * 0.054)
	Shape.line(parent, coil, 0.012, brass)


func _wheel(side: float, front: bool, rubber: Material, tread: Material, brass: Material, bright: Material, steel: Material, frame: Material) -> void:
	var pivot: Node3D = _part("Wheel%s%s" % ["Front" if front else "Rear", "Left" if side < 0.0 else "Right"])
	pivot.position = Vector3(side * 0.8, 0.045, -0.74 if front else 0.74)
	if front:
		_front_pivots.append(pivot)
	var wheel: Node3D = Node3D.new()
	wheel.name = "TireAssembly"
	pivot.add_child(wheel)
	_wheels.append(wheel)
	var rings: Array[PackedVector3Array] = []
	for row: Vector2 in [Vector2(-0.175, 0.205), Vector2(-0.2, 0.26), Vector2(-0.18, 0.335), Vector2(-0.12, 0.377), Vector2(0.12, 0.377), Vector2(0.18, 0.335), Vector2(0.20, 0.26), Vector2(0.175, 0.205)]:
		var ring: PackedVector3Array = []
		for i: int in range(32):
			var angle: float = TAU * float(i) / 32.0
			ring.append(Vector3(row.x, cos(angle) * row.y, sin(angle) * row.y))
		rings.append(ring)
	Shape.add(wheel, Shape.loft(rings, true, false), rubber)
	for row: int in range(3):
		for i: int in range(22):
			var theta: float = TAU * (float(i) + float(row % 2) * 0.5) / 22.0
			Shape.box(wheel, Vector3((row - 1) * 0.115, cos(theta) * 0.378, sin(theta) * 0.378), Vector3(0.096, 0.033, 0.075), tread, Vector3(theta, 0.0, 0.1 * (row - 1)))
	Shape.cylinder(wheel, Vector3(side * 0.183, 0.0, 0.0), 0.223, 0.04, brass, Vector3(0.0, 0.0, PI * 0.5))
	Shape.cylinder(wheel, Vector3(side * 0.21, 0.0, 0.0), 0.178, 0.016, frame, Vector3(0.0, 0.0, PI * 0.5))
	Shape.line(wheel, Shape.circle(Vector3(side * 0.223, 0.0, 0.0), Vector3.UP, Vector3.BACK, 0.192), 0.017, bright)
	for i: int in range(8):
		var angle: float = TAU * float(i) / 8.0
		Shape.line(wheel, PackedVector3Array([Vector3(side * 0.23, cos(angle) * 0.07, sin(angle) * 0.07), Vector3(side * 0.222, cos(angle + 0.14) * 0.176, sin(angle + 0.14) * 0.176)]), 0.022, brass)
		Shape.ellipsoid(wheel, Vector3(side * 0.24, cos(angle) * 0.112, sin(angle) * 0.112), Vector3(0.017, 0.012, 0.012), steel, 12)
	Shape.cylinder(wheel, Vector3(side * 0.239, 0.0, 0.0), 0.071, 0.044, bright, Vector3(0.0, 0.0, PI * 0.5))
	Shape.bake(wheel)


func _steering_wheel(parent: Node3D, frame: Material, brass: Material) -> void:
	var center: Vector3 = Vector3(0.0, 0.57, -0.43)
	var vertical: Vector3 = Vector3(0.0, 0.78, 0.63)
	Shape.line(parent, Shape.circle(center, Vector3.RIGHT, vertical, 0.205), 0.026, frame)
	for angle: float in [PI * 0.5, PI * 1.17, PI * 1.83]:
		Shape.line(parent, PackedVector3Array([center, center + (Vector3.RIGHT * cos(angle) + vertical * sin(angle)) * 0.19]), 0.012, brass)
	Shape.line(parent, PackedVector3Array([Vector3(0.0, 0.2, -0.58), center]), 0.026, frame)
	Shape.ellipsoid(parent, center, Vector3(0.04, 0.035, 0.035), brass)


func _engine(brass: Material, bright: Material, frame: Material, cyan: Material) -> void:
	var engine: Node3D = _part("CrystalEngine")
	engine.position.z = 0.71
	var cage: Node3D = Node3D.new()
	cage.name = "Cage"
	engine.add_child(cage)
	Shape.cylinder(cage, Vector3(0.0, 0.30, 0.0), 0.28, 0.18, frame)
	for height: float in [0.37, 0.66, 1.02]:
		Shape.line(cage, Shape.circle(Vector3(0.0, height, 0.0), Vector3.RIGHT, Vector3.BACK, 0.245), 0.031, brass)
	for angle: float in [0.3, PI - 0.3, PI + 0.3, TAU - 0.3]:
		var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		Shape.line(cage, PackedVector3Array([offset * 0.26 + Vector3(0.0, 0.31, 0.0), offset * 0.28 + Vector3(0.0, 0.65, 0.0), offset * 0.245 + Vector3(0.0, 1.02, 0.0)]), 0.028, bright, true)
		for height: float in [0.39, 1.02]:
			Shape.ellipsoid(cage, offset * 0.26 + Vector3(0.0, height, 0.0), Vector3(0.045, 0.045, 0.045), frame, 12)
	Shape.bake(cage)
	var rings: Array[PackedVector3Array] = []
	for row: Vector3 in [Vector3(0.0, 0.36, 0.022), Vector3(-0.014, 0.49, 0.19), Vector3(0.02, 0.99, 0.198), Vector3(0.05, 1.31, 0.009)]:
		rings.append(Shape.horizontal_ring(Vector3(row.x, row.y, 0.0), row.z, row.z * 0.91, 7))
	_crystal = Shape.add(engine, Shape.loft(rings, false), cyan)
	_crystal.name = "Crystal"
	var edge_material: StandardMaterial3D = Shape.material(Color("b5fff8"), 0.22, 0.05, 0.8)
	for edge: int in [0, 2, 4, 6]:
		Shape.line(cage, PackedVector3Array([rings[0][edge], rings[1][edge], rings[2][edge], rings[3][edge]]), 0.009, edge_material)
	Shape.bake(cage)


func _exhaust(brass: Material, steel: Material, frame: Material, cyan: Material) -> void:
	var pipes: Node3D = _part("ExhaustPair")
	_trails = _part("BoostTrails")
	_trails.position.z = 1.27
	var outer: ShaderMaterial = ShaderMaterial.new()
	outer.shader = ExhaustShader
	outer.set_shader_parameter("jet_color", Color(0.50, 0.35, 1.0, 0.65))
	var inner: ShaderMaterial = ShaderMaterial.new()
	inner.shader = ExhaustShader
	inner.set_shader_parameter("jet_color", Color(0.30, 0.92, 1.0, 0.9))
	for side: float in [-1.0, 1.0]:
		Shape.line(pipes, PackedVector3Array([Vector3(side * 0.28, 0.22, 0.58), Vector3(side * 0.46, 0.23, 0.82), Vector3(side * 0.47, 0.21, 1.10)]), 0.118, steel, true)
		Shape.cylinder(pipes, Vector3(side * 0.47, 0.21, 1.06), 0.154, 0.21, brass, Vector3(PI * 0.5, 0.0, 0.0))
		Shape.cylinder(pipes, Vector3(side * 0.47, 0.21, 1.19), 0.13, 0.065, frame, Vector3(PI * 0.5, 0.0, 0.0))
		Shape.cylinder(pipes, Vector3(side * 0.47, 0.21, 1.224), 0.083, 0.008, cyan, Vector3(PI * 0.5, 0.0, 0.0))
		Shape.line(pipes, Shape.circle(Vector3(side * 0.47, 0.21, 1.226), Vector3.RIGHT, Vector3.UP, 0.133), 0.02, brass)
		var outer_jet: MeshInstance3D = Shape.cylinder(_trails, Vector3(side * 0.47, 0.21, 0.9), 0.115, 1.8, outer, Vector3(PI * 0.5, 0.0, 0.0), 0.002)
		var inner_jet: MeshInstance3D = Shape.cylinder(_trails, Vector3(side * 0.47, 0.21, 0.65), 0.065, 1.3, inner, Vector3(PI * 0.5, 0.0, 0.0), 0.002)
		outer_jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inner_jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Shape.bake(pipes)
	_trails.visible = false
