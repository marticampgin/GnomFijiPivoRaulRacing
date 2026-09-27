extends Node3D

const Kart = preload("res://vehicle/authored_kart.gd")
const ChaseCamera = preload("res://view/race_camera.gd")
const ItemVisuals = preload("res://items/item_visuals.gd")

var _session: Node3D
var _layout: String = "side-by-side"
var _quality: String = "standard"
var _reduced: bool = false
var _layer: CanvasLayer
var _surface: Control
var _views: Array[Dictionary] = []
var _visuals: Dictionary = {}
var _items: Node3D
var _sun: DirectionalLight3D
var _parent_viewport: Viewport
var _previous_disable_3d: bool = false
var _race_id: int = -1
var _clock: float = 0.0


func configure(session: Node3D, layout: String = "side-by-side") -> void:
	assert(_session == null, "Configure each local race view once")
	_session = session
	_layout = layout
	_parent_viewport = get_viewport()
	_previous_disable_3d = _parent_viewport.disable_3d
	_parent_viewport.disable_3d = true
	Kart.warm()
	if _session.get_world_3d().environment == null:
		_setup_lighting()
	_items = ItemVisuals.new()
	add_child(_items)
	_items.set_process(false)
	_layer = CanvasLayer.new()
	add_child(_layer)
	_surface = Control.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_surface)
	_parent_viewport.size_changed.connect(resize)
	_rebuild_views()
	set_quality(_quality, _reduced)
	_sync_visuals(0.0)


func _exit_tree() -> void:
	for visual: Node3D in _visuals.values():
		if is_instance_valid(visual):
			visual.queue_free()
	if is_instance_valid(_parent_viewport):
		_parent_viewport.disable_3d = _previous_disable_3d


func _humans() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for player: Dictionary in _session._players.values():
		if not player.is_bot:
			result.append(player)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot) < int(b.slot))
	return result


static func layout_rects(count: int, layout: String = "side-by-side") -> Array[Rect2]:
	if count == 1:
		return [Rect2(0, 0, 1, 1)]
	if count == 2:
		if layout == "stacked":
			return [Rect2(0, 0, 1, 0.5), Rect2(0, 0.5, 1, 0.5)]
		return [Rect2(0, 0, 0.5, 1), Rect2(0.5, 0, 0.5, 1)]
	var result: Array[Rect2] = []
	for index: int in mini(count, 4):
		result.append(Rect2((index % 2) * 0.5, floori(index / 2.0) * 0.5, 0.5, 0.5))
	return result


func sectors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for view: Dictionary in _views:
		var rect: Rect2 = view.rect
		result.append({"seat": view.seat, "x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y})
	return result


func set_layout(layout: String) -> void:
	_layout = "stacked" if layout == "stacked" else "side-by-side"
	if _session != null:
		_rebuild_views()


func _rebuild_views() -> void:
	for view: Dictionary in _views:
		view.container.free()
	_views.clear()
	var humans: Array[Dictionary] = _humans()
	var rects: Array[Rect2] = layout_rects(humans.size(), _layout)
	for index: int in rects.size():
		var container := SubViewportContainer.new()
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.stretch = true
		_surface.add_child(container)
		var viewport := SubViewport.new()
		viewport.world_3d = _session.get_world_3d()
		viewport.handle_input_locally = false
		viewport.gui_disable_input = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)
		var camera := Camera3D.new()
		camera.far = 1200.0
		viewport.add_child(camera)
		camera.current = true
		var chase: RefCounted = ChaseCamera.new()
		chase.configure(camera)
		_views.append({"seat": int(humans[index].slot), "id": humans[index].id, "rect": rects[index], "container": container, "viewport": viewport, "camera": camera, "chase": chase})
	resize()
	set_quality(_quality, _reduced)


func resize() -> void:
	var size: Vector2 = _parent_viewport.get_visible_rect().size
	for view: Dictionary in _views:
		var rect: Rect2 = view.rect
		var first: Vector2 = (size * rect.position).floor()
		var last: Vector2 = (size * rect.end).floor()
		view.container.position = first
		view.container.size = (last - first).max(Vector2.ONE)


func set_quality(quality: String, reduced_effects: bool = false) -> void:
	_quality = "low" if quality == "low" else "standard"
	_reduced = reduced_effects
	var low: bool = _quality == "low"
	for view: Dictionary in _views:
		view.viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		view.viewport.scaling_3d_scale = 0.75 if low else 1.0
		view.viewport.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	if is_instance_valid(_sun):
		_sun.directional_shadow_max_distance = 45.0 if low else 120.0
	if is_instance_valid(_items):
		_items.set_quality(_quality)
		_items.set_reduced_effects(_reduced)
	if _session != null and is_instance_valid(_session._track):
		if _session._track.has_method("set_quality"):
			_session._track.set_quality(low)
		if _session._track.has_method("set_reduced_effects"):
			_session._track.set_reduced_effects(_reduced)
	for visual: Node3D in _visuals.values():
		if is_instance_valid(visual):
			visual.set_reduced_effects(_reduced)


## Presentation only: the owner advances the shared simulation exactly once.
func update_view(delta: float, commands_by_seat: Dictionary = {}) -> void:
	if _session == null:
		return
	_clock += maxf(0.0, delta)
	_sync_visuals(delta)
	if _race_id != int(_session._race_id):
		_race_id = int(_session._race_id)
		_items.clear()
	# Legacy personal gift cooldowns become global in the item-rule milestone.
	_items.apply_world(_session._items.world_state())
	_items._process(maxf(0.0, delta))
	for view: Dictionary in _views:
		var player: Dictionary = _session._players.get(view.id, {})
		if player.is_empty():
			continue
		var command: Dictionary = commands_by_seat.get(view.seat, {})
		view.chase.update(player.vehicle, delta, bool(command.get("look_back", false)))


func _sync_visuals(delta: float) -> void:
	var alive: Dictionary = {}
	for player: Dictionary in _session._players.values():
		var vehicle: CharacterBody3D = player.vehicle
		var key: int = vehicle.get_instance_id()
		alive[key] = true
		if not _visuals.has(key) or not is_instance_valid(_visuals[key]):
			var visual: Node3D = Kart.create(Color("2e9d99"))
			visual.set_reduced_effects(_reduced)
			vehicle.add_child(visual)
			_visuals[key] = visual
		var visual: Node3D = _visuals[key]
		var combat: Dictionary = player.combat
		visual.visible = float(combat.get("destroyed_remaining", 0.0)) <= 0.0 and (_reduced or float(combat.get("invulnerable_remaining", 0.0)) <= 0.0 or fmod(_clock, 0.4) < 0.28)
		visual.update_visual(delta, vehicle.speed_mps, vehicle.steering_amount, vehicle.is_drifting, minf(1.0, vehicle.boost_remaining))
	for key: int in _visuals.keys():
		if not alive.has(key):
			if is_instance_valid(_visuals[key]):
				_visuals[key].queue_free()
			_visuals.erase(key)


func _setup_lighting() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	var sky := Sky.new()
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = load("res://art/summer-sky.png")
	sky.sky_material = panorama
	settings.background_mode = Environment.BG_SKY
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c1d9ec")
	settings.ambient_light_energy = 0.5
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	_sun.light_color = Color("fff1d8")
	_sun.light_energy = 0.78
	_sun.shadow_enabled = true
	add_child(_sun)
