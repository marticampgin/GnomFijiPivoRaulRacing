extends Node3D

const ROAD_STEPS: int = 160
const CASTLE: Vector3 = Vector3(45.0, 20.0, 215.0)
var _batches: Dictionary = {}
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _radius_x: float
var _radius_z: float
var _placement_transform: Transform3D = Transform3D.IDENTITY


func build(radius_x: float, radius_z: float, width: float) -> void:
	_radius_x = radius_x
	_radius_z = radius_z
	_materials_init()
	_road(width)
	_island("MainIsland", Vector3(0.0, -0.18, 0.0), Vector2(80.0, 61.0), -23.0, 64, 0.2)
	_island("CastleIsland", CASTLE, Vector2(54.0, 42.0), -24.0, 64, 1.4)
	_island("WestCliffs", Vector3(-112.0, 10.0, 75.0), Vector2(32.0, 40.0), -24.0, 36, 2.8)
	_island("EastCliffs", Vector3(134.0, 7.0, 62.0), Vector2(28.0, 44.0), -24.0, 36, 4.3)
	_lake()
	_castle()
	_viaduct()
	_forest()
	_waterfall(CASTLE + Vector3(-33.0, -0.1, -33.0), 10.0, 39.4, 0.3)
	_waterfall(CASTLE + Vector3(36.0, -0.1, -30.0), 12.0, 39.4, 1.7)
	_waterfall(Vector3(-94.0, 9.9, 43.0), 8.0, 29.0, 3.2)
	_mountains()
	_start_gate()
	_flush_batches()


func _materials_init() -> void:
	_materials["stone"] = _material(Color("e2e2d6"))
	_materials["cap"] = _material(Color("eeeee2"))
	_materials["road"] = _material(Color("bfc3bf"))
	if ResourceLoader.exists("res://art/stone-road.png"):
		var tile: Texture2D = load("res://art/stone-road.png")
		_materials["road"].albedo_texture = tile
		_materials["road"].albedo_color = Color("deded3")
		_materials["road"].texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_materials["stone"].albedo_texture = tile
		_materials["stone"].uv1_triplanar = true
		_materials["stone"].uv1_world_triplanar = true
		_materials["stone"].uv1_scale = Vector3.ONE * 0.23
	_materials["terrain"] = _material(Color.WHITE)
	_materials["terrain"].vertex_color_use_as_albedo = true
	_materials["terrain"].vertex_color_is_srgb = true
	var cliff: StandardMaterial3D = _material(Color("eeefe7"))
	cliff.vertex_color_use_as_albedo = true
	cliff.vertex_color_is_srgb = true
	if ResourceLoader.exists("res://art/limestone-cliff.png"):
		cliff.albedo_texture = load("res://art/limestone-cliff.png")
		cliff.uv1_triplanar = true
		cliff.uv1_world_triplanar = true
		cliff.uv1_scale = Vector3.ONE / 12.0
		cliff.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials["cliff"] = cliff
	_materials["castle_stone"] = _material(Color("d7d4bc"))
	if ResourceLoader.exists("res://art/oak-leaves.png"):
		var foliage: StandardMaterial3D = _material(Color("e4eed4"))
		foliage.albedo_texture = load("res://art/oak-leaves.png")
		foliage.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		foliage.alpha_scissor_threshold = 0.38
		foliage.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		foliage.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		_materials["foliage"] = foliage
	_materials["roof"] = _material(Color("8e4e62"))
	_materials["roof_dark"] = _material(Color("67475c"))
	_materials["gold"] = _material(Color("d6b05c"))
	_materials["red"] = _material(Color("c64c50"))
	_materials["white"] = _material(Color("faf2e5"))
	_materials["window"] = _material(Color("29484c"))
	_materials["trunk"] = _material(Color("64594a"))
	_materials["leaf0"] = _material(Color("577f48"))
	_materials["leaf1"] = _material(Color("789943"))
	_materials["leaf2"] = _material(Color("90ad58"))
	_materials["leaf3"] = _material(Color("427452"))
	for key: String in ["leaf0", "leaf1", "leaf2", "leaf3"]:
		_materials[key].vertex_color_use_as_albedo = true
	_materials["flower"] = _material(Color("bd668e"))
	_materials["foam"] = _material(Color("d2f5f1"))
	var waterfall: Shader = Shader.new()
	waterfall.code = """shader_type spatial;
render_mode cull_disabled;
void fragment() {
    float ribbon = sin(UV.x * 75.0 + sin(UV.y * 9.0) * 1.8);
    float streak = pow(abs(sin(UV.y * 42.0 + TIME * 7.0 + UV.x * 6.0)), 9.0);
    ALBEDO = mix(vec3(0.35, 0.78, 0.84), vec3(0.93, 0.99, 0.96), clamp(0.48 + ribbon * 0.24 + streak * 0.28, 0.0, 1.0));
    ROUGHNESS = 0.32;
}"""
	var waterfall_material: ShaderMaterial = ShaderMaterial.new()
	waterfall_material.shader = waterfall
	_materials["waterfall"] = waterfall_material


func _road(width: float) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var distance: float = 0.0
	var circumference: float = 0.0
	for index: int in ROAD_STEPS:
		circumference += _road_point(TAU * index / ROAD_STEPS).distance_to(_road_point(TAU * (index + 1) / ROAD_STEPS))
	var uv_rate: float = roundf(circumference / 4.0) / circumference
	for index: int in ROAD_STEPS:
		var a: float = TAU * float(index) / ROAD_STEPS
		var b: float = TAU * float(index + 1) / ROAD_STEPS
		var start: Vector3 = _road_point(a)
		var end: Vector3 = _road_point(b)
		var next_distance: float = distance + start.distance_to(end)
		var normal_a: Vector3 = _road_normal(a)
		var normal_b: Vector3 = _road_normal(b)
		_quad(surface, start - normal_a * width * 0.5, end - normal_b * width * 0.5, end + normal_b * width * 0.5, start + normal_a * width * 0.5,
			Vector3.UP, Color.WHITE, [Vector2(0.0, distance * uv_rate), Vector2(0.0, next_distance * uv_rate), Vector2(width / 4.0, next_distance * uv_rate), Vector2(width / 4.0, distance * uv_rate)])
		distance = next_distance
	_node_mesh("StoneRoad", surface.commit(), _materials["road"], Transform3D(Basis.IDENTITY, Vector3.UP * 0.015))
	for side: float in [-1.0, 1.0]:
		_parapet(side, width * 0.5 + 0.3, 0.57, 0.0, 0.95, _materials["stone"])
		_parapet(side, width * 0.5 + 0.3, 0.86, 0.95, 1.1, _materials["cap"])
		for index: int in 32:
			var angle: float = TAU * float(index) / 32.0
			var normal: Vector3 = _road_normal(angle)
			var tangent: Vector3 = Vector3(-normal.z, 0.0, normal.x)
			var at: Vector3 = _road_point(angle) + normal * side * (width * 0.5 + 0.3)
			_box(at + Vector3.UP * 0.73, Vector3(0.95, 1.46, 0.95), _materials["stone"])
			_box(at + Vector3.UP * 1.48, Vector3(1.1, 0.2, 1.1), _materials["cap"])
			if index % 2 == 0:
				var facing: Basis = Basis(tangent * side, Vector3.UP, -normal * side)
				var board_at: Vector3 = at - normal * side * 0.49 + Vector3.UP * 0.65
				_place(_unit_box(), _materials["red"], _pose(board_at, Vector3(3.3, 0.68, 0.07), facing), false)
				for arrow: float in [-0.95, 0.0, 0.95]:
					_place(_chevron_mesh(), _materials["white"], _pose(board_at + facing.x * arrow + facing.z * 0.05, Vector3(0.95, 0.78, 1.0), facing), false)


func _parapet(side: float, offset: float, width: float, bottom: float, top: float, material: Material) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in ROAD_STEPS:
		var a: float = TAU * float(index) / ROAD_STEPS
		var b: float = TAU * float(index + 1) / ROAD_STEPS
		var na: Vector3 = _road_normal(a)
		var nb: Vector3 = _road_normal(b)
		var ai: Vector3 = _road_point(a) + na * (side * offset - width * 0.5)
		var ao: Vector3 = ai + na * width
		var bi: Vector3 = _road_point(b) + nb * (side * offset - width * 0.5)
		var bo: Vector3 = bi + nb * width
		_quad(surface, ai + Vector3.UP * top, bi + Vector3.UP * top, bo + Vector3.UP * top, ao + Vector3.UP * top, Vector3.UP)
		_quad(surface, ai + Vector3.UP * bottom, bi + Vector3.UP * bottom, bi + Vector3.UP * top, ai + Vector3.UP * top, -(na + nb).normalized())
		_quad(surface, ao + Vector3.UP * bottom, bo + Vector3.UP * bottom, bo + Vector3.UP * top, ao + Vector3.UP * top, (na + nb).normalized())
	_node_mesh("Parapet", surface.commit(), material)


func _island(label: String, center: Vector3, radius: Vector2, bottom: float, segments: int, phase: float) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls: SurfaceTool = SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for layer: int in 7:
		var points: PackedVector3Array = []
		var radius_scale: float = [1.0, 1.015, 0.96, 1.04, 0.95, 1.08, 0.87][layer]
		var height: float = lerpf(bottom, center.y, [1.0, 0.94, 0.77, 0.56, 0.38, 0.17, 0.0][layer])
		for index: int in segments:
			var angle: float = TAU * float(index) / segments
			var jitter: float = 1.0 + sin(angle * 7.0 + phase) * 0.055 + sin(angle * 19.0 + phase * 3.0 + layer * 0.8) * 0.035
			var jagged_height: float = height + (sin(angle * 13.0 + phase) * 0.65 if layer > 0 else 0.0)
			points.append(Vector3(center.x + cos(angle) * radius.x * radius_scale * jitter, jagged_height, center.z + sin(angle) * radius.y * radius_scale * jitter))
		rings.append(points)
	for index: int in segments:
		var next: int = (index + 1) % segments
		_triangle(surface, center, rings[0][next], rings[0][index], Vector3.UP, Color("6f8c56").lightened(0.025 * sin(index * 1.8)))
		for layer: int in 6:
			var normal: Vector3 = (rings[layer][next] - rings[layer][index]).cross(rings[layer + 1][index] - rings[layer][index]).normalized()
			var tint: Color = [Color("899084"), Color("a3a79b"), Color("878f88"), Color("9aa499"), Color("738c85"), Color("607b78")][layer]
			tint = tint.lightened(0.48 + 0.06 * sin(float(index) * 2.71 + phase))
			_quad(walls, rings[layer][index], rings[layer][next], rings[layer + 1][next], rings[layer + 1][index], normal, tint)
	_node_mesh(label, surface.commit(), _materials["terrain"])
	_node_mesh(label + "Cliffs", walls.commit(), _materials["cliff"])


func _castle() -> void:
	var castle_basis: Basis = Basis.from_scale(Vector3(1.45, 0.64, 1.25))
	_placement_transform = Transform3D(castle_basis, CASTLE - castle_basis * CASTLE)
	var original_stone: Material = _materials["stone"]
	_materials["stone"] = _materials["castle_stone"]
	var stone: Material = _materials["castle_stone"]
	var cap: Material = _materials["cap"]
	_box(CASTLE + Vector3(0.0, 0.35, 0.0), Vector3(53.0, 0.7, 43.0), cap)
	_box(CASTLE + Vector3(0.0, 20.0, 1.0), Vector3(18.0, 40.0, 21.0), stone)
	_place(_pyramid_mesh(), _materials["roof_dark"], _pose(CASTLE + Vector3(0.0, 47.0, 1.0), Vector3(20.5, 14.0, 23.5)))
	for x: float in [-9.0, 9.0]:
		for z: float in [-10.0, 10.0]:
			_tower(CASTLE + Vector3(x, 28.0, z), 2.0, 21.0, 9.0)
	_tower(CASTLE + Vector3(0.0, 0.0, 10.0), 4.6, 57.0, 18.0)
	for side: float in [-1.0, 1.0]:
		_tower(CASTLE + Vector3(side * 18.0, 0.0, -16.0), 4.0, 30.0, 12.0)
		_tower(CASTLE + Vector3(side * 24.0, 0.0, 13.0), 3.5, 35.0, 14.0)
		_box(CASTLE + Vector3(side * 17.0, 9.0, -4.0), Vector3(12.0, 18.0, 21.0), stone)
		_place(_pyramid_mesh(), _materials["roof"], _pose(CASTLE + Vector3(side * 17.0, 22.0, -4.0), Vector3(13.5, 8.0, 22.5)))
		_box(CASTLE + Vector3(side * 15.0, 5.2, -25.0), Vector3(20.0, 10.4, 2.3), stone)
		_crenels(CASTLE + Vector3(side * 15.0, 10.7, -25.0), 20.0, 9)
		_tower(CASTLE + Vector3(side * 28.0, 0.0, -25.0), 2.8, 15.0, 0.0)
	_arch(CASTLE + Vector3(0.0, 0.0, -25.0), 4.3, 6.2, 2.2)
	for floor_index: int in 4:
		for x: float in [-5.5, 0.0, 5.5]:
			_place(_window_mesh(), _materials["window"], _pose(CASTLE + Vector3(x, 8.0 + floor_index * 7.5, -9.55), Vector3(1.7, 2.25, 1.0)), false)
	for side: float in [-1.0, 1.0]:
		_banner(CASTLE + Vector3(side * 7.0, 13.0, -26.3), 2.0)
		_banner(CASTLE + Vector3(side * 13.0, 22.0, -14.7), 1.7)
	_materials["stone"] = original_stone
	_placement_transform = Transform3D.IDENTITY


func _tower(base: Vector3, radius: float, height: float, roof_height: float) -> void:
	_place(_cylinder_mesh(), _materials["stone"], _pose(base + Vector3.UP * height * 0.5, Vector3(radius, height, radius)))
	for y: float in [0.6, height * 0.45, height - 0.6]:
		_place(_cylinder_mesh(), _materials["cap"], _pose(base + Vector3.UP * y, Vector3(radius * 1.12, 0.6, radius * 1.12)))
	if height >= 7.5:
		for tier: int in maxi(1, int(height / 9.0)):
			for side: int in 6:
				var angle: float = TAU * side / 6.0
				var position: Vector3 = base + Vector3(sin(angle) * (radius + 0.02), 5.5 + tier * 8.5, cos(angle) * (radius + 0.02))
				_place(_window_mesh(), _materials["window"], _pose(position, Vector3(radius * 0.37, 1.55, 1.0), Basis(Vector3.UP, angle)), false)
	if roof_height > 0.0:
		_place(_cone_mesh(), _materials["roof"], _pose(base + Vector3.UP * (height + roof_height * 0.5), Vector3(radius * 1.35, roof_height, radius * 1.35)))
		_place(_cone_mesh(), _materials["gold"], _pose(base + Vector3.UP * (height + roof_height + 1.0), Vector3(0.22, 2.2, 0.22)))
	else:
		for index: int in 10:
			var angle: float = TAU * index / 10.0
			_box(base + Vector3(sin(angle) * radius, height + 0.5, cos(angle) * radius), Vector3(1.0, 1.2, 1.0), _materials["cap"], Basis(Vector3.UP, angle))


func _viaduct() -> void:
	for index: int in 5:
		_arch(Vector3(-4.0 + index * 20.0, -19.0, 91.0), 8.0, 12.0, 6.5)
	_box(Vector3(36.0, 4.1, 91.0), Vector3(100.0, 1.8, 7.5), _materials["stone"])
	for side: float in [-1.0, 1.0]:
		_box(Vector3(36.0, 5.35, 91.0 + side * 3.75), Vector3(100.0, 1.0, 0.6), _materials["cap"])
	for end: float in [-13.0, 85.0]:
		_tower(Vector3(end, 3.2, 91.0), 3.5, 9.5, 0.0)


func _arch(base: Vector3, radius: float, spring_height: float, depth: float) -> void:
	_place(_arch_mesh(), _materials["stone"], _pose(base + Vector3.UP * spring_height, Vector3(radius, radius, depth)))
	for side: float in [-1.0, 1.0]:
		_box(base + Vector3(side * radius * 1.14, spring_height * 0.5, 0.0), Vector3(radius * 0.28, spring_height, depth), _materials["stone"])
		_box(base + Vector3(side * radius * 1.14, spring_height, 0.0), Vector3(radius * 0.4, 0.5, depth * 1.1), _materials["cap"])


func _crenels(base: Vector3, length: float, count: int) -> void:
	for index: int in count:
		_box(base + Vector3((float(index) / (count - 1) - 0.5) * length, 0.0, 0.0), Vector3(1.2, 1.5, 2.6), _materials["cap"])


func _banner(at: Vector3, size: float) -> void:
	_place(_banner_mesh(), _materials["red"], _pose(at, Vector3(size, size, 1.0)), false)
	_place(_cylinder_mesh(), _materials["gold"], _pose(at + Vector3.UP * size, Vector3(0.07, size * 1.3, 0.07), Basis(Vector3.FORWARD, PI * 0.5)))
	_place(_diamond_mesh(), _materials["gold"], _pose(at + Vector3(0.0, 0.12, -0.025), Vector3(size * 0.28, size * 0.35, 1.0)), false)


func _forest() -> void:
	_tree(Vector3(44.0, -0.18, 12.0), 1.35, 31)
	_tree(Vector3(77.0, -0.18, 13.0), 1.3, 46)
	_tree(Vector3(25.0, -0.18, 30.0), 1.45, 21)
	_tree(Vector3(71.0, -0.18, 29.0), 1.3, 52)
	for index: int in 46:
		var angle: float = TAU * (index + 0.35) / 46.0
		var normal: Vector3 = _road_normal(angle)
		var location: Vector3 = _road_point(angle) + normal * (12.0 + 1.5 * sin(index * 2.3))
		if location.z > 6.0 and location.x > 9.0:
			continue
		_tree(location + Vector3.DOWN * 0.18, 0.75 + 0.38 * (sin(index * 2.1) + 1.0) * 0.5, index)
	for index: int in 27:
		var angle: float = TAU * (index + 0.7) / 27.0
		var location: Vector3 = Vector3(cos(angle) * 40.0, -0.18, sin(angle) * 24.0)
		_tree(location, 0.7 + 0.35 * (cos(index * 1.7) + 1.0) * 0.5, index + 2)
	for index: int in 20:
		var angle: float = TAU * index / 20.0
		if sin(angle) < -0.15:
			continue
		_tree(CASTLE + Vector3(cos(angle) * 47.0, 0.0, sin(angle) * 36.0), 0.72 + (index % 3) * 0.08, index)
	for index: int in 9:
		_tree(Vector3(-120.0 + (index % 3) * 8.0, 10.0, 55.0 + (index / 3) * 12.0), 1.2, index)
	for index: int in 32:
		var angle: float = TAU * index / 32.0
		var location: Vector3 = Vector3(cos(angle) * 43.5, 0.3, sin(angle) * 27.5)
		_place(_leaf_mesh(), _materials["leaf3"], _pose(location, Vector3(1.8, 0.8, 1.5)), false)
		if index % 3 == 0:
			_place(_leaf_mesh(), _materials["flower"], _pose(location + Vector3(0.2, 0.55, 0.0), Vector3(1.0, 0.28, 0.7)), false)


func _tree(at: Vector3, size: float, variation: int) -> void:
	var height: float = (6.7 + sin(variation * 1.7) * 1.4) * size
	_place(_tapered_cylinder_mesh(), _materials["trunk"], _pose(at + Vector3.UP * height * 0.36, Vector3(0.28 * size, height * 0.72, 0.28 * size)))
	for branch: int in 3:
		var angle: float = variation * 0.9 + branch * TAU / 3.0
		var branch_up: Vector3 = Vector3(cos(angle) * 0.7, 1.0, sin(angle) * 0.7).normalized()
		var orientation: Basis = Basis.looking_at(Vector3(branch_up.z, 0.0, -branch_up.x), branch_up)
		_place(_tapered_cylinder_mesh(), _materials["trunk"], _pose(at + Vector3(cos(angle) * size * 0.5, height * 0.57, sin(angle) * size * 0.5), Vector3(0.14 * size, height * 0.38, 0.14 * size), orientation))
	for cluster: int in 7:
		var angle: float = cluster * 2.399 + variation * 0.37
		var radial: float = 1.8 * size if cluster < 6 else 0.0
		var location: Vector3 = at + Vector3(cos(angle) * radial, height * (0.81 + (cluster % 3) * 0.07), sin(angle) * radial)
		var scale: Vector3 = Vector3(2.2, 1.7 + (cluster % 2) * 0.5, 1.9) * size
		if _materials.has("foliage"):
			for spray: int in 8:
				var turn: float = angle + spray * 2.399
				var vertical: float = -0.8 + float(spray) / 7.0 * 1.6
				var radius: float = sqrt(maxf(0.0, 1.0 - vertical * vertical))
				var offset: Vector3 = Vector3(cos(turn) * radius * scale.x * 0.6, vertical * scale.y * 0.65, sin(turn) * radius * scale.z * 0.6)
				var orientation: Basis = Basis.from_euler(Vector3(sin(turn * 1.7) * 0.85, turn, cos(turn * 1.2) * 0.4))
				_place(_leaf_card_mesh(), _materials["foliage"], _pose(location + offset, Vector3.ONE * (1.75 + (spray % 3) * 0.22) * size, orientation))
		else:
			_place(_leaf_mesh(), _materials["leaf%d" % ((variation + cluster) % 4)], _pose(location, scale, Basis(Vector3.UP, angle)))


func _lake() -> void:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(1200.0, 1200.0)
	mesh.subdivide_width = 30
	mesh.subdivide_depth = 30
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    float ripple = sin(world_position.x * 0.42 + TIME * 0.7) * sin(world_position.z * 0.37 - TIME * 0.5);
    float glint = pow(max(0.0, sin(world_position.x * 0.18 + world_position.z * 0.72 + TIME)), 18.0);
    ALBEDO = mix(vec3(0.05, 0.43, 0.61), vec3(0.1, 0.7, 0.75), 0.45 + ripple * 0.16) + vec3(0.13, 0.2, 0.2) * glint;
    ROUGHNESS = 0.3;
    SPECULAR = 0.6;
}"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	_node_mesh("Lake", mesh, material, Transform3D(Basis.IDENTITY, Vector3(0.0, -19.5, 0.0)), false)


func _waterfall(top: Vector3, width: float, height: float, phase: float) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in 22:
		var a: float = float(index) / 22.0
		var b: float = float(index + 1) / 22.0
		var ca: Vector3 = top + Vector3(sin(a * 4.0 + phase) * width * 0.08, -a * height, -sin(a * PI * 0.5) * 6.0)
		var cb: Vector3 = top + Vector3(sin(b * 4.0 + phase) * width * 0.08, -b * height, -sin(b * PI * 0.5) * 6.0)
		var wa: float = width * (0.5 + a * 0.18)
		var wb: float = width * (0.5 + b * 0.18)
		_quad(surface, ca - Vector3.RIGHT * wa, cb - Vector3.RIGHT * wb, cb + Vector3.RIGHT * wb, ca + Vector3.RIGHT * wa, Vector3.FORWARD, Color.WHITE, [Vector2(0.0, a), Vector2(0.0, b), Vector2(1.0, b), Vector2(1.0, a)])
	_node_mesh("Waterfalls", surface.commit(), _materials["waterfall"], Transform3D.IDENTITY, false)
	var foam: SurfaceTool = SurfaceTool.new()
	foam.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center: Vector3 = Vector3(top.x, -19.3, top.z - 7.0)
	for index: int in 32:
		var a: float = TAU * index / 32.0
		var b: float = TAU * (index + 1) / 32.0
		var pa: Vector3 = center + Vector3(cos(a) * width * 0.92, 0.0, sin(a) * 4.0) * (1.0 + 0.15 * sin(a * 11.0))
		var pb: Vector3 = center + Vector3(cos(b) * width * 0.92, 0.0, sin(b) * 4.0) * (1.0 + 0.15 * sin(b * 11.0))
		_triangle(foam, center, pb, pa, Vector3.UP)
	_node_mesh("WaterfallFoam", foam.commit(), _materials["foam"], Transform3D.IDENTITY, false)


func _mountains() -> void:
	for index: int in 13:
		var angle: float = 0.15 + index * TAU / 13.0
		var position: Vector3 = Vector3(cos(angle) * 360.0, -21.0, sin(angle) * 340.0)
		_place(_mountain_mesh(), _materials["terrain"], _pose(position, Vector3(50.0 + (index % 3) * 12.0, 90.0 + (index % 4) * 18.0, 57.0 + (index % 2) * 15.0), Basis(Vector3.UP, angle)), false)


func _start_gate() -> void:
	for side: float in [-1.0, 1.0]:
		var base: Vector3 = Vector3(_radius_x + side * 10.4, 0.0, 4.0)
		_tower(base, 0.8, 3.4, 1.7)
		_banner(base + Vector3(0.0, 2.0, -0.85), 0.7)
	for index: int in 12:
		_box(Vector3(_radius_x - 5.5 + index, 0.029, 0.0), Vector3(0.93, 0.025, 0.7), _materials["white"] if index % 2 == 0 else _materials["window"])


func _road_point(angle: float) -> Vector3:
	return Vector3(_radius_x * cos(angle), 0.0, _radius_z * sin(angle))


func _road_normal(angle: float) -> Vector3:
	return Vector3(_radius_z * cos(angle), 0.0, _radius_x * sin(angle)).normalized()


func _box(at: Vector3, size: Vector3, material: Material, orientation: Basis = Basis.IDENTITY) -> void:
	_place(_unit_box(), material, _pose(at, size, orientation))


func _pose(at: Vector3, size: Vector3 = Vector3.ONE, orientation: Basis = Basis.IDENTITY) -> Transform3D:
	return Transform3D(orientation * Basis.from_scale(size), at)


func _place(mesh: Mesh, material: Material, pose: Transform3D, shadow: bool = true) -> void:
	var key: String = "%s_%s_%s" % [mesh.get_instance_id(), material.get_instance_id(), shadow]
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "material": material, "transforms": [], "shadow": shadow}
	_batches[key]["transforms"].append(_placement_transform * pose)


func _flush_batches() -> void:
	for key: String in _batches:
		var batch: Dictionary = _batches[key]
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = batch["mesh"]
		multi.instance_count = batch["transforms"].size()
		for index: int in multi.instance_count:
			multi.set_instance_transform(index, batch["transforms"][index])
		var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
		visual.name = "Batch_%d" % get_child_count()
		visual.multimesh = multi
		visual.material_override = batch["material"]
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if batch["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	_batches.clear()


func _node_mesh(label: String, mesh: Mesh, material: Material, pose: Transform3D = Transform3D.IDENTITY, shadow: bool = true) -> void:
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.material_override = material
	visual.transform = pose
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.83
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _unit_box() -> Mesh:
	if not _meshes.has("box"):
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3.ONE
		_meshes["box"] = mesh
	return _meshes["box"]


func _cylinder_mesh() -> Mesh:
	return _cylinder("cylinder", 1.0)


func _cone_mesh() -> Mesh:
	return _cylinder("cone", 0.0)


func _tapered_cylinder_mesh() -> Mesh:
	return _cylinder("trunk", 0.48)


func _cylinder(key: String, top: float) -> Mesh:
	if not _meshes.has(key):
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = top
		mesh.bottom_radius = 1.0
		mesh.height = 1.0
		mesh.radial_segments = 16
		_meshes[key] = mesh
	return _meshes[key]


func _leaf_mesh() -> Mesh:
	if not _meshes.has("leaf"):
		var seed: SphereMesh = SphereMesh.new()
		seed.radius = 1.0
		seed.height = 2.0
		seed.radial_segments = 18
		seed.rings = 10
		var arrays: Array = seed.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = []
		for index: int in vertices.size():
			var point: Vector3 = vertices[index]
			var lobe: float = 1.0 + 0.095 * sin(point.x * 13.0 + point.z * 9.0) + 0.065 * sin(point.y * 17.0 - point.x * 11.0)
			vertices[index] = point * lobe
			var shade: float = 0.9 + point.y * 0.08 + 0.06 * sin(point.x * 23.0 + point.y * 17.0)
			colors.append(Color(shade, shade, shade, 1.0))
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_meshes["leaf"] = mesh
	return _meshes["leaf"]


func _leaf_card_mesh() -> Mesh:
	if not _meshes.has("leaf_card"):
		var mesh: QuadMesh = QuadMesh.new()
		mesh.size = Vector2.ONE
		_meshes["leaf_card"] = mesh
	return _meshes["leaf_card"]


func _chevron_mesh() -> Mesh:
	return _polygon_mesh("chevron", PackedVector2Array([Vector2(-0.45, -0.35), Vector2(-0.13, -0.35), Vector2(0.25, 0.0), Vector2(-0.13, 0.35), Vector2(-0.45, 0.35), Vector2(-0.07, 0.0)]))


func _banner_mesh() -> Mesh:
	return _polygon_mesh("banner", PackedVector2Array([Vector2(-0.5, 1.0), Vector2(0.5, 1.0), Vector2(0.5, -0.8), Vector2(0.0, -1.1), Vector2(-0.5, -0.8)]))


func _diamond_mesh() -> Mesh:
	return _polygon_mesh("diamond", PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.65, 0.0), Vector2(0.0, -1.0), Vector2(-0.65, 0.0)]))


func _window_mesh() -> Mesh:
	var points: PackedVector2Array = [Vector2(-0.5, -1.0), Vector2(0.5, -1.0), Vector2(0.5, 0.4)]
	for index: int in 11:
		var angle: float = PI * float(index) / 10.0
		points.append(Vector2(cos(angle) * 0.5, 0.4 + sin(angle) * 0.5))
	return _polygon_mesh("window", points)


func _polygon_mesh(key: String, points: PackedVector2Array) -> Mesh:
	if not _meshes.has(key):
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(points)
		for index: int in indices:
			surface.set_normal(Vector3.FORWARD)
			surface.set_uv(points[index])
			surface.add_vertex(Vector3(points[index].x, points[index].y, 0.0))
		_meshes[key] = surface.commit()
	return _meshes[key]


func _arch_mesh() -> Mesh:
	if not _meshes.has("arch"):
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index: int in 20:
			var a: float = PI * index / 20.0
			var b: float = PI * (index + 1) / 20.0
			var ai: Vector3 = Vector3(cos(a), sin(a), 0.0)
			var bi: Vector3 = Vector3(cos(b), sin(b), 0.0)
			for side: float in [-1.0, 1.0]:
				var depth: Vector3 = Vector3.BACK * side * 0.5
				_quad(surface, ai + depth, bi + depth, bi * 1.28 + depth, ai * 1.28 + depth, Vector3.BACK * side)
			_quad(surface, ai + Vector3.FORWARD * 0.5, bi + Vector3.FORWARD * 0.5, bi + Vector3.BACK * 0.5, ai + Vector3.BACK * 0.5, -(ai + bi).normalized())
			_quad(surface, ai * 1.28 + Vector3.FORWARD * 0.5, bi * 1.28 + Vector3.FORWARD * 0.5, bi * 1.28 + Vector3.BACK * 0.5, ai * 1.28 + Vector3.BACK * 0.5, (ai + bi).normalized())
		_meshes["arch"] = surface.commit()
	return _meshes["arch"]


func _pyramid_mesh() -> Mesh:
	if not _meshes.has("pyramid"):
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var corners: Array[Vector3] = [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5)]
		for index: int in 4:
			var a: Vector3 = corners[index]
			var b: Vector3 = corners[(index + 1) % 4]
			_triangle(surface, a, b, Vector3.UP * 0.5, Vector3((a.x + b.x) * 0.5, 0.5, (a.z + b.z) * 0.5).normalized())
		_meshes["pyramid"] = surface.commit()
	return _meshes["pyramid"]


func _mountain_mesh() -> Mesh:
	if not _meshes.has("mountain"):
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var noise: FastNoiseLite = FastNoiseLite.new()
		noise.seed = 7319
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 3.6
		noise.fractal_octaves = 4
		noise.fractal_gain = 0.54
		const STEPS: int = 40
		var grid: PackedVector3Array = []
		for z: int in STEPS + 1:
			for x: int in STEPS + 1:
				var px: float = lerpf(-1.5, 1.5, float(x) / STEPS)
				var pz: float = lerpf(-1.5, 1.5, float(z) / STEPS)
				grid.append(Vector3(px, _mountain_height(px, pz, noise), pz))
		for z: int in STEPS:
			for x: int in STEPS:
				var a: Vector3 = grid[z * (STEPS + 1) + x]
				var b: Vector3 = grid[z * (STEPS + 1) + x + 1]
				var c: Vector3 = grid[(z + 1) * (STEPS + 1) + x + 1]
				var d: Vector3 = grid[(z + 1) * (STEPS + 1) + x]
				_mountain_face(surface, a, c, b, noise)
				_mountain_face(surface, a, d, c, noise)
		_meshes["mountain"] = surface.commit()
	return _meshes["mountain"]


func _mountain_height(x: float, z: float, noise: FastNoiseLite) -> float:
	var peaks: float = maxf(
		0.97 * exp(-((x + 0.48) * (x + 0.48) / 0.2 + (z - 0.13) * (z - 0.13) / 0.35)),
		0.88 * exp(-((x - 0.28) * (x - 0.28) / 0.25 + (z + 0.42) * (z + 0.42) / 0.16)))
	peaks = maxf(peaks, 0.65 * exp(-((x - 0.56) * (x - 0.56) / 0.12 + (z - 0.42) * (z - 0.42) / 0.28)))
	var edge: float = clampf((1.5 - maxf(absf(x), absf(z))) * 2.5, 0.0, 1.0)
	var ridge: float = 1.0 - absf(noise.get_noise_2d(x, z))
	return maxf(0.0, (peaks * (0.84 + ridge * 0.2) + noise.get_noise_2d(x * 2.7, z * 2.7) * 0.055) * edge)


func _mountain_face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, noise: FastNoiseLite) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	var center: Vector3 = (a + b + c) / 3.0
	var variation: float = noise.get_noise_2d(center.x * 1.7, center.z * 1.7)
	var stone: Color = Color("819da2").lightened(variation * 0.14 + center.y * 0.09)
	var snow: float = smoothstep(0.79 + variation * 0.13, 0.96, center.y) * clampf(normal.y * 1.25, 0.0, 1.0)
	_triangle(surface, a, b, c, normal, stone.lerp(Color("cbd5d0"), snow))


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color = Color.WHITE) -> void:
	for point: Vector3 in [a, b, c]:
		surface.set_normal(normal)
		surface.set_color(color)
		surface.set_uv(Vector2(point.x, point.y))
		surface.add_vertex(point)


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color = Color.WHITE, uv: Array = []) -> void:
	var positions: Array[Vector3] = [a, b, c, d]
	var coordinates: Array = uv if uv.size() == 4 else [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for index: int in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(normal)
		surface.set_color(color)
		surface.set_uv(coordinates[index])
		surface.add_vertex(positions[index])
