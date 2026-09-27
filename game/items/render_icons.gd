extends SceneTree

const Art = preload("res://items/item_art.gd")
const IDS = ["fanta", "mermaid_rum", "ice_rum", "stroh80", "lays_crab", "bfg10k"]

func _initialize() -> void:
	call_deferred("_render")

func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0, 0, 0, 0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	viewport.add_child(light)
	light.rotation_degrees = Vector3(-40, -40, 0)
	light.light_energy = 1.8
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(1.8, 1.25, -3.8)
	camera.look_at(Vector3(0, 0.05, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.9
	var output := ProjectSettings.globalize_path("res://../web/assets/items")
	DirAccess.make_dir_recursive_absolute(output)
	for id in IDS:
		var model: Node3D = Art.create_item(id)
		viewport.add_child(model)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var result := viewport.get_texture().get_image().save_png(output.path_join(id + ".png"))
		print("item icon ", id, " result=", result)
		model.queue_free()
		await process_frame
	quit()
