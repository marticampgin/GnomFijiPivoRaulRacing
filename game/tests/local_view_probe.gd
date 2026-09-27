extends SceneTree

const Session = preload("res://race/race_session.gd")
const Track = preload("res://track/authored_track.gd")
const View = preload("res://view/local_race_view.gd")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	for count: int in range(1, 5):
		var session := Session.new()
		root.add_child(session)
		session._track = Track.new()
		session.add_child(session._track)
		session._track.build(false)
		for seat: int in count:
			var id: String = "local:%d" % seat
			session._players[id] = session._new_player(id, id, seat, false)
		session._start_race()
		var view := View.new()
		session.add_child(view)
		view.configure(session)
		await process_frame
		_check(root.disable_3d, "root skips duplicate 3D rendering")
		_check(view._views.size() == count, "%d seats have exactly %d cameras" % [count, count])
		_check(view._visuals.size() == 10, "ten participants share one set of visuals")
		var area: float = 0.0
		for sector: Dictionary in view._views:
			_check(sector.viewport.world_3d == session.get_world_3d(), "sector shares authoritative world")
			_check(sector.viewport.get_camera_3d() == sector.camera, "sector uses its own camera")
			_check(sector.viewport.size.x > 0 and sector.viewport.size.y > 0, "sector render target is nonzero")
			area += sector.rect.get_area()
		_check(is_equal_approx(area, 0.75 if count == 3 else 1.0), "only three-seat layout reserves overview sector")
		view.set_quality("low", true)
		for sector: Dictionary in view._views:
			_check(is_equal_approx(sector.viewport.scaling_3d_scale, 0.75), "quality applies independently to each camera")
		if count == 2:
			view.set_layout("stacked")
			_check(view.sectors()[1].y == 0.5 and view.sectors()[1].width == 1.0, "stacked alternative divides vertically")
		root.size = Vector2i(844, 390)
		await process_frame
		view.resize()
		var bounds: Vector2 = root.get_visible_rect().size
		for sector: Dictionary in view._views:
			var end: Vector2 = sector.container.position + sector.container.size
			_check(end.x <= bounds.x and end.y <= bounds.y, "resized sectors stay inside logical screen")
		root.size = Vector2i(1600, 900)
		var tick: int = session._tick
		view.update_view(0.0, {0: {"look_back": true}})
		_check(session._tick == tick, "view never advances race simulation")
		_check(bool(view._views[0].chase._last_look_back), "seat zero camera receives look-back")
		if count > 1:
			_check(not bool(view._views[1].chase._last_look_back), "look-back is isolated from other seat")
		session._start_race()
		view.update_view(0.0)
		_check(view._visuals.size() == 10, "rematch replaces bot visuals without accumulating duplicates")
		view.free()
		_check(not root.disable_3d, "leaving local view restores root rendering")
		session.free()
		await process_frame
	print("LOCAL_VIEW_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
