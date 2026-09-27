extends SceneTree

const Study = preload("res://track/authored_track_study.gd")
const Track = preload("res://track/authored_track.gd")
const Baker = preload("res://track/track_baker.gd")
const Kart = preload("res://vehicle/prototype_kart.gd")


func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	root.size = Vector2i(1600, 900)
	var track := Track.new()
	var data: Dictionary = track.data
	track.free()
	var world := Node3D.new()
	root.add_child(world)
	var study := Study.new()
	world.add_child(study)
	study.build(data)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	var sky := Sky.new()
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://art/summer-sky.png")
	sky.sky_material = sky_material
	settings.background_mode = Environment.BG_SKY
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c4dcf0")
	settings.ambient_light_energy = 0.42
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_color = Color("fff1d8")
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	world.add_child(sun)
	var kart: Node3D = Kart.create(Color("2e9d99"))
	world.add_child(kart)
	var camera := Camera3D.new()
	camera.fov = 58.0
	camera.far = 1400.0
	world.add_child(camera)
	camera.current = true
	for anchor: Dictionary in data.camera_anchors:
		var position: Vector3 = Baker.vector(anchor.position)
		var forward: Vector3 = Baker.vector(anchor.forward).slide(Vector3.UP).normalized()
		kart.transform = Transform3D(Basis.looking_at(forward, Vector3.UP), position + Vector3.UP * 0.35)
		camera.position = position - forward * 5.5 + Vector3.UP * 2.85
		camera.look_at(position + forward * 3.8 + Vector3.UP * 1.35)
		for frame: int in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "/private/tmp/gnom-study-%s.png" % anchor.id
		root.get_texture().get_image().save_png(path)
		print("STUDY_RENDER ", path)
	quit()
