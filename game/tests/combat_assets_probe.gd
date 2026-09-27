extends SceneTree

const Art = preload("res://items/item_art.gd")
const Visuals = preload("res://items/item_visuals.gd")
var checks := 0

func check(value: bool) -> void:
	assert(value)
	checks += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for id in ["crystal_shield", "seeker", "rear_trap"]:
		var prop := Art.create_item(id)
		check(prop.name == id)
		check(prop.get_child_count() >= 5)
		for mesh: MeshInstance3D in prop.get_children():
			check(mesh.mesh != null and mesh.material_override != null)
		prop.free()
	var aura := Art.create_shield_aura()
	check(aura.get_child_count() == 3)
	check(aura.get_child(0).material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
	check(aura.get_child(0).material_override.albedo_color.a < 0.2)
	aura.free()
	var visuals := Visuals.new()
	root.add_child(visuals)
	var world := {"projectiles": [
		{"id": 1, "kind": "seeker", "position": [0, 1, 0], "target": "p2"},
		{"id": 2, "kind": "rear_trap", "position": [0, 0, 2], "target": ""}],
		"events": [{"id": 3, "kind": "blast_seeker", "position": [0, 0, 0], "radius": 2},
		{"id": 4, "kind": "blast_rear_trap", "position": [0, 0, 2], "radius": 2}]}
	visuals.apply_world(world)
	check(visuals._projectiles["1"].name == "seeker")
	check(visuals._projectiles["2"].name == "rear_trap")
	check(visuals._events.size() == 2)
	visuals.apply_world(world)
	check(visuals._events.size() == 2)
	world.projectiles[0].position = [2, 1, 0]
	visuals.apply_world(world)
	visuals._process(0.1)
	check((-visuals._projectiles["1"].basis.z).dot(Vector3.RIGHT) > 0.99)
	check(visuals._projectiles["2"].rotation.is_zero_approx())
	check(visuals._projectiles["2"].position.is_equal_approx(Vector3(0, 0, 2)))
	visuals.set_reduced_effects(true)
	visuals._process(0.1)
	check(visuals._projectiles["2"].rotation.is_zero_approx())
	visuals.apply_world({})
	visuals._process(0.5)
	await process_frame
	check(visuals.get_child_count() == 0)
	visuals.queue_free()
	print("combat_assets_probe: %d assertions passed" % checks)
	quit()
