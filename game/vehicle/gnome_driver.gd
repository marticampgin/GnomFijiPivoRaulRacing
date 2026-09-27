extends RefCounted

const Shape = preload("res://vehicle/kart_meshes.gd")


static func create() -> Node3D:
	var driver: Node3D = Node3D.new()
	driver.name = "Driver"
	var skin: StandardMaterial3D = Shape.material(Color("e9ae86"), 0.77)
	var rose: StandardMaterial3D = Shape.material(Color("bd6d62"), 0.8)
	var blue: StandardMaterial3D = Shape.material(Color("326b90"), 0.83)
	var blue_light: StandardMaterial3D = Shape.material(Color("548aaa"), 0.8)
	var leather: StandardMaterial3D = Shape.material(Color("392a25"), 0.75)
	var white: StandardMaterial3D = Shape.material(Color("eee9d9"), 0.88)
	var hair_shadow: StandardMaterial3D = Shape.material(Color("b9b8ad"), 0.88)
	var brass: StandardMaterial3D = Shape.material(Color("c6a15f"), 0.32, 0.65)
	var black: StandardMaterial3D = Shape.material(Color("202321"), 0.45)
	var coat: Node3D = _part(driver, "CoatAndHands")
	Shape.ellipsoid(coat, Vector3(0.0, 0.63, 0.10), Vector3(0.29, 0.33, 0.23), blue)
	Shape.ellipsoid(coat, Vector3(0.0, 0.74, -0.05), Vector3(0.22, 0.21, 0.12), blue_light)
	for side: float in [-1.0, 1.0]:
		Shape.line(coat, PackedVector3Array([Vector3(side * 0.22, 0.8, 0.06), Vector3(side * 0.34, 0.64, -0.15), Vector3(side * 0.18, 0.58, -0.43)]), 0.085, blue, true)
		Shape.ellipsoid(coat, Vector3(side * 0.2, 0.59, -0.41), Vector3(0.087, 0.075, 0.093), leather)
		for finger: int in range(3):
			Shape.ellipsoid(coat, Vector3(side * (0.16 + finger * 0.026), 0.622, -0.46), Vector3(0.017, 0.025, 0.028), leather, 12)
		Shape.line(coat, PackedVector3Array([Vector3(side * 0.18, 0.33, 0.07), Vector3(side * 0.22, 0.26, -0.25)]), 0.09, leather)
		Shape.ellipsoid(coat, Vector3(side * 0.22, 0.22, -0.30), Vector3(0.115, 0.07, 0.19), leather)
		Shape.line(coat, PackedVector3Array([Vector3(side * 0.20, 0.87, 0.02), Vector3(side * 0.15, 0.74, -0.12), Vector3(side * 0.13, 0.5, -0.13)]), 0.023, leather, true)
	Shape.ellipsoid(coat, Vector3(0.0, 0.47, -0.125), Vector3(0.18, 0.035, 0.04), leather)
	Shape.ellipsoid(coat, Vector3(0.0, 0.48, -0.166), Vector3(0.035, 0.027, 0.014), brass, 12)
	Shape.bake(coat)
	var head: Node3D = _part(driver, "Head")
	var face: Node3D = _part(head, "Face")
	Shape.ellipsoid(face, Vector3(0.0, 1.07, 0.015), Vector3(0.255, 0.275, 0.235), skin)
	Shape.ellipsoid(face, Vector3(0.0, 1.065, -0.242), Vector3(0.09, 0.11, 0.125), skin)
	Shape.ellipsoid(face, Vector3(0.0, 1.015, -0.314), Vector3(0.10, 0.067, 0.069), skin)
	for side: float in [-1.0, 1.0]:
		Shape.ellipsoid(face, Vector3(side * 0.175, 1.035, -0.15), Vector3(0.08, 0.063, 0.05), skin)
		_ear(face, side, skin, rose)
		Shape.ellipsoid(face, Vector3(side * 0.10, 1.135, -0.201), Vector3(0.069, 0.047, 0.025), white)
		Shape.ellipsoid(face, Vector3(side * 0.097, 1.131, -0.224), Vector3(0.029, 0.032, 0.012), blue_light, 16)
		Shape.ellipsoid(face, Vector3(side * 0.097, 1.131, -0.235), Vector3(0.013, 0.021, 0.007), black, 12)
		Shape.ellipsoid(face, Vector3(side * 0.092, 1.142, -0.24), Vector3(0.007, 0.008, 0.003), white, 12)
		Shape.line(face, PackedVector3Array([Vector3(side * 0.035, 1.185, -0.223), Vector3(side * 0.11, 1.197, -0.232), Vector3(side * 0.19, 1.17, -0.18)]), 0.027, white, true)
	Shape.line(face, PackedVector3Array([Vector3(-0.066, 0.965, -0.252), Vector3(0.0, 0.95, -0.273), Vector3(0.066, 0.965, -0.252)]), 0.014, rose, true)
	Shape.bake(face)
	_beard(head, white, hair_shadow)
	_hat(head)
	return driver


static func _part(parent: Node3D, title: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = title
	parent.add_child(node)
	return node


static func _ear(parent: Node3D, side: float, skin: Material, rose: Material) -> void:
	var rings: Array[PackedVector3Array] = []
	for depth: float in [0.025, -0.07, -0.095]:
		var scale_factor: float = 1.0 if depth == -0.07 else 0.58
		var center: Vector3 = Vector3(side * 0.29, 1.095, depth)
		var ring: PackedVector3Array = []
		for point: Vector3 in [Vector3(-0.08, 0.08, 0.0), Vector3(0.18, 0.155, 0.0), Vector3(0.10, -0.01, 0.0), Vector3(-0.005, -0.10, 0.0)]:
			ring.append(center + Vector3(side * point.x, point.y, point.z) * scale_factor)
		if side < 0.0:
			ring.reverse()
		rings.append(ring)
	Shape.add(parent, Shape.loft(rings), skin)
	Shape.ellipsoid(parent, Vector3(side * 0.307, 1.101, -0.095), Vector3(0.047, 0.068, 0.018), rose, 16)


static func _beard(parent: Node3D, white: Material, shadow: Material) -> void:
	var beard: Node3D = _part(parent, "Beard")
	var rings: Array[PackedVector3Array] = []
	for row: Vector4 in [Vector4(0.925, -0.125, 0.22, 0.16), Vector4(0.84, -0.19, 0.235, 0.135), Vector4(0.70, -0.245, 0.17, 0.095), Vector4(0.55, -0.255, 0.065, 0.045), Vector4(0.52, -0.26, 0.008, 0.007)]:
		rings.push_front(Shape.horizontal_ring(Vector3(0.0, row.x, row.y), row.z, row.w, 20, 0.075))
	Shape.add(beard, Shape.loft(rings), shadow)
	for strand: int in range(11):
		var x: float = (strand - 5) * 0.038
		var edge: float = absf(x) / 0.2
		var path: PackedVector3Array = Shape.curve(PackedVector3Array([
			Vector3(x, 0.94 - edge * 0.025, -0.225 + edge * 0.09),
			Vector3(x * 1.06, 0.85, -0.33 + edge * 0.025),
			Vector3(x * 0.77, 0.69 + edge * 0.05, -0.35 + edge * 0.07),
			Vector3(x * 0.5 + sin(float(strand)) * 0.012, 0.525 + edge * 0.135, -0.30 + edge * 0.08),
		]), 3)
		var radii: PackedFloat32Array = []
		for step: int in range(path.size()):
			var t: float = float(step) / float(path.size() - 1)
			radii.append(lerpf(0.038, 0.002, t) + sin(t * PI) * 0.007)
		Shape.add(beard, Shape.tube(path, radii, 8), white)
	for side: float in [-1.0, 1.0]:
		var moustache: PackedVector3Array = Shape.curve(PackedVector3Array([Vector3(side * 0.015, 0.997, -0.299), Vector3(side * 0.09, 0.991, -0.30), Vector3(side * 0.19, 0.925, -0.22)]), 4)
		Shape.add(beard, Shape.tube(moustache, PackedFloat32Array([0.033, 0.035, 0.039, 0.035, 0.03, 0.025, 0.019, 0.012, 0.002]), 10), white)
		Shape.ellipsoid(beard, Vector3(side * 0.208, 1.015, 0.045), Vector3(0.053, 0.13, 0.15), white)
	Shape.ellipsoid(beard, Vector3(0.0, 1.08, 0.20), Vector3(0.22, 0.15, 0.06), shadow)
	for strand: int in range(9):
		var x: float = (strand - 4) * 0.049
		Shape.line(beard, PackedVector3Array([Vector3(x, 1.16, 0.20), Vector3(x * 1.04, 1.03, 0.257), Vector3(x * 0.95, 0.92, 0.205)]), 0.026, white, true)
	Shape.bake(beard)


static func _hat(parent: Node3D) -> void:
	var hat: Node3D = _part(parent, "Hat")
	var red: StandardMaterial3D = Shape.material(Color("b83032"), 0.87)
	var dark_red: StandardMaterial3D = Shape.material(Color("8c262c"), 0.9)
	var highlight: StandardMaterial3D = Shape.material(Color("cf4542"), 0.87)
	var rings: Array[PackedVector3Array] = []
	var centers: Array[Vector3] = [Vector3(0.0, 1.24, 0.018), Vector3(0.0, 1.30, 0.018), Vector3(-0.025, 1.43, 0.045), Vector3(-0.045, 1.55, 0.095), Vector3(-0.02, 1.65, 0.155), Vector3(0.07, 1.70, 0.2), Vector3(0.17, 1.67, 0.20), Vector3(0.23, 1.61, 0.18), Vector3(0.28, 1.62, 0.16)]
	var widths: Array[float] = [0.278, 0.292, 0.235, 0.175, 0.12, 0.082, 0.054, 0.032, 0.002]
	for i: int in range(centers.size()):
		var tangent: Vector3 = (centers[mini(i + 1, centers.size() - 1)] - centers[maxi(i - 1, 0)]).normalized()
		var u: Vector3 = tangent.cross(Vector3.BACK).normalized()
		var v: Vector3 = u.cross(tangent).normalized()
		var ring: PackedVector3Array = []
		for segment: int in range(28):
			var theta: float = -TAU * float(segment) / 28.0
			var fold: float = 1.0 + sin(theta * 5.0 + float(i) * 0.65) * 0.045
			ring.append(centers[i] + (u * cos(theta) + v * sin(theta) * 0.84) * widths[i] * fold)
		rings.append(ring)
	Shape.add(hat, Shape.loft(rings), red)
	var brim: PackedVector3Array = Shape.horizontal_ring(Vector3(0.0, 1.273, 0.018), 0.286, 0.249, 40)
	brim.append(brim[0])
	Shape.line(hat, brim, 0.03, dark_red)
	for fold: int in range(5):
		var points: PackedVector3Array = []
		for step: int in range(5):
			var index: int = step + 1
			var segment: int = (fold * 5 + step) % 28
			points.append(centers[index] + (rings[index][segment] - centers[index]) * 1.005)
		Shape.line(hat, points, 0.006, highlight, true)
	Shape.bake(hat)
