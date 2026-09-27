extends Node3D

const Baker = preload("res://track/track_baker.gd")
const Kit = preload("res://track/study_kit.gd")
const WATER_Y: float = -10.0
const CASTLE_ANCHOR := Vector3(-158, 18, -128)
const FALL_ANCHOR := Vector3(-63, 19, 69)

var _kit: Node3D
var _data: Dictionary
var _water: ShaderMaterial
var _fall: ShaderMaterial
var _built: bool = false
var direction_sign_poses: Array[Transform3D] = []


func build(data: Dictionary) -> void:
	if _built:
		return
	_built = true
	name = "InternalEnvironmentStudy"
	set_meta("production_accepted", false)
	set_meta("simulation_hash", data.simulation_hash)
	_data = data
	_kit = Kit.new()
	add_child(_kit)
	_kit.prepare()
	_road()
	_shore_ribbons()
	_water_features()
	_castle_bridge()
	_forest()
	_distance_landscape()
	_start_landmarks()
	_kit.finish()


func set_quality(low: bool) -> void:
	if _kit != null:
		_kit.set_quality(low)


func set_reduced_effects(enabled: bool) -> void:
	if _water != null:
		_water.set_shader_parameter("motion_strength", 0.18 if enabled else 1.0)
	if _fall != null:
		_fall.set_shader_parameter("motion_strength", 0.4 if enabled else 1.0)


func _road() -> void:
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in _data.samples.size() - 1:
		var a: Dictionary = _data.samples[index]
		var b: Dictionary = _data.samples[index + 1]
		var forward: Vector3 = Baker.vector(a.tangent)
		var normal: Vector3 = forward.cross(Vector3.UP).normalized().cross(forward).normalized()
		var uv: Array[Vector2] = [Vector2(0, a.s / 4.0), Vector2(0, b.s / 4.0), Vector2(a.width / 4.0, a.s / 4.0), Vector2(0, b.s / 4.0), Vector2(b.width / 4.0, b.s / 4.0), Vector2(a.width / 4.0, a.s / 4.0)]
		for corner: int in 6:
			road.set_normal(normal)
			road.set_uv(uv[corner])
			road.add_vertex(Baker.vector(_data.collision.road_faces[index * 6 + corner]) + Vector3.UP * 0.012)
	_kit._node_mesh("StudyStoneRoad", road.commit(), _kit._materials.road)
	for barrier: Dictionary in _data.collision.barriers:
		var pose := Transform3D(Basis.looking_at(Baker.vector(barrier.forward), Vector3.UP), Baker.vector(barrier.position))
		_kit._box(pose.origin, Baker.vector(barrier.size), _kit._materials.stone, pose.basis)
		_kit._box(pose.origin + Vector3.UP * 0.68, Vector3(0.75, 0.16, float(barrier.size[2])), _kit._materials.cap, pose.basis)
	for distance: int in range(0, int(_data.length), 14):
		var sample: Dictionary = Baker.sample_at(_data, distance)
		var forward: Vector3 = Baker.vector(sample.tangent)
		var side: Vector3 = forward.cross(Vector3.UP).normalized()
		var base: Vector3 = Baker.vector(sample.position)
		for sign_value: float in [-1.0, 1.0]:
			var point: Vector3 = base + side * sign_value * 7.25
			_kit._box(point + Vector3.UP * 0.83, Vector3(1.05, 1.66, 1.05), _kit._materials.stone)
			_kit._box(point + Vector3.UP * 1.68, Vector3(1.18, 0.2, 1.18), _kit._materials.cap)
			if distance % 42 == 0:
				_kit._place(_kit._cylinder_mesh(), _kit._materials.gold, _kit._pose(point + Vector3.UP * 2.65, Vector3(0.08, 1.8, 0.08)))
				_kit._banner(point + Vector3.UP * 3.1, 0.7)
		if distance > 105 and distance < 275:
			var board: Vector3 = base - side * 6.92 + Vector3.UP * 0.82
			var facing := Basis(-forward.slide(Vector3.UP).normalized(), Vector3.UP, side)
			_kit._box(board, Vector3(3.5, 0.65, 0.09), _kit._materials.red, facing)
			# The board faces the road, but the chevron tip must follow route +s.
			var arrow_facing := Basis(forward.slide(Vector3.UP).normalized(), Vector3.DOWN, side)
			for offset: float in [-1.0, 0.0, 1.0]:
				var pose: Transform3D = _kit._pose(board + facing.x * offset + facing.z * 0.06, Vector3(0.9, 0.65, 1), arrow_facing)
				direction_sign_poses.append(pose)
				_kit._place(_kit._chevron_mesh(), _kit._materials.white, pose, false)


func _shore_ribbons() -> void:
	for chunk: int in range(0, _data.samples.size() - 1, 40):
		var turf := SurfaceTool.new()
		turf.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cliff := SurfaceTool.new()
		cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
		var populated: bool = false
		for index: int in range(chunk, mini(chunk + 40, _data.samples.size() - 1)):
			var a: Dictionary = _data.samples[index]
			var b: Dictionary = _data.samples[index + 1]
			if float(a.s) > 548.0 and float(a.s) < 670.0:
				continue
			populated = true
			for side: float in [-1.0, 1.0]:
				var rings_a: Array[Vector3] = _bank(a, side)
				var rings_b: Array[Vector3] = _bank(b, side)
				for ring: int in 3:
					var color: Color = Color("68864e").lightened(0.03 * sin(float(index) * 0.3))
					_kit._quad(turf if ring == 0 else cliff, rings_a[ring], rings_b[ring], rings_b[ring + 1], rings_a[ring + 1], Vector3.UP if ring == 0 else (rings_a[ring] - rings_a[ring + 1]).normalized(), color if ring == 0 else Color("d3d6cc"))
		if populated:
			_kit._node_mesh("StudyBankTurf_%d" % chunk, turf.commit(), _kit._materials.terrain)
			_kit._node_mesh("StudyBankCliff_%d" % chunk, cliff.commit(), _kit._materials.cliff)


func _bank(sample: Dictionary, sign_value: float) -> Array[Vector3]:
	var p: Vector3 = Baker.vector(sample.position)
	var right: Vector3 = Baker.vector(sample.tangent).cross(Vector3.UP).normalized() * sign_value
	var forest: bool = float(sample.s) > 65.0 and float(sample.s) < 278.0
	var width: float = 22.0 if forest else 11.8
	var variation: float = sin(float(sample.s) * 0.07) * 1.0
	return [p + right * 7.7 - Vector3.UP * 0.13, p + right * (width + variation) + Vector3.UP * (0.4 if forest else -0.4), Vector3(p.x, p.y - 7.0, p.z) + right * (width + 4.0), Vector3(p.x, WATER_Y - 1.2, p.z) + right * (width + 7.5)]


func _water_features() -> void:
	_water = ShaderMaterial.new()
	_water.shader = load("res://track/study_water.gdshader")
	var lake := PlaneMesh.new()
	lake.size = Vector2(900, 900)
	_kit._node_mesh("StudyLake", lake, _water, Transform3D(Basis.IDENTITY, Vector3(0, WATER_Y, 0)), false)
	_fall = ShaderMaterial.new()
	_fall.shader = load("res://track/study_waterfall.gdshader")
	_kit._island("WaterfallRockShelf", FALL_ANCHOR - Vector3(0, 0.5, 19), Vector2(28, 22), WATER_Y - 3, 48, 2.1)
	_kit._island("WaterfallSideShelf", Vector3(-24, 12, 63), Vector2(17, 15), WATER_Y - 3, 36, 3.4)
	_waterfall(FALL_ANCHOR, 12.0, "Main")
	_waterfall(Vector3(-26, 12, 78), 6.0, "Side")
	for i: int in 6:
		_kit._tree(FALL_ANCHOR + Vector3(-20 + i * 7, -0.5, -21 - (i % 2) * 6), 1.1 + (i % 3) * 0.13, i)


func _waterfall(top: Vector3, width: float, label: String) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height: float = top.y - WATER_Y
	for index: int in 24:
		var a: float = float(index) / 24.0
		var b: float = float(index + 1) / 24.0
		var ca: Vector3 = top + Vector3(sin(a * 6) * width * 0.04, -a * height, sin(a * PI * 0.5) * 5.0)
		var cb: Vector3 = top + Vector3(sin(b * 6) * width * 0.04, -b * height, sin(b * PI * 0.5) * 5.0)
		_kit._quad(surface, ca - Vector3.RIGHT * width * (0.5 + a * 0.15), cb - Vector3.RIGHT * width * (0.5 + b * 0.15), cb + Vector3.RIGHT * width * (0.5 + b * 0.15), ca + Vector3.RIGHT * width * (0.5 + a * 0.15), Vector3.BACK, Color.WHITE, [Vector2(0,a), Vector2(0,b), Vector2(1,b), Vector2(1,a)])
	_kit._node_mesh("StudyWaterfall" + label, surface.commit(), _fall, Transform3D.IDENTITY, false)
	var foam := SurfaceTool.new()
	foam.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(top.x, WATER_Y + 0.025, top.z + 5.5)
	for index: int in 40:
		var a: float = TAU * index / 40.0
		var b: float = TAU * (index + 1) / 40.0
		var pa: Vector3 = center + Vector3(cos(a) * width * 0.78, 0, sin(a) * 4.5) * (1.0 + sin(a * 11) * 0.1)
		var pb: Vector3 = center + Vector3(cos(b) * width * 0.78, 0, sin(b) * 4.5) * (1.0 + sin(b * 11) * 0.1)
		_kit._triangle(foam, center, pb, pa, Vector3.UP)
	_kit._node_mesh("StudyWaterfallFoam" + label, foam.commit(), _kit._materials.foam, Transform3D.IDENTITY, false)


func _castle_bridge() -> void:
	_kit.castle(CASTLE_ANCHOR)
	for distance: int in range(554, 669, 17):
		var sample: Dictionary = Baker.sample_at(_data, distance)
		var p: Vector3 = Baker.vector(sample.position)
		var forward: Vector3 = Baker.vector(sample.tangent).slide(Vector3.UP).normalized()
		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		var orientation := Basis(forward, Vector3.UP, right)
		for side: float in [-1.0, 1.0]:
			var top: Vector3 = p + right * side * 6.7
			_kit._place(_kit._arch_mesh(), _kit._materials.stone, _kit._pose(top - Vector3.UP * 10.4, Vector3(7.2, 7.8, 1.1), orientation))
			_kit._box(top - Vector3.UP * 1.2, Vector3(17.0, 2.5, 1.2), _kit._materials.stone, orientation)
			var foot: Vector3 = top + forward * 8.0
			var height: float = foot.y - WATER_Y
			_kit._box(foot - Vector3.UP * height * 0.5, Vector3(2.1, height, 2.0), _kit._materials.stone, orientation)
	_kit._island("BridgeLandingRock", Vector3(-114, 15.0, -73), Vector2(21, 22), WATER_Y - 4, 36, 1.4)


func _forest() -> void:
	for distance: int in range(74, 283, 9):
		var sample: Dictionary = Baker.sample_at(_data, distance)
		var p: Vector3 = Baker.vector(sample.position)
		var right: Vector3 = Baker.vector(sample.tangent).cross(Vector3.UP).normalized()
		for side: float in [-1.0, 1.0]:
			var at: Vector3 = p + right * side * (13.3 + 2.1 * sin(distance * 0.21))
			_kit._tree(at - Vector3.UP * 0.2, 1.05 + 0.2 * sin(distance * 0.4), distance)
			for shrub: int in 2:
				var shrub_at: Vector3 = p + right * side * (10.1 + shrub * 2.0) + Vector3.UP * 0.4
				_kit._place(_kit._leaf_mesh(), _kit._materials["leaf%d" % ((distance + shrub) % 4)], _kit._pose(shrub_at, Vector3(1.7, 0.65, 1.2)), false)
	for distance: int in [15, 38, 306, 334, 461, 494, 706, 731, 758]:
		var sample: Dictionary = Baker.sample_at(_data, distance)
		var right: Vector3 = Baker.vector(sample.tangent).cross(Vector3.UP).normalized()
		_kit._tree(Baker.vector(sample.position) - right * 12.0, 1.35, distance)


func _distance_landscape() -> void:
	_kit._island("InnerWoodedUpland", Vector3(0, 7, -27), Vector2(56, 46), WATER_Y - 2, 52, 0.8)
	for i: int in 14:
		var angle: float = TAU * i / 14.0
		_kit._tree(Vector3(cos(angle) * 43, 7, -27 + sin(angle) * 32), 1.25 + (i % 3) * 0.2, i)
	for index: int in 9:
		var angle: float = TAU * index / 9.0
		var at := Vector3(cos(angle) * 460.0, WATER_Y - 6, sin(angle) * 450.0)
		_kit._place(_kit._mountain_mesh(), _kit._materials.terrain, _kit._pose(at, Vector3(120 + index % 3 * 12, 67 + index % 4 * 8, 118), Basis(Vector3.UP, angle)), false)


func _start_landmarks() -> void:
	var start: Dictionary = _data.gates[0]
	var p: Vector3 = Baker.vector(start.position)
	var forward: Vector3 = Baker.vector(start.forward).slide(Vector3.UP).normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	for side: float in [-1.0, 1.0]:
		var base: Vector3 = p + right * side * 9.3
		_kit._tower(base, 0.75, 3.8, 1.4)
		_kit._banner(base + Vector3.UP * 2.1 - forward * 0.8, 0.65)
	for row: int in 2:
		for index: int in 14:
			var at: Vector3 = p + right * (-6.5 + index) + forward * (row * 0.6) + Vector3.UP * 0.027
			_kit._box(at, Vector3(0.92, 0.024, 0.58), _kit._materials.white if (index + row) % 2 == 0 else _kit._materials.window, Basis(right, Vector3.UP, -forward))
