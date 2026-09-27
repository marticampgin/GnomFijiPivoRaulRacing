extends SceneTree

const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Styles = preload("res://vehicle/driving_styles.gd")
const DT: float = 1.0 / 60.0
var world: Node3D
var vehicles: Dictionary = {}
var checks: int = 0
var failures: int = 0
var measurements: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_catalogue_checks()
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000.0, 1.0, 1000.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	for id: String in Styles.IDS:
		var vehicle = Vehicle.new()
		var collider := CollisionShape3D.new()
		collider.shape = Vehicle.create_collision_shape()
		vehicle.add_child(collider)
		vehicle.collision_layer = 2
		vehicle.collision_mask = 1
		vehicle.configure(Styles.stats_for(id))
		world.add_child(vehicle)
		vehicles[id] = vehicle
	_reset_all()
	await _steps(60, {})
	await _steps(60, {"throttle": 1.0})
	var acceleration := _speeds()
	measurements["speed_after_one_second"] = acceleration
	_check(_strongest(acceleration) == "acceleration", "acceleration style wins standing-start acceleration")
	await _steps(240, {"throttle": 1.0})
	var top_speeds := _speeds()
	measurements["top_speeds"] = top_speeds
	_check(_strongest(top_speeds) == "speed", "speed style wins sustained straight-line speed")
	for id: String in Styles.IDS:
		_check(absf(top_speeds[id] - float(Styles.stats_for(id)["top_speed"])) < 0.1, id + " reaches its engine cap")
	_reset_all()
	await _steps(60, {})
	for vehicle in vehicles.values():
		vehicle.velocity = Vector3.FORWARD * 20.0
	await _steps(30, {"throttle": 1.0, "steering": 0.6})
	var turns: Dictionary = {}
	for id: String in Styles.IDS:
		turns[id] = absf(vehicles[id].rotation.y)
	measurements["turn_angle_half_second"] = turns
	_check(_strongest(turns) == "handling", "handling style turns most at equal starting speed")
	_reset_all()
	await _steps(60, {})
	for vehicle in vehicles.values():
		vehicle.velocity = Vector3.FORWARD * 24.0
	await _steps(50, {"throttle": 1.0, "steering": 0.6, "drift_left": true})
	var charges: Dictionary = {}
	for id: String in Styles.IDS:
		charges[id] = vehicles[id].drift_charge
		_check(charges[id] > 0.25, id + " earns drift charge")
	measurements["drift_charge"] = charges
	_check(_strongest(charges) == "drift", "drift style charges fastest under the same controls")
	var boosts: Dictionary = {}
	var ready_at: Dictionary = {}
	for tick: int in 100:
		await physics_frame
		for id: String in Styles.IDS:
			var vehicle = vehicles[id]
			var command: Dictionary = {"throttle": 1.0, "steering": 0.6, "drift_left": true}
			if ready_at.has(id):
				command.drift_left = false
			elif vehicle.drift_ready():
				command.drift_right = true
				ready_at[id] = tick
			vehicle.step(command, DT)
			if ready_at.get(id, -1) == tick:
				boosts[id] = vehicle.boost_remaining
		if ready_at.size() == Styles.IDS.size():
			break
	for id: String in Styles.IDS:
		var vehicle = vehicles[id]
		_check(boosts.get(id, 0.0) == Vehicle.DRIFT_BOOST_SECONDS[0], id + " gets same first turbo through manual timing")
		var configured: Dictionary = vehicle.stats.duplicate(true)
		var state: Dictionary = vehicle.capture_state()
		vehicle.reset_at(Transform3D.IDENTITY)
		_check(vehicle.stats == configured and vehicle.boost_remaining == 0.0, id + " respawn clears motion without losing profile")
		vehicle.restore_state(state)
		_check(vehicle.stats == configured, id + " reconciliation preserves profile")
	measurements["boost_duration"] = boosts
	measurements["ticks_to_ready_after_charge_sample"] = ready_at
	for id: String in Styles.IDS:
		if id != "drift":
			_check(int(ready_at.get("drift", 999)) < int(ready_at.get(id, 0)), "drift specialization reaches timing window before " + id)
	print("DRIVING_STYLES_PROBE ", JSON.stringify({"checks": checks, "failures": failures, "measurements": measurements}))
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _catalogue_checks() -> void:
	_check(Styles.IDS.size() == 4 and Styles.IDS.has("drift"), "four styles include a separate drift style")
	_check(Styles.is_valid(Styles.DEFAULT_ID), "default style is valid")
	for invalid in ["", "unknown", "SPEED", 1, null, {}, []]:
		_check(not Styles.is_valid(invalid), "reject malformed or unknown style: " + str(invalid))
	var copy: Dictionary = Styles.stats_for("speed")
	copy["top_speed"] = 999.0
	_check(Styles.stats_for("speed")["top_speed"] == 37.0, "returned profile stats cannot mutate catalogue")
	var catalogue: Array = Styles.describe_all()
	catalogue[0]["stats"]["handling"] = 99.0
	_check(Styles.stats_for("handling")["handling"] == 1.18, "description stats cannot mutate catalogue")
	_check(Styles.stats_for("unknown") == Styles.stats_for(Styles.DEFAULT_ID), "internal unknown profile falls back to default")
	for id: String in Styles.IDS:
		var stats: Dictionary = Styles.stats_for(id)
		_check(stats["durability"] == 100.0, id + " retains equal deferred durability")
		for other: String in Styles.IDS:
			if id == other:
				continue
			var weaker: bool = false
			for key: String in ["top_speed", "acceleration", "handling", "drift"]:
				weaker = weaker or float(stats[key]) < float(Styles.stats_for(other)[key])
			_check(weaker, id + " cannot dominate " + other + " across all characteristics")


func _reset_all() -> void:
	for index: int in Styles.IDS.size():
		vehicles[Styles.IDS[index]].reset_at(Transform3D(Basis.IDENTITY, Vector3(index * 80.0 - 120.0, 0.8, 0.0)))


func _steps(count: int, input: Dictionary) -> void:
	for tick: int in count:
		await physics_frame
		for vehicle in vehicles.values():
			vehicle.step(input, DT)


func _speeds() -> Dictionary:
	var result: Dictionary = {}
	for id: String in Styles.IDS:
		result[id] = vehicles[id].speed_mps
	return result


func _strongest(values: Dictionary) -> String:
	var best: String = ""
	var maximum: float = -INF
	for id: String in values:
		if float(values[id]) > maximum:
			best = id
			maximum = float(values[id])
	return best


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
