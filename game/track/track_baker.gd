class_name TrackBaker
extends RefCounted

const BAKE_VERSION: int = 1


static func bake(definition: Resource) -> Dictionary:
	var errors: PackedStringArray = definition.validation_errors()
	if not errors.is_empty():
		return {"errors": errors}
	var source_length: float = definition.route.get_baked_length()
	if source_length < 200.0 or source_length > 5000.0:
		return {"errors": PackedStringArray(["route: length must be between 200 and 5000 metres"])}
	var segment_count: int = ceili(source_length / definition.sample_spacing)
	var positions: Array[Vector3] = []
	for index: int in segment_count:
		positions.append(definition.route.sample_baked(source_length * index / segment_count, true))
	positions.append(positions[0])
	var samples: Array = []
	var length: float = 0.0
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for index: int in segment_count + 1:
		var p: Vector3 = positions[index]
		var before: Vector3 = positions[posmod(index - 1, segment_count)]
		var after: Vector3 = positions[(index + 1) % segment_count]
		var forward: Vector3 = (after - before).normalized()
		if index > 0:
			var distance: float = p.distance_to(positions[index - 1])
			if distance < 0.01:
				errors.append("sample[%d]: zero-length segment" % index)
			length += distance
		if not p.is_finite() or not forward.is_finite() or absf(forward.y) > 0.22:
			errors.append("sample[%d]: non-finite geometry or slope exceeds 22 percent" % index)
		minimum = minimum.min(p)
		maximum = maximum.max(p)
		samples.append({"position": vec(p), "s": rounded(length), "tangent": vec(forward), "up": [0, 1, 0], "width": definition.road_width, "surface_id": definition.surface_id})
	# Reject same-level crossings and unsupported stacked topology at authoring time.
	for a: int in range(0, segment_count, 3):
		for b: int in range(a + 3, segment_count, 3):
			var separation: float = float(samples[b].s) - float(samples[a].s)
			if minf(separation, length - separation) < definition.road_width * 2.0:
				continue
			if positions[a].distance_to(positions[b]) < definition.road_width + 1.0:
				errors.append("route[%d,%d]: overlapping non-neighbour road corridors" % [a, b])
				break
	var data: Dictionary = {
		"track_id": definition.track_id, "schema_version": definition.schema_version,
		"simulation_revision": definition.simulation_revision, "bake_version": BAKE_VERSION,
		"length": rounded(length), "samples": samples, "gates": [], "starts": [], "recovery": [],
		"corridor": {"shoulder": definition.shoulder_tolerance, "min_height": -2.0, "max_height": 4.0, "cap_extension": 0.2},
		"surfaces": [{"id": definition.surface_id, "friction": 1.0}],
		"bounds": {"min": vec(minimum - Vector3(12, 10, 12)), "max": vec(maximum + Vector3(12, 12, 12))},
		"collision": {"road_faces": [], "road_backface": false, "barriers": []}, "guides": [], "camera_anchors": [],
	}
	for index: int in segment_count:
		var a: Dictionary = samples[index]
		var b: Dictionary = samples[index + 1]
		var start: Vector3 = vector(a.position)
		var finish: Vector3 = vector(b.position)
		var right_a: Vector3 = vector(a.tangent).cross(Vector3.UP).normalized()
		var right_b: Vector3 = vector(b.tangent).cross(Vector3.UP).normalized()
		var half_width: float = definition.road_width * 0.5
		var left_a: Vector3 = start - right_a * half_width
		var right_edge_a: Vector3 = start + right_a * half_width
		var left_b: Vector3 = finish - right_b * half_width
		var right_edge_b: Vector3 = finish + right_b * half_width
		for vertex: Vector3 in [left_a, left_b, right_edge_a, left_b, right_edge_b, right_edge_a]:
			data.collision.road_faces.append(vec(vertex))
		for side: float in [-1.0, 1.0]:
			var edge_a: Vector3 = start + right_a * side * (half_width + 0.25)
			var edge_b: Vector3 = finish + right_b * side * (half_width + 0.25)
			data.collision.barriers.append({"position": vec((edge_a + edge_b) * 0.5 + Vector3.UP * 0.65), "forward": vec((edge_b - edge_a).normalized()), "size": [0.5, 1.3, rounded(edge_a.distance_to(edge_b) + 0.12)]})
		var turn: float = vector(a.tangent).signed_angle_to(vector(b.tangent), Vector3.UP)
		data.guides.append({"s": a.s, "position": a.position, "direction": a.tangent, "width": a.width, "curvature": rounded(turn / start.distance_to(finish)), "suggested_speed": 24.0 if absf(turn) > 0.035 else 30.0})
	for index: int in definition.gate_count:
		var s: float = length * index / definition.gate_count
		var sample: Dictionary = sample_at(data, s)
		data.gates.append({"id": index, "s": rounded(s), "position": sample.position, "forward": sample.tangent, "half_width": definition.road_width * 0.5 + definition.shoulder_tolerance, "min_height": -0.4, "max_height": 3.5})
		var anchor: Dictionary = sample_at(data, s + 3.0)
		data.recovery.append({"confirmed_gate": index, "s": anchor.s, "position": vec(vector(anchor.position) + Vector3.UP * 0.65), "forward": anchor.tangent})
	for slot: int in 10:
		var start_sample: Dictionary = sample_at(data, length - 6.0 - (slot / 2) * 5.0)
		var lane: float = -2.7 if slot % 2 == 0 else 2.7
		var right: Vector3 = vector(start_sample.tangent).cross(Vector3.UP).normalized()
		data.starts.append({"slot": slot, "s": start_sample.s, "position": vec(vector(start_sample.position) + right * lane + Vector3.UP * 0.65), "forward": start_sample.tangent})
	var initial: Dictionary = sample_at(data, length - 6.0)
	data.recovery.push_front({"confirmed_gate": -1, "s": initial.s, "position": vec(vector(initial.position) + Vector3.UP * 0.65), "forward": initial.tangent})
	data.shortcuts = []
	if definition.shortcut_enabled:
		_bake_shortcut(data, definition.shortcut_width)
	data.kill_volumes = [{"id": "world-floor", "min": vec(minimum - Vector3(30, 100, 30)), "max": vec(Vector3(maximum.x + 30, minimum.y - 6, maximum.z + 30))}]
	for index: int in 4:
		var anchor: Dictionary = sample_at(data, length * [0.02, 0.23, 0.50, 0.77][index])
		data.camera_anchors.append({"id": ["stone-start", "forest", "lake-waterfall", "bridge-castle"][index], "s": anchor.s, "position": anchor.position, "forward": anchor.tangent})
	var polyline: Array = []
	for sample: Dictionary in samples:
		polyline.append([sample.position[0], sample.position[2]])
	data.minimap = {"polyline": polyline, "bounds": {"min_x": rounded(minimum.x), "max_x": rounded(maximum.x), "min_z": rounded(minimum.z), "max_z": rounded(maximum.z)}, "world_to_map": {"scale_x": rounded(1.0 / (maximum.x - minimum.x)), "scale_z": rounded(1.0 / (maximum.z - minimum.z)), "offset_x": rounded(-minimum.x / (maximum.x - minimum.x)), "offset_z": rounded(-minimum.z / (maximum.z - minimum.z))}, "start": polyline[0]}
	data.minimap.shortcuts = []
	for shortcut: Dictionary in data.shortcuts:
		var line: Array = []
		for sample: Dictionary in shortcut.samples:
			line.append([sample.position[0], sample.position[2]])
		data.minimap.shortcuts.append(line)
	if not errors.is_empty():
		return {"errors": errors}
	# Scenery and presentation metadata are deliberately outside this payload.
	data.simulation_hash = simulation_hash(data)
	data.art_revision = definition.art_revision
	return {"data": data, "errors": PackedStringArray()}


static func _bake_shortcut(data: Dictionary, width: float) -> void:
	# The branch is wholly inside one ordered checkpoint interval.
	var from_s: float = float(data.gates[4].s) + 2.0
	var to_s: float = float(data.gates[5].s) - 2.0
	var start: Vector3 = vector(sample_at(data, from_s).position)
	var finish: Vector3 = vector(sample_at(data, to_s).position)
	var forward: Vector3 = (finish - start).normalized()
	var side: Vector3 = forward.cross(Vector3.UP).normalized()
	var samples: Array = []
	var count: int = ceili(start.distance_to(finish) / 2.0)
	for index: int in count + 1:
		var weight: float = float(index) / count
		samples.append({"position": vec(start.lerp(finish, weight)), "s": rounded(lerpf(from_s, to_s, weight)), "tangent": vec(forward), "width": width})
	data.shortcuts.append({"id": "forest-cut", "from_gate": 4, "to_gate": 5, "from_s": from_s, "to_s": to_s, "length": rounded(start.distance_to(finish)), "width": width, "samples": samples})
	for index: int in count:
		var a: Vector3 = vector(samples[index].position)
		var b: Vector3 = vector(samples[index + 1].position)
		for vertex: Vector3 in [a - side * width * 0.5, b - side * width * 0.5, a + side * width * 0.5, b - side * width * 0.5, b + side * width * 0.5, a + side * width * 0.5]:
			data.collision.road_faces.append(vec(vertex))
	var barriers: Array = []
	for barrier: Dictionary in data.collision.barriers:
		if not shortcut_contains(data, vector(barrier.position), 1.8):
			barriers.append(barrier)
	data.collision.barriers = barriers


static func shortcut_contains(data: Dictionary, point: Vector3, margin: float = 0.0) -> bool:
	for branch: Dictionary in data.get("shortcuts", []):
		var a: Vector3 = vector(branch.samples[0].position)
		var b: Vector3 = vector(branch.samples[-1].position)
		var edge: Vector3 = (b - a).slide(Vector3.UP)
		var t: float = clampf((point - a).dot(edge) / edge.length_squared(), 0.0, 1.0)
		if (point - a.lerp(b, t)).slide(Vector3.UP).length() <= float(branch.width) * 0.5 + margin:
			return true
	return false


static func sample_at(data: Dictionary, offset: float) -> Dictionary:
	var s: float = fposmod(offset, float(data.length))
	var samples: Array = data.samples
	var low: int = 0
	var high: int = samples.size() - 1
	while high - low > 1:
		var middle: int = (low + high) / 2
		if float(samples[middle].s) <= s:
			low = middle
		else:
			high = middle
	var a: Dictionary = samples[low]
	var b: Dictionary = samples[high]
	var weight: float = (s - float(a.s)) / (float(b.s) - float(a.s))
	return {"s": rounded(s), "position": vec(vector(a.position).lerp(vector(b.position), weight)), "tangent": vec(vector(a.tangent).lerp(vector(b.tangent), weight).normalized()), "width": lerpf(float(a.width), float(b.width), weight)}


static func compact(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["track_id", "schema_version", "simulation_revision", "simulation_hash", "art_revision", "length", "minimap"]:
		result[key] = data[key]
	return result


static func vec(value: Vector3) -> Array:
	return [rounded(value.x), rounded(value.y), rounded(value.z)]


static func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func rounded(value: float) -> float:
	return snappedf(value, 0.000001)


static func simulation_hash(data: Dictionary) -> String:
	var simulation: Dictionary = data.duplicate(true)
	for key: String in ["camera_anchors", "minimap", "guides", "art_revision", "simulation_hash"]:
		simulation.erase(key)
	return JSON.stringify(_numeric_canonical(simulation), "", true, true).sha256_text()


static func _numeric_canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _numeric_canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_numeric_canonical(item))
		return result
	# Godot's JSON parser may round the final binary digits. Hash the declared
	# one-micrometre bake precision, not incidental floating-point text.
	return roundi(float(value) * 1000000.0) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else value


static func package_errors(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in ["samples", "gates", "starts", "recovery", "guides", "kill_volumes", "camera_anchors"]:
		if not data.get(key) is Array or data[key].is_empty():
			errors.append("package.%s: nonempty array required" % key)
	for key: String in ["collision", "corridor", "bounds", "minimap"]:
		if not data.get(key) is Dictionary:
			errors.append("package.%s: dictionary required" % key)
	if data.get("track_id") != "castle-waterfalls" or data.get("schema_version") != 1 or data.get("bake_version") != BAKE_VERSION:
		errors.append("package.identity: unsupported track/schema/bake version")
	if not _finite_number(data.get("length")) or float(data.length) < 200.0:
		errors.append("package.length: invalid route length")
	for key: String in ["simulation_revision", "art_revision"]:
		if not _finite_number(data.get(key)) or float(data[key]) < 1.0:
			errors.append("package.%s: invalid revision" % key)
	if not data.get("simulation_hash") is String or str(data.simulation_hash).length() != 64 or not str(data.simulation_hash).is_valid_hex_number(false):
		errors.append("package.simulation_hash: SHA256 required")
	if not errors.is_empty():
		return errors
	if data.starts.size() != 10 or data.gates.size() < 4 or data.recovery.size() != data.gates.size() + 1:
		errors.append("package.anchors: ten starts and ordered gate-linked recovery required")
	var previous: float = -1.0
	for index: int in data.samples.size():
		var sample: Variant = data.samples[index]
		if not sample is Dictionary or not _vector_valid(sample.get("position")) or not _vector_valid(sample.get("tangent")) or not _finite_number(sample.get("s")) or not _finite_number(sample.get("width")):
			errors.append("package.samples[%d]: invalid numeric sample" % index)
			continue
		if float(sample.s) <= previous or float(sample.width) < 10.0 or vector(sample.tangent).length() < 0.9:
			errors.append("package.samples[%d]: non-monotonic length/invalid width or tangent" % index)
		previous = float(sample.s)
	for key: String in ["gates", "starts", "recovery"]:
		for index: int in data[key].size():
			var item: Variant = data[key][index]
			if not item is Dictionary or not _vector_valid(item.get("position")) or not _vector_valid(item.get("forward")) or not _finite_number(item.get("s")):
				errors.append("package.%s[%d]: invalid anchor" % [key, index])
				continue
			if key == "gates" and (item.get("id") != index or not _finite_number(item.get("half_width")) or not _finite_number(item.get("min_height")) or not _finite_number(item.get("max_height"))):
				errors.append("package.gates[%d]: invalid ordered gate" % index)
			if key == "starts" and item.get("slot") != index:
				errors.append("package.starts[%d]: invalid slot" % index)
			if key == "recovery" and item.get("confirmed_gate") != index - 1:
				errors.append("package.recovery[%d]: invalid checkpoint link" % index)
	if not data.collision.get("road_faces") is Array or data.collision.road_faces.size() % 3 != 0 or data.collision.road_faces.is_empty() or not data.collision.get("barriers") is Array:
		errors.append("package.collision: invalid face/barrier arrays")
	else:
		for point: Variant in data.collision.road_faces:
			if not _vector_valid(point):
				errors.append("package.collision: non-finite vertex")
				break
		for barrier: Variant in data.collision.barriers:
			if not barrier is Dictionary or not _vector_valid(barrier.get("position")) or not _vector_valid(barrier.get("forward")) or not _vector_valid(barrier.get("size")):
				errors.append("package.collision: malformed barrier")
				break
	for key: String in ["shoulder", "min_height", "max_height", "cap_extension"]:
		if not _finite_number(data.corridor.get(key)):
			errors.append("package.corridor.%s: invalid value" % key)
	for key: String in ["min", "max"]:
		if not _vector_valid(data.bounds.get(key)):
			errors.append("package.bounds.%s: invalid value" % key)
	for volume: Variant in data.kill_volumes:
		if not volume is Dictionary or not _vector_valid(volume.get("min")) or not _vector_valid(volume.get("max")):
			errors.append("package.kill_volumes: invalid bounds")
	if not data.get("shortcuts", []) is Array:
		errors.append("package.shortcuts: array required")
	else:
		for branch: Variant in data.get("shortcuts", []):
			if not branch is Dictionary or not branch.get("samples") is Array or branch.samples.size() < 2 or not _finite_number(branch.get("width")) or not _finite_number(branch.get("length")) or not _finite_number(branch.get("from_s")) or not _finite_number(branch.get("to_s")):
				errors.append("package.shortcuts: invalid branch")
				continue
			if branch.get("from_gate") != 4 or branch.get("to_gate") != 5 or data.gates.size() < 6 or float(branch.width) < 4.0 or float(branch.width) > 6.0 or float(branch.length) <= 0.0 or float(branch.length) >= float(branch.to_s) - float(branch.from_s):
				errors.append("package.shortcuts: unsupported or non-shorter branch")
				continue
			if float(branch.from_s) <= float(data.gates[4].s) or float(branch.to_s) >= float(data.gates[5].s):
				errors.append("package.shortcuts: branch may not bypass checkpoints")
			var previous_s: float = float(branch.from_s) - 0.01
			for sample: Variant in branch.samples:
				if not sample is Dictionary or not _vector_valid(sample.get("position")) or not _vector_valid(sample.get("tangent")) or not _finite_number(sample.get("s")) or not _finite_number(sample.get("width")):
					errors.append("package.shortcuts: invalid sample")
					continue
				if float(sample.s) <= previous_s or float(sample.width) != float(branch.width):
					errors.append("package.shortcuts: invalid sample progress or width")
				previous_s = float(sample.s)
	if errors.is_empty() and simulation_hash(data) != data.simulation_hash:
		errors.append("package.simulation_hash: baked simulation payload was modified")
	return errors


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _vector_valid(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _finite_number(value[0]) and _finite_number(value[1]) and _finite_number(value[2])
