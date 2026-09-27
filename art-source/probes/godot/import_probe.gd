extends SceneTree

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Usage: Godot --headless --path art-source/probes/godot --script import_probe.gd -- /absolute/export-probe.glb")
		quit(2)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(arguments[0], state)
	_expect(error == OK, "self-contained GLB parsed without Blender")
	if error != OK:
		quit(1)
		return
	var scene := document.generate_scene(state)
	_expect(scene != null, "scene generated")
	if scene == null:
		quit(1)
		return
	root.add_child(scene)
	for name: String in ["TealSample", "BrassSample", "RubberSample", "CrystalSample", "UVSample"]:
		var mesh_node := scene.find_child(name, true, false) as MeshInstance3D
		_expect(mesh_node != null, "%s node preserved" % name)
		if mesh_node == null:
			continue
		_expect(mesh_node.scale.is_equal_approx(Vector3.ONE), "%s unit transform" % name)
		_expect(mesh_node.mesh.get_aabb().size.is_equal_approx(Vector3.ONE * 0.4), "%s meter dimensions" % name)
		var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
		_expect(arrays[Mesh.ARRAY_TEX_UV] != null and arrays[Mesh.ARRAY_TEX_UV].size() > 0, "%s UVs preserved" % name)
		_expect(arrays[Mesh.ARRAY_NORMAL] != null and arrays[Mesh.ARRAY_NORMAL].size() > 0, "%s normals preserved" % name)
		var material := mesh_node.get_active_material(0) as StandardMaterial3D
		_expect(material != null, "%s material imported" % name)
		if material == null:
			continue
		if name == "BrassSample":
			_expect(material.metallic > 0.8, "brass metallic preserved")
		if name == "RubberSample":
			_expect(material.roughness > 0.8 and material.metallic < 0.1, "rubber roughness preserved")
		if name == "CrystalSample":
			_expect(material.emission_enabled and material.emission.b > 0.5, "crystal emission preserved")
		if name == "UVSample":
			_expect(material.albedo_texture != null, "embedded image decoded without external texture file")
			if material.albedo_texture != null:
				_expect(material.albedo_texture.get_size() == Vector2(64, 64), "embedded texture dimensions preserved")
	var axes := {"ForwardAttachment": Vector3.FORWARD, "UpAttachment": Vector3.UP, "RightAttachment": Vector3.RIGHT}
	for name: String in axes:
		var attachment := scene.find_child(name, true, false) as Node3D
		_expect(attachment != null, "%s named attachment preserved" % name)
		if attachment != null:
			_expect(attachment.global_position.is_equal_approx(axes[name]), "%s coordinate convention" % name)
	scene.free()
	print("GLB_PROBE_RESULT checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + description)
