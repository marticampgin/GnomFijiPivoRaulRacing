extends SceneTree

const View = preload("res://view/local_race_view.gd")
const WARMUP_TICKS: int = 60
const SAMPLE_TICKS: int = 300

class TimedTrack extends "res://track/authored_track.gd":
	var costs: Dictionary = {}
	var measuring: bool = false

	func record(label: String, start: int) -> void:
		if measuring:
			var entry: Dictionary = costs.get(label, {"total_us": 0, "calls": 0})
			entry.total_us += Time.get_ticks_usec() - start
			entry.calls += 1
			costs[label] = entry

	func sample_at(s: float) -> Dictionary:
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = super.sample_at(s)
		record("sample_at", start)
		return result

	func advance_progress(state: Dictionary, previous: Vector3, current: Vector3, discontinuity: bool = false) -> Array:
		var start: int = Time.get_ticks_usec()
		var result: Array = super.advance_progress(state, previous, current, discontinuity)
		record("advance_progress", start)
		return result

	func standings_distance(state: Dictionary, location: Vector3) -> float:
		var start: int = Time.get_ticks_usec()
		var result: float = super.standings_distance(state, location)
		record("standings_distance", start)
		return result

	func needs_recovery(location: Vector3) -> bool:
		var start: int = Time.get_ticks_usec()
		var result: bool = super.needs_recovery(location)
		record("needs_recovery", start)
		return result

class TestLocal extends "res://race/local_race_session.gd":
	var race_view: Node3D
	var samples: Dictionary = {"simulation": [], "view": [], "presentation": []}
	var completed: int = 0
	var active: bool = false
	var snapshots: Dictionary = {-1: {"connected": true, "keys": {"KeyW": true}}, 0: {"connected": true, "axes": {}, "buttons": {}}, 1: {"connected": true, "axes": {}, "buttons": {}}, 2: {"connected": true, "axes": {}, "buttons": {}}}

	func _create_vehicle(_slot: int, _visuals: bool) -> CharacterBody3D:
		var vehicle := TimedVehicle.new()
		vehicle.owner_session = self
		var collider := CollisionShape3D.new()
		collider.shape = Vehicle.create_collision_shape()
		vehicle.add_child(collider)
		vehicle.collision_layer = 2
		vehicle.collision_mask = 1
		add_child(vehicle)
		return vehicle

	func _physics_process(delta: float) -> void:
		if not active or completed >= WARMUP_TICKS + SAMPLE_TICKS:
			return
		_track.measuring = completed >= WARMUP_TICKS
		var start: int = Time.get_ticks_usec()
		step_local(delta, snapshots)
		var stepped: int = Time.get_ticks_usec()
		race_view.update_view(delta, _last_commands)
		var viewed: int = Time.get_ticks_usec()
		var state: Dictionary = presentation()
		var presented: int = Time.get_ticks_usec()
		assert(state.seats.size() == 4 and state.players.size() == 10)
		if completed >= WARMUP_TICKS:
			samples.simulation.append(stepped - start)
			samples.view.append(viewed - stepped)
			samples.presentation.append(presented - viewed)
		completed += 1

class TimedVehicle extends "res://vehicle/racing_vehicle.gd":
	var owner_session: Node3D
	var total_us: int = 0
	var calls: int = 0

	func step(command: Dictionary, delta: float, gravity_up: Vector3 = Vector3.UP) -> void:
		var start: int = Time.get_ticks_usec()
		super.step(command, delta, gravity_up)
		if owner_session.completed >= WARMUP_TICKS:
			total_us += Time.get_ticks_usec() - start
			calls += 1

class TimedItems extends "res://items/race_items.gd":
	var owner_session: Node3D
	var costs: Dictionary = {}

	func record(label: String, start: int) -> void:
		if owner_session.completed >= WARMUP_TICKS:
			costs[label] = int(costs.get(label, 0)) + Time.get_ticks_usec() - start

	func step(players: Dictionary, delta: float) -> Array:
		var start: int = Time.get_ticks_usec()
		var result: Array = super.step(players, delta)
		record("step", start)
		return result

	func _step_shards(players: Dictionary, delta: float) -> void:
		var start: int = Time.get_ticks_usec()
		super._step_shards(players, delta)
		record("shards", start)

	func _collect_pickups(players: Dictionary) -> void:
		var start: int = Time.get_ticks_usec()
		super._collect_pickups(players)
		record("pickups", start)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var session := TestLocal.new()
	root.add_child(session)
	var items := TimedItems.new()
	items.owner_session = session
	session._items = items
	var track := TimedTrack.new()
	session.add_child(track)
	track.build(false)
	session.configure(track)
	assert(session.start_local([{"device": -1}, {"device": 0}, {"device": 1}, {"device": 2}], [0, 1, 2]))
	var view := View.new()
	session.add_child(view)
	view.configure(session)
	session.race_view = view
	session._phase = "racing"
	session._countdown = 0
	session.active = true
	while session.completed < WARMUP_TICKS + SAMPLE_TICKS:
		await physics_frame
		await process_frame
	var results: Dictionary = {"samples": SAMPLE_TICKS, "warmup": WARMUP_TICKS, "native_headless_only": true}
	results["track_inclusive"] = track.costs
	results["items_inclusive_us"] = items.costs
	var vehicle_us: int = 0
	var vehicle_calls: int = 0
	for player: Dictionary in session._players.values():
		vehicle_us += player.vehicle.total_us
		vehicle_calls += player.vehicle.calls
	results["vehicle_step_inclusive"] = {"total_us": vehicle_us, "calls": vehicle_calls}
	for layer: String in session.samples:
		var values: Array = session.samples[layer]
		values.sort()
		var total: int = 0
		for value: int in values:
			total += value
		results[layer] = {"total_us": total, "mean_us": float(total) / values.size(), "p50_us": values[values.size() / 2], "p95_us": values[floori(values.size() * 0.95)], "max_us": values.back()}
	print("LOCAL_COST_PROBE " + JSON.stringify(results))
	session.free()
	await process_frame
	quit()
