class_name TrackDefinition
extends Resource

@export var track_id: String = "castle-waterfalls"
@export var schema_version: int = 1
@export var simulation_revision: int = 1
@export var art_revision: int = 1
@export var route: Curve3D
@export var road_width: float = 14.0
@export var sample_spacing: float = 2.0
@export var gate_count: int = 16
@export var shoulder_tolerance: float = 0.8
@export var surface_id: String = "stone-dry"
@export var shortcut_enabled: bool = true
@export var shortcut_width: float = 4.5


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(shortcut_width) or shortcut_width < 4.0 or shortcut_width > 6.0:
		errors.append("shortcut_width: must be between 4 and 6 metres")
	if track_id.is_empty() or schema_version != 1 or simulation_revision < 1 or art_revision < 1:
		errors.append("identity: invalid id or unsupported version")
	if not is_finite(road_width) or road_width < 10.0 or road_width > 24.0:
		errors.append("road_width: must be finite and between 10 and 24 metres")
	if not is_finite(sample_spacing) or sample_spacing < 0.5 or sample_spacing > 3.0:
		errors.append("sample_spacing: must be between 0.5 and 3 metres")
	if gate_count < 4 or gate_count > 64:
		errors.append("gate_count: must be between 4 and 64")
	if shortcut_enabled and gate_count < 6:
		errors.append("shortcut: requires checkpoint interval 4 to 5")
	if not is_finite(shoulder_tolerance) or shoulder_tolerance < 0.0 or shoulder_tolerance > 2.0:
		errors.append("shoulder_tolerance: must be between 0 and 2 metres")
	if surface_id != "stone-dry":
		errors.append("surface_id: unsupported gameplay surface")
	if route == null or route.point_count < 5:
		errors.append("route: a closed Curve3D with at least four segments is required")
		return errors
	for index: int in route.point_count:
		if not route.get_point_position(index).is_finite() or not route.get_point_in(index).is_finite() or not route.get_point_out(index).is_finite():
			errors.append("route[%d]: non-finite coordinate or handle" % index)
		if index > 0 and route.get_point_position(index).distance_to(route.get_point_position(index - 1)) < 0.1:
			errors.append("route[%d]: zero-length control segment" % index)
	if route.get_point_position(0).distance_to(route.get_point_position(route.point_count - 1)) > 0.001:
		errors.append("route: last point must repeat the first point")
	return errors
