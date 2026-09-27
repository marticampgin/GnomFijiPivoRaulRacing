extends SceneTree

const Visuals = preload("res://items/item_visuals.gd")
const Art = preload("res://items/item_art.gd")
const Runtime = preload("res://items/race_items.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var visuals := Visuals.new()
	root.add_child(visuals)
	for id in ["fanta", "mermaid_rum", "ice_rum", "stroh80", "lays_crab", "bfg10k"]:
		var prop: Node3D = Art.create_item(id)
		assert(prop.get_child_count() >= 5)
		prop.free()
	var bolt: Node3D = Art.create_projectile("bfg10k")
	assert(bolt.name == "bfg_energy_bolt" and bolt.get_child_count() == 3)
	bolt.free()
	var runtime := Runtime.new()
	runtime._pickups = [{"id": 1, "position": Vector3(1, 2, 3)}]
	runtime._projectiles = [{"id": 2, "kind": "stroh80", "position": Vector3(0, 1, 0)}]
	runtime._event("blast_stroh80", Vector3(0, 1, 0), 4.0)
	var world: Dictionary = runtime.world_state()
	visuals.apply_world(world)
	assert(visuals.get_child_count() == 3)
	visuals.apply_world(world)
	assert(visuals.get_child_count() == 3)
	visuals.set_reduced_effects(true)
	visuals._process(0.1)
	assert(is_equal_approx(visuals._pickups["1"].position.y, 2.0))
	visuals._process(0.1)
	var effect: Node3D = visuals._events.values()[0].node
	assert(is_equal_approx(effect.scale.x * 0.5, 4.0 * 0.35))
	world.pickups[0].available = false
	visuals.apply_world(world)
	assert(not visuals._pickups["1"].visible)
	world.pickups[0].available = true
	visuals.apply_world(world)
	assert(visuals._pickups["1"].visible)
	visuals._process(0.5)
	visuals.apply_world({})
	await process_frame
	assert(visuals.get_child_count() == 0)
	visuals.apply_world(world)
	assert(visuals.get_child_count() == 2)
	visuals.clear()
	await process_frame
	visuals.apply_world(world)
	assert(visuals.get_child_count() == 3)
	runtime._event("use_bfg10k", Vector3.ZERO, 1.0)
	visuals.apply_world(runtime.world_state())
	assert(visuals.get_child_count() == 3)
	runtime._event("blast_bfg10k", Vector3.ZERO, 6.0)
	visuals.apply_world(runtime.world_state())
	assert(visuals.get_child_count() == 4)
	runtime._projectiles.append({"id": 22, "kind": "bfg10k", "position": Vector3.ZERO})
	visuals.apply_world(runtime.world_state())
	assert(visuals._projectiles["22"].name == "bfg_energy_bolt")
	print("item_visuals_probe: 19 assertions passed")
	quit()
