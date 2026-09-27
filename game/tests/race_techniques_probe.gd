extends SceneTree

const Techniques = preload("res://race/race_techniques.gd")
const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Styles = preload("res://vehicle/driving_styles.gd")
const Protocol = preload("res://net/prototype_protocol.gd")
const Track = preload("res://track/authored_track.gd")
const Session = preload("res://race/race_session.gd")
const Bot = preload("res://ai/racing_bot_driver.gd")
const DT: float = 1.0 / 60.0
var checks: int = 0
var failures: int = 0
var techniques: RefCounted = Techniques.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for style: String in Styles.IDS:
		var player: Dictionary = _player(style, Vector3.ZERO)
		player.vehicle.configure(Styles.stats_for(style))
		for timing: float in [0.9, 0.4, 0.05]:
			player.driving = Techniques.new_state()
			player.vehicle.boost_remaining = 0.0
			techniques.countdown(player, {"throttle": 1.0}, timing, false)
			_check(player.vehicle.boost_remaining == 0.0, "countdown cannot grant boost before GO")
			techniques.countdown(player, {"throttle": 1.0}, 0.0, true)
			_check(is_equal_approx(player.vehicle.boost_remaining, 1.0 if timing == 0.4 else 0.0), style + " start timing bonus or ordinary start")
		player.driving = Techniques.new_state()
		player.vehicle.boost_remaining = 0.0
		techniques.countdown(player, {"throttle": 1.0}, 0.4, false)
		techniques.countdown(player, Protocol.NEUTRAL, 0.1, false)
		techniques.countdown(player, Protocol.NEUTRAL, 0.0, true)
		_check(player.vehicle.boost_remaining == 0.0, "released start input cannot keep a bonus")
		player.vehicle.free()
	_slipstream()
	await _drift_and_control()
	await _session_start()
	print("RACE_TECHNIQUES_PROBE %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _player(id: String, location: Vector3) -> Dictionary:
	var kart: CharacterBody3D = Vehicle.new()
	root.add_child(kart)
	kart.global_position = location
	kart.velocity = Vector3.FORWARD * 15.0
	kart.grounded = true
	return {"id": id, "vehicle": kart, "driving": Techniques.new_state(), "finished": false,
		"spectator": false, "connected": true, "combat": {"health": 100.0, "destroyed_remaining": 0.0, "invulnerable_remaining": 0.0}}


func _slipstream() -> void:
	var follower: Dictionary = _player("follower", Vector3.ZERO)
	var leader: Dictionary = _player("leader", Vector3(0.0, 0.0, -8.0))
	var players: Dictionary = {"follower": follower, "leader": leader}
	for tick: int in 60:
		techniques.step(players, DT)
	_check(follower.driving.slipstream_charge > 0.8 and follower.vehicle.boost_remaining == 0.0, "draft requires dwell, not instant entry")
	for tick: int in 12:
		techniques.step(players, DT)
	_check(follower.driving.slipstream_boost_remaining == 1.0 and follower.vehicle.boost_remaining == 1.0, "dwell grants bounded boost")
	_check(follower.combat.invulnerable_remaining == 0.0, "slipstream never grants immunity")
	follower.vehicle.boost_remaining = 0.0
	for tick: int in 100:
		techniques.step(players, DT)
	_check(follower.driving.slipstream_boost_remaining == 0.0 and follower.vehicle.boost_remaining == 0.0, "staying behind cannot maintain permanent boost")
	for kind: String in ["ahead", "far", "side", "height", "opposite", "stopped", "airborne", "finished", "destroyed", "spectator"]:
		follower.driving = Techniques.new_state()
		leader.vehicle.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -8.0))
		leader.vehicle.velocity = Vector3.FORWARD * 15.0
		leader.vehicle.grounded = true
		leader.finished = false
		leader.spectator = false
		leader.combat.destroyed_remaining = 0.0
		match kind:
			"ahead": leader.vehicle.position.z = 8.0
			"far": leader.vehicle.position.z = -20.0
			"side": leader.vehicle.position.x = 3.0
			"height": leader.vehicle.position.y = 4.0
			"opposite": leader.vehicle.rotation.y = PI
			"stopped": leader.vehicle.velocity = Vector3.ZERO
			"airborne": leader.vehicle.grounded = false
			"finished": leader.finished = true
			"destroyed": leader.combat.destroyed_remaining = 1.0
			"spectator": leader.spectator = true
		techniques.step(players, DT)
		_check(follower.driving.slipstream_charge == 0.0, "draft excludes " + kind)
	leader.spectator = false
	follower.driving = Techniques.new_state()
	techniques.step(players, DT)
	var expected: Dictionary = follower.driving.duplicate()
	follower.driving = Techniques.new_state()
	techniques.step({"leader": leader, "follower": follower}, DT)
	_check(follower.driving == expected, "draft charge independent of dictionary iteration order")
	follower.vehicle.boost_remaining = 1.8
	follower.driving = Techniques.new_state()
	for tick: int in 72:
		techniques.step(players, DT)
	_check(is_equal_approx(follower.vehicle.boost_remaining, 1.8), "slip boost neither stacks nor truncates a longer active boost")
	_check(Techniques.presentation(follower).size() == 4, "presentation exposes only four authoritative technique fields")
	follower.vehicle.free()
	leader.vehicle.free()


func _drift_and_control() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	var kart: CharacterBody3D = Vehicle.new()
	var shape := CollisionShape3D.new()
	shape.shape = Vehicle.create_collision_shape()
	kart.add_child(shape)
	root.add_child(kart)
	for style: String in Styles.IDS:
		kart.configure(Styles.stats_for(style))
		for chain: int in 3:
			kart.reset_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.35, 0.0)))
			kart.velocity = Vector3.FORWARD * 16.0
			kart.grounded = true
			kart._step_drift(false, false, true, 0.2, DT)
			kart._step_drift(true, false, true, 0.2, DT)
			kart.drift_chain = chain
			kart.drift_charge = 0.75
			await physics_frame
			kart.step({"throttle": 1.0, "steering": 0.6, "drift_left": true, "drift_right": true}, DT)
			_check(kart.drift_level() == chain + 1, style + " records successful timed turbo")
			_check(is_equal_approx(kart.boost_remaining, Vehicle.DRIFT_BOOST_SECONDS[chain]), style + " earns corresponding drift duration")
			_check(not kart.global_basis.is_equal_approx(Basis.IDENTITY), "steering remains active during boost")
			kart.boost_remaining = 0.0
			await physics_frame
			kart.step({"throttle": 1.0, "steering": 0.6}, DT)
			_check(kart.boost_remaining == 0.0 and kart.drift_level() == 0, "release resets chain without awarding turbo")
	kart.free()
	floor_body.free()
	await physics_frame


func _session_start() -> void:
	var session: Node3D = Session.new()
	root.add_child(session)
	var track: Node3D = Track.new()
	session.add_child(track)
	track.build(false)
	session._track = track
	var human: Dictionary = session._new_player("human", "Human", 0, false)
	session._players.human = human
	session._phase = "countdown"
	session._countdown = 40
	human.input = Protocol.NEUTRAL.duplicate()
	for tick: int in 40:
		if tick == 15:
			human.input = {"throttle": 1.0}
		await physics_frame
		session._step_session(DT)
		if tick == 37:
			_check(human.vehicle.speed_mps < 0.05 and human.vehicle.boost_remaining == 0.0, "shared session keeps countdown parked while recording timing")
	_check(session._phase == "racing" and human.driving.start_boost_remaining > 0.9, "shared session grants timing bonus on GO")
	_check(human.vehicle.boost_remaining > 0.9, "GO boost enters captured authoritative physics state")
	session._recover(human)
	_check(human.driving == Techniques.new_state(), "recovery clears technique state")
	for level: String in Bot.DIFFICULTIES:
		var bot: RefCounted = Bot.new(track, 1, level)
		var bot_player: Dictionary = _player(level, Vector3.ZERO)
		for tick: int in 61:
			var seconds: float = float(60 - tick) / 60.0
			techniques.countdown(bot_player, bot.sample_countdown(seconds), seconds, tick == 60)
		_check(bot_player.vehicle.boost_remaining == (0.0 if level == "easy" else 1.0), "bot " + level + " passes same timing judge")
		bot_player.vehicle.free()
	session.free()
	await process_frame


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
