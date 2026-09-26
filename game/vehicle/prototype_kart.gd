class_name PrototypeKart
extends Node3D


static func create(color: Color) -> Node3D:
	var kart: Node3D = Node3D.new()
	var body: StandardMaterial3D = _material(color)
	var dark: StandardMaterial3D = _material(Color("20312f"))
	var accent: StandardMaterial3D = _material(Color("e5ff58"))
	var glass: StandardMaterial3D = _material(Color("a0e8e7"))
	_add_box(kart, Vector3(1.25, 0.34, 1.85), Vector3(0.0, 0.06, 0.0), body)
	_add_box(kart, Vector3(1.05, 0.24, 0.58), Vector3(0.0, 0.12, -0.9), body)
	_add_box(kart, Vector3(0.82, 0.24, 0.65), Vector3(0.0, 0.34, 0.16), dark)
	_add_box(kart, Vector3(0.68, 0.3, 0.38), Vector3(0.0, 0.59, 0.05), glass)
	_add_box(kart, Vector3(1.4, 0.11, 0.28), Vector3(0.0, 0.5, 0.95), accent)
	_add_box(kart, Vector3(0.2, 0.38, 0.14), Vector3(-0.42, 0.3, 0.92), dark)
	_add_box(kart, Vector3(0.2, 0.38, 0.14), Vector3(0.42, 0.3, 0.92), dark)
	_add_box(kart, Vector3(0.17, 0.015, 0.95), Vector3(0.0, 0.26, -0.57), accent)
	for side: float in [-1.0, 1.0]:
		_add_box(kart, Vector3(0.27, 0.13, 0.07), Vector3(side * 0.4, 0.2, -1.21), accent)
		_add_box(kart, Vector3(0.29, 0.12, 0.07), Vector3(side * 0.4, 0.17, 0.96), _material(Color("fc806c")))
		for axle: float in [-0.73, 0.68]:
			var tire: MeshInstance3D = MeshInstance3D.new()
			var mesh: CylinderMesh = CylinderMesh.new()
			mesh.top_radius = 0.32
			mesh.bottom_radius = 0.32
			mesh.height = 0.29
			mesh.radial_segments = 12
			tire.mesh = mesh
			tire.material_override = dark
			tire.rotation.z = PI * 0.5
			tire.position = Vector3(side * 0.7, -0.08, axle)
			kart.add_child(tire)
	return kart


static func _add_box(parent: Node3D, size: Vector3, location: Vector3, material: StandardMaterial3D) -> void:
	var visual: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = location
	visual.material_override = material
	parent.add_child(visual)


static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	return material
