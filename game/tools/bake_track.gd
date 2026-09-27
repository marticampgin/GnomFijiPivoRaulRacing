extends SceneTree

const Baker = preload("res://track/track_baker.gd")


func _initialize() -> void:
	var source: Resource = load("res://track/castle_waterfalls.tres")
	var result: Dictionary = Baker.bake(source)
	if not result.errors.is_empty():
		for message: String in result.errors:
			push_error(message)
		quit(1)
		return
	var output: String = "res://track/baked/castle_waterfalls.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://track/baked"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../shared"))
	if not _write(output, result.data) or not _write("res://../shared/track-manifest.json", Baker.compact(result.data)):
		quit(1)
		return
	_write_overview(result.data)
	print("TRACK_BAKE ", JSON.stringify({"path": output, "simulation_hash": result.data.simulation_hash, "length": result.data.length, "samples": result.data.samples.size()}))
	quit(0)


func _write(path: String, data: Dictionary) -> bool:
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write " + path)
		return false
	file.store_string(JSON.stringify(data, "", true, true) + "\n")
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) == OK


func _write_overview(data: Dictionary) -> void:
	var colors: Array[String] = ["#c39b19", "#2d8a61", "#258ba3", "#c76655"]
	var bounds: Dictionary = data.minimap.bounds
	var scale: float = 2.75
	var offset := Vector2(140.0 - float(bounds.min_x) * scale, 155.0 - float(bounds.min_z) * scale)
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="960" viewBox="0 0 1280 960"><rect width="1280" height="960" fill="#f8faf9"/><g font-family="Arial,sans-serif" fill="#172b2a"><text x="64" y="64" font-size="32" font-weight="700">Castle / Waterfall Route</text><text x="64" y="98" font-size="17">GREYBOX PLAN - 798 m - 14 m road - elevation 0 to 16 m - clockwise</text>'
	var line: String = ""
	for sample: Dictionary in data.samples:
		var p := Vector2(float(sample.position[0]), float(sample.position[2])) * scale + offset
		line += "%.2f,%.2f " % [p.x, p.y]
	svg += '<polyline points="%s" fill="none" stroke="#c8d3d0" stroke-width="40" stroke-linejoin="round"/><polyline points="%s" fill="none" stroke="#edf1ef" stroke-width="31" stroke-linejoin="round"/>' % [line, line]
	for gate: Dictionary in data.gates:
		var p := Vector2(float(gate.position[0]), float(gate.position[2])) * scale + offset
		svg += '<circle cx="%.2f" cy="%.2f" r="9" fill="#526c66"/><text x="%.2f" y="%.2f" font-size="12" fill="white" text-anchor="middle">%d</text>' % [p.x, p.y, p.x, p.y + 4, int(gate.id)]
	for index: int in data.camera_anchors.size():
		var anchor: Dictionary = data.camera_anchors[index]
		var p := Vector2(float(anchor.position[0]), float(anchor.position[2])) * scale + offset
		svg += '<circle cx="%.2f" cy="%.2f" r="19" fill="%s"/><text x="%.2f" y="%.2f" font-size="17" fill="white" text-anchor="middle">%d</text>' % [p.x, p.y, colors[index], p.x, p.y + 6, index + 1]
	for slot: Dictionary in data.starts:
		var p := Vector2(float(slot.position[0]), float(slot.position[2])) * scale + offset
		svg += '<rect x="%.2f" y="%.2f" width="7" height="7" fill="#28463e"/>' % [p.x - 3.5, p.y - 3.5]
	var labels: Array[String] = ["1. Stone start / warm-up", "2. Forest S-bend / descent", "3. Lake / waterfall reveal", "4. Bridge climb / castle view"]
	for index: int in 4:
		var y: int = 210 + index * 116
		svg += '<rect x="900" y="%d" width="6" height="56" fill="%s"/><text x="920" y="%d" font-size="17" font-weight="700">%s</text><text x="920" y="%d" font-size="15">Camera anchor: %d m</text>' % [y - 20, colors[index], y, labels[index], y + 28, roundi(float(data.camera_anchors[index].s))]
	svg += '<text x="64" y="910" font-size="16">Review route direction before detailed scenery. Numbered small dots are directed gates, not pickups.</text></g></svg>'
	var file: FileAccess = FileAccess.open("res://track/baked/route-overview.svg", FileAccess.WRITE)
	if file != null:
		file.store_string(svg + "\n")
