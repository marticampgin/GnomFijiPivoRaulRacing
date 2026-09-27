class_name RouteProgress
extends RefCounted

const Baker = preload("res://track/track_baker.gd")

static var _prism_cache: Dictionary = {}
static var _spatial_cache: Dictionary = {}
static var _segment_cache: Dictionary = {}
const CELL_SIZE: float = 24.0


static func initial_state() -> Dictionary:
	return {"started": false, "expected_gate": 0, "confirmed_gate": -1, "lap": 0, "finished": false, "interval_valid": true, "discontinuity": false}


static func advance(data: Dictionary, state: Dictionary, previous: Vector3, current: Vector3, discontinuity: bool = false, total_laps: int = 3) -> Array:
	var events: Array = []
	if bool(state.finished):
		return events
	if discontinuity or bool(state.get("discontinuity", false)):
		state.discontinuity = false
		return events
	if not previous.is_finite() or not current.is_finite():
		state.interval_valid = false
		return events
	if not sweep_in_corridor(data, previous, current):
		state.interval_valid = false
	if not bool(state.interval_valid):
		return events
	var last_fraction: float = -1.0
	for unused: int in data.gates.size():
		var gate: Dictionary = data.gates[int(state.expected_gate)]
		var fraction: float = crossing_fraction(gate, previous, current)
		if fraction < 0.0 or fraction <= last_fraction:
			break
		last_fraction = fraction
		var index: int = int(gate.id)
		state.confirmed_gate = index
		state.expected_gate = (index + 1) % data.gates.size()
		events.append({"type": "checkpoint", "gate": index})
		if index == 0:
			if not bool(state.started):
				state.started = true
			else:
				state.lap = int(state.lap) + 1
				events.append({"type": "lap", "lap": state.lap})
				if int(state.lap) >= total_laps:
					state.finished = true
					events.append({"type": "finish"})
					break
	return events


static func crossing_fraction(gate: Dictionary, previous: Vector3, current: Vector3) -> float:
	var center: Vector3 = Baker.vector(gate.position)
	var forward: Vector3 = Baker.vector(gate.forward).normalized()
	var before: float = (previous - center).dot(forward)
	var after: float = (current - center).dot(forward)
	if before > 0.0 or after <= 0.0 or after - before <= 0.000001:
		return -1.0
	var fraction: float = -before / (after - before)
	var offset: Vector3 = previous.lerp(current, fraction) - center
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var local_up: Vector3 = right.cross(forward).normalized()
	if absf(offset.dot(right)) > float(gate.half_width) or offset.dot(local_up) < float(gate.min_height) or offset.dot(local_up) > float(gate.max_height):
		return -1.0
	return fraction


static func project(data: Dictionary, location: Vector3, from_s: float, to_s: float) -> Dictionary:
	var best: Dictionary = {"distance": INF, "s": from_s, "position": Vector3.ZERO, "lateral": INF, "height": INF, "width": 0.0}
	if not location.is_finite():
		return best
	var segments: Array = _segments(data)
	var indices: Array = []
	if from_s <= 0.0 and to_s >= float(data.length):
		indices = _spatial_indices(data, location, location)
	else:
		for index: int in range(_segment_at(data, from_s), _segment_at(data, to_s) + 1):
			indices.append(index)
		for index: int in range(data.samples.size() - 1, segments.size()):
			indices.append(index)
	for index: int in indices:
		var a: Dictionary = segments[index][0]
		var b: Dictionary = segments[index][1]
		if float(b.s) < from_s or float(a.s) > to_s:
			continue
		var start: Vector3 = Baker.vector(a.position)
		var finish: Vector3 = Baker.vector(b.position)
		var edge: Vector3 = finish - start
		var minimum: float = clampf((from_s - float(a.s)) / (float(b.s) - float(a.s)), 0.0, 1.0)
		var maximum: float = clampf((to_s - float(a.s)) / (float(b.s) - float(a.s)), 0.0, 1.0)
		var fraction: float = clampf((location - start).dot(edge) / edge.length_squared(), minimum, maximum)
		var p: Vector3 = start + edge * fraction
		var offset: Vector3 = location - p
		var distance: float = offset.length()
		if distance < float(best.distance):
			var forward: Vector3 = edge.normalized()
			var right: Vector3 = forward.cross(Vector3.UP).normalized()
			var local_up: Vector3 = right.cross(forward).normalized()
			best = {"distance": distance, "s": lerpf(float(a.s), float(b.s), fraction), "position": p, "lateral": offset.dot(right), "height": offset.dot(local_up), "width": lerpf(float(a.width), float(b.width), fraction)}
	return best


static func standings_distance(data: Dictionary, state: Dictionary, location: Vector3) -> float:
	if bool(state.finished):
		return float(state.lap) * float(data.length)
	var confirmed: int = int(state.confirmed_gate)
	if confirmed < 0:
		return float(project(data, location, float(data.length) - 40.0, float(data.length)).s) - float(data.length)
	var from_s: float = float(data.gates[confirmed].s)
	var next: int = int(state.expected_gate)
	var to_s: float = float(data.length) if next == 0 else float(data.gates[next].s)
	return float(state.lap) * float(data.length) + float(project(data, location, from_s, to_s).s)


static func in_corridor(data: Dictionary, location: Vector3) -> bool:
	return sweep_in_corridor(data, location, location)


static func sweep_in_corridor(data: Dictionary, previous: Vector3, current: Vector3) -> bool:
	if not previous.is_finite() or not current.is_finite():
		return false
	if previous.distance_to(current) > float(data.length):
		return false
	var covered: Array[Vector2] = []
	# Clip the complete movement segment against a union of corridor prisms.
	# Fixed-distance sampling would miss a sufficiently short excursion.
	var prisms: Array = _prisms(data)
	for index: int in _spatial_indices(data, previous, current):
		var prism: Dictionary = prisms[index]
		var relative: Vector3 = previous - prism.origin
		var movement: Vector3 = current - previous
		var interval := Vector2(0.0, 1.0)
		for axis: int in 3:
			var direction: Vector3 = prism.axes[axis]
			var start: float = relative.dot(direction)
			var delta: float = movement.dot(direction)
			var minimum: float = prism.minimum[axis]
			var maximum: float = prism.maximum[axis]
			if absf(delta) < 0.000001:
				if start < minimum or start > maximum:
					interval = Vector2(1, 0)
					break
			else:
				var a: float = (minimum - start) / delta
				var b: float = (maximum - start) / delta
				interval.x = maxf(interval.x, minf(a, b))
				interval.y = minf(interval.y, maxf(a, b))
				if interval.x > interval.y:
					break
		if interval.x <= interval.y:
			if interval.x <= 0.0 and interval.y >= 1.0:
				return true
			covered.append(interval)
	covered.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var extent: float = 0.0
	for interval: Vector2 in covered:
		if interval.x > extent + 0.000001:
			return false
		extent = maxf(extent, interval.y)
	return extent >= 1.0


static func _prisms(data: Dictionary) -> Array:
	var key: String = str(data.simulation_hash)
	if _prism_cache.has(key):
		return _prism_cache[key]
	var result: Array = []
	for segment: Array in _segments(data):
		var a: Dictionary = segment[0]
		var b: Dictionary = segment[1]
		var origin: Vector3 = Baker.vector(a.position)
		var edge: Vector3 = Baker.vector(b.position) - origin
		var forward: Vector3 = edge.normalized()
		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		var up: Vector3 = right.cross(forward).normalized()
		var half_width: float = minf(float(a.width), float(b.width)) * 0.5 + float(data.corridor.shoulder)
		result.append({"origin": origin, "axes": [forward, right, up], "minimum": [-float(data.corridor.cap_extension), -half_width, float(data.corridor.min_height)], "maximum": [edge.length() + float(data.corridor.cap_extension), half_width, float(data.corridor.max_height)]})
	_prism_cache[key] = result
	return result


static func _segment_at(data: Dictionary, s: float) -> int:
	var low: int = 0
	var high: int = data.samples.size() - 1
	while high - low > 1:
		var middle: int = (low + high) / 2
		if float(data.samples[middle].s) <= s:
			low = middle
		else:
			high = middle
	return mini(low, data.samples.size() - 2)


static func _segments(data: Dictionary) -> Array:
	var key: String = str(data.simulation_hash)
	if _segment_cache.has(key):
		return _segment_cache[key]
	var segments: Array = []
	var routes: Array = [data.samples]
	for branch: Dictionary in data.get("shortcuts", []):
		routes.append(branch.samples)
	for samples: Array in routes:
		for index: int in samples.size() - 1:
			segments.append([samples[index], samples[index + 1]])
	_segment_cache[key] = segments
	return segments


static func _spatial_indices(data: Dictionary, start: Vector3, finish: Vector3) -> Array:
	var key: String = str(data.simulation_hash)
	if not _spatial_cache.has(key):
		var grid: Dictionary = {}
		var segments: Array = _segments(data)
		for index: int in segments.size():
			var a: Dictionary = segments[index][0]
			var b: Dictionary = segments[index][1]
			var margin: float = maxf(float(a.width), float(b.width)) * 0.5 + 6.0
			var minimum: Vector3 = Baker.vector(a.position).min(Baker.vector(b.position)) - Vector3(margin, 0, margin)
			var maximum: Vector3 = Baker.vector(a.position).max(Baker.vector(b.position)) + Vector3(margin, 0, margin)
			for x: int in range(floori(minimum.x / CELL_SIZE), floori(maximum.x / CELL_SIZE) + 1):
				for z: int in range(floori(minimum.z / CELL_SIZE), floori(maximum.z / CELL_SIZE) + 1):
					var cell := Vector2i(x, z)
					if not grid.has(cell):
						grid[cell] = []
					grid[cell].append(index)
		_spatial_cache[key] = grid
	var grid: Dictionary = _spatial_cache[key]
	var minimum: Vector3 = start.min(finish)
	var maximum: Vector3 = start.max(finish)
	var first := Vector2i(floori(minimum.x / CELL_SIZE), floori(minimum.z / CELL_SIZE))
	var last := Vector2i(floori(maximum.x / CELL_SIZE), floori(maximum.z / CELL_SIZE))
	if first == last:
		return grid.get(first, [])
	var unique: Dictionary = {}
	for x: int in range(first.x, last.x + 1):
		for z: int in range(first.y, last.y + 1):
			for index: int in grid.get(Vector2i(x, z), []):
				unique[index] = true
	return unique.keys()


static func recovery_anchor(data: Dictionary, state: Dictionary) -> Dictionary:
	return data.recovery[int(state.confirmed_gate) + 1]


static func recover(state: Dictionary) -> void:
	state.interval_valid = true
	state.discontinuity = true


static func needs_recovery(data: Dictionary, location: Vector3) -> bool:
	if not location.is_finite():
		return true
	var minimum: Vector3 = Baker.vector(data.bounds.min)
	var maximum: Vector3 = Baker.vector(data.bounds.max)
	if location.x < minimum.x or location.y < minimum.y or location.z < minimum.z or location.x > maximum.x or location.y > maximum.y or location.z > maximum.z:
		return true
	for volume: Dictionary in data.kill_volumes:
		var start: Vector3 = Baker.vector(volume.min)
		var end: Vector3 = Baker.vector(volume.max)
		if location.x >= start.x and location.x <= end.x and location.y >= start.y and location.y <= end.y and location.z >= start.z and location.z <= end.z:
			return true
	var nearest: Dictionary = project(data, location, 0.0, float(data.length))
	return float(nearest.height) < -3.0 or absf(float(nearest.lateral)) > float(nearest.width) * 0.5 + 5.0
