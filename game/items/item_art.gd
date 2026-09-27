extends RefCounted
## Original low-poly prototype props. All dimensions are in metres.

static func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.roughness = 0.55
	if glow > 0.0:
		value.emission_enabled = true
		value.emission = color
		value.emission_energy_multiplier = glow
	return value

static func part(root: Node3D, mesh: Mesh, position: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color, glow)
	node.position = position
	root.add_child(node)
	return node

static func box(root: Node3D, size: Vector3, position: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return part(root, mesh, position, color, glow)

static func cylinder(root: Node3D, bottom: float, top: float, height: float, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 10
	return part(root, mesh, position, color)

static func crystal(root: Node3D, position: Vector3, color: Color, size: float = 0.3) -> void:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(size, size * 1.9, size)
	var node := part(root, mesh, position, color, 0.35)
	node.rotation.z = 0.2

static func create_item(id: String) -> Node3D:
	if id == "engine_shard":
		return create_shard()
	if id == "crystal_shield":
		return create_shield()
	if id == "seeker":
		return create_seeker()
	if id == "rear_trap":
		return create_trap()
	var root := Node3D.new()
	root.name = id
	var dark := Color("193737")
	var gold := Color("e6bb64")
	if id == "bfg10k":
		box(root, Vector3(0.65, 0.38, 0.95), Vector3(0, 0.12, 0), dark)
		box(root, Vector3(0.24, 0.32, 0.28), Vector3(0, -0.2, 0.2), Color("37484a")).rotation.x = -0.2
		for x in [-0.24, 0.24]:
			box(root, Vector3(0.16, 0.3, 0.85), Vector3(x, 0.2, -0.2), Color("8ad648"))
			box(root, Vector3(0.10, 0.17, 0.08), Vector3(x, 0.2, -0.67), Color("d3ff71"), 0.8)
		crystal(root, Vector3(0, 0.45, 0.1), Color("a2f65b"), 0.25)
		box(root, Vector3(0.38, 0.08, 0.18), Vector3(0, 0.35, 0.32), gold)
	elif id == "lays_crab":
		box(root, Vector3(0.75, 0.95, 0.26), Vector3.ZERO, Color("c93d4a")).rotation.z = -0.08
		for y in [-0.48, 0.48]:
			box(root, Vector3(0.82, 0.09, 0.32), Vector3(0, y, 0), gold)
		box(root, Vector3(0.56, 0.5, 0.02), Vector3(0, 0, -0.16), Color("ffe2a0"))
		cylinder(root, 0.14, 0.14, 0.035, Vector3(0, 0, -0.19), Color("b92b39")).rotation.x = PI / 2.0
		for side in [-1.0, 1.0]:
			for y in [-0.1, 0.02, 0.12]:
				box(root, Vector3(0.15, 0.035, 0.03), Vector3(side * 0.17, y, -0.19), Color("b92b39")).rotation.z = side * 0.45
	else:
		var colors := {"fanta": Color("ff8d28"), "mermaid_rum": Color("29bbaa"), "ice_rum": Color("a0eafa"), "stroh80": Color("a3532d")}
		var color: Color = colors.get(id, Color("a0eafa"))
		cylinder(root, 0.27, 0.27, 0.65, Vector3(0, -0.1, 0), color)
		cylinder(root, 0.27, 0.12, 0.19, Vector3(0, 0.32, 0), color.lightened(0.1))
		cylinder(root, 0.11, 0.11, 0.22, Vector3(0, 0.51, 0), color)
		cylinder(root, 0.13, 0.13, 0.12, Vector3(0, 0.65, 0), gold if id != "fanta" else Color("448f44"))
		cylinder(root, 0.279, 0.279, 0.29, Vector3(0, -0.08, 0), Color("fff1c7") if id != "ice_rum" else dark)
		if id == "fanta":
			cylinder(root, 0.11, 0.11, 0.025, Vector3(0, -0.06, -0.281), color).rotation.x = PI / 2.0
			box(root, Vector3(0.1, 0.055, 0.025), Vector3(0.08, 0.07, -0.28), Color("448f44")).rotation.z = -0.5
		elif id == "ice_rum":
			crystal(root, Vector3(0, -0.06, -0.29), color, 0.16)
		elif id == "mermaid_rum":
			for side in [-1, 1]:
				box(root, Vector3(0.09, 0.22, 0.025), Vector3(side * 0.045, -0.03, -0.28), color).rotation.z = side * 0.5
		else:
			box(root, Vector3(0.16, 0.16, 0.035), Vector3(0, -0.07, -0.28), Color("d64332")).rotation.z = PI / 4.0
			box(root, Vector3(0.2, 0.1, 0.12), Vector3(0.08, 0.74, 0), dark).rotation.z = -0.4
	return root


static func create_shield() -> Node3D:
	var root := Node3D.new()
	root.name = "crystal_shield"
	var rim := cylinder(root, 0.66, 0.66, 0.13, Vector3.ZERO, Color("e6bb64"))
	(rim.mesh as CylinderMesh).radial_segments = 6
	rim.rotation.x = PI / 2.0
	var face := cylinder(root, 0.54, 0.54, 0.16, Vector3(0, 0, -0.05), Color("176e89"))
	(face.mesh as CylinderMesh).radial_segments = 6
	face.rotation.x = PI / 2.0
	crystal(root, Vector3(0, 0, -0.22), Color("83ffff"), 0.35)
	for side in [-1.0, 1.0]:
		box(root, Vector3(0.10, 0.35, 0.08), Vector3(side * 0.31, 0, -0.18), Color("72ece6"), 0.3).rotation.z = side * 0.35
	return root

static func create_seeker() -> Node3D:
	var root := Node3D.new()
	root.name = "seeker"
	cylinder(root, 0.18, 0.18, 0.7, Vector3.ZERO, Color("944269")).rotation.x = PI / 2.0
	cylinder(root, 0.19, 0, 0.43, Vector3(0, 0, -0.54), Color("ff768b")).rotation.x = -PI / 2.0
	cylinder(root, 0.23, 0.23, 0.12, Vector3(0, 0, 0.28), Color("e6bb64")).rotation.x = PI / 2.0
	for side in [-1.0, 1.0]:
		var fin := PrismMesh.new()
		fin.size = Vector3(0.4, 0.13, 0.43)
		part(root, fin, Vector3(side * 0.25, 0, 0.18), Color("e6bb64"))
	box(root, Vector3(0.1, 0.36, 0.28), Vector3(0, 0.16, 0.2), Color("d99c58"))
	crystal(root, Vector3(0, 0.23, -0.13), Color("ffb2c1"), 0.14)
	cylinder(root, 0.09, 0, 0.32, Vector3(0, 0, 0.47), Color("6af6e8")).rotation.x = PI / 2.0
	return root

static func create_trap() -> Node3D:
	var root := Node3D.new()
	root.name = "rear_trap"
	cylinder(root, 0.55, 0.46, 0.17, Vector3(0, 0.09, 0), Color("493b57"))
	cylinder(root, 0.40, 0.34, 0.1, Vector3(0, 0.22, 0), Color("e6bb64"))
	crystal(root, Vector3(0, 0.39, 0), Color("ff6982"), 0.32)
	for index in range(6):
		var angle := TAU * index / 6.0
		var spike := cylinder(root, 0.14, 0, 0.43, Vector3(sin(angle) * 0.40, 0.32, cos(angle) * 0.40), Color("edbd73"))
		spike.rotation = Vector3(cos(angle) * 0.45, 0, -sin(angle) * 0.45)
	return root

static func create_shield_aura() -> Node3D:
	var root := Node3D.new()
	root.name = "CrystalShieldAura"
	var dome := SphereMesh.new()
	dome.radius = 1.6
	dome.height = 3.2
	dome.radial_segments = 12
	dome.rings = 6
	var shell := part(root, dome, Vector3(0, 0.65, 0), Color(0.25, 0.9, 0.94, 0.10), 0.15)
	shell.scale = Vector3(1, 0.75, 1.2)
	var skin := shell.material_override as StandardMaterial3D
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for height in [0.05, 1.2]:
		var ring := TorusMesh.new()
		ring.inner_radius = 1.42
		ring.outer_radius = 1.46
		ring.rings = 12
		ring.ring_segments = 6
		var band := part(root, ring, Vector3(0, height, 0), Color("72ece6"), 0.35)
		band.scale.z = 1.2
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

static func create_shard() -> Node3D:
	var root := Node3D.new()
	root.name = "TurquoiseEngineShard"
	var upper := CylinderMesh.new()
	upper.bottom_radius = 0.25
	upper.top_radius = 0.0
	upper.height = 0.6
	upper.radial_segments = 5
	part(root, upper, Vector3(0, 0.15, 0), Color("56e8dc"), 0.45)
	var lower := CylinderMesh.new()
	lower.bottom_radius = 0.0
	lower.top_radius = 0.25
	lower.height = 0.3
	lower.radial_segments = 5
	part(root, lower, Vector3(0, -0.3, 0), Color("168e99"), 0.25)
	return root

static func create_projectile(id: String) -> Node3D:
	if id != "bfg10k":
		return create_item(id)
	var root := Node3D.new()
	root.name = "bfg_energy_bolt"
	var core := SphereMesh.new()
	core.radius = 0.24
	core.height = 0.48
	core.radial_segments = 10
	core.rings = 5
	part(root, core, Vector3.ZERO, Color("d7ff8b"), 0.9)
	for side in [-1, 1]:
		var shard := PrismMesh.new()
		shard.size = Vector3(0.16, 0.55, 0.16)
		var node := part(root, shard, Vector3(side * 0.22, 0, 0), Color("74df52"), 0.5)
		node.rotation.z = side * 0.55
	return root

static func create_pickup() -> Node3D:
	var root := Node3D.new()
	box(root, Vector3(0.9, 0.9, 0.9), Vector3.ZERO, Color("2b777b"))
	for axis in [0, 1, 2]:
		var size := Vector3(1.0, 1.0, 1.0)
		size[axis] = 0.15
		box(root, size, Vector3.ZERO, Color("f0c878"))
	crystal(root, Vector3(0, 0.63, 0), Color("aff3cf"), 0.25)
	return root

static func create_explosion(kind: String) -> Node3D:
	var root := Node3D.new()
	var color := Color("a9ef63") if kind.contains("bfg") else Color("ffac48")
	if kind.contains("seeker") or kind.contains("rear_trap"):
		color = Color("ff7895")
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	part(root, mesh, Vector3.ZERO, color, 0.5)
	return root
