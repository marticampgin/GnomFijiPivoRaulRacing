extends SceneTree

const Session = preload("res://race/local_race_session.gd")
const Track = preload("res://track/authored_track.gd")
const Bot = preload("res://ai/racing_bot_driver.gd")
var checks: int = 0
var failures: int = 0

class TestSession extends "res://race/local_race_session.gd":
	var steps: int = 0
	func _physics_process(_delta: float) -> void:
		if steps > 0:
			steps -= 1
			step_local(1.0 / 60.0, {-1: {"connected": true, "keys": {}}, 0: {"connected": true, "axes": {}, "buttons": {}}})


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session := TestSession.new()
	root.add_child(session)
	var track := Track.new()
	session.add_child(track)
	track.build(false)
	session.configure(track)
	for level: String in Bot.DIFFICULTIES:
		_check(session.start_local([{"device": -1, "style_id": "drift"}, {"device": 0, "style_id": "speed"}], [0], level), "start " + level)
		_check(session._human_count() == 2 and session._players.size() == 10, "mixed grid")
		for player: Dictionary in session._players.values():
			_check(player.vehicle.stats == Session.Styles.stats_for(player.style_id), "identical style stats " + level)
			_check(player.combat.slots == ["", ""] and player.combat.health == 100.0, "no free inventory or health")
			if player.is_bot:
				_check(player.driver.difficulty == level, "driver difficulty")
		var race_id: int = session._race_id
		_check(not session.start_local([{"device": -1}], [], "cheat"), "invalid difficulty rejected")
		_check(session._race_id == race_id and session.presentation().bot_difficulty == level and session._human_count() == 2, "invalid start transactional")
		session._phase = "results"
		session.ready_seat(0)
		session.ready_seat(1)
		session._try_repeat()
		_check(session._race_id == race_id + 1 and session._players["bot:2"].driver.difficulty == level, "repeat preserves difficulty")
		session._phase = "racing"
		session._countdown = 0
		var epochs: Dictionary = {}
		for bot: Dictionary in session._players.values():
			epochs[bot.id] = bot.epoch
		session.steps = 90
		while session.steps > 0:
			await physics_frame
			await process_frame
		var moving: int = 0
		for bot: Dictionary in session._players.values():
			if bot.is_bot:
				if bot.vehicle.speed_mps > 1.0:
					moving += 1
				_check(bot.epoch == epochs[bot.id], "short mixed grid no teleport " + level)
				_check(bot.vehicle.stats == session._items.effects_stats(bot, Session.Styles.stats_for(bot.style_id)), "live shared stats include ordinary race effects " + level)
		_check(moving == 8, "all bots drive under shared simulation " + level)
	var player: Dictionary = session._players["bot:2"]
	var opponent: Dictionary = session._players["local:0"]
	player.slot = 0
	var easy := Bot.new(track, 0, "easy")
	var normal := Bot.new(track, 0)
	var hard := Bot.new(track, 0, "hard")
	player.combat.slots = ["mermaid_rum", "bfg10k"]
	player.combat.health = 80.0
	var isolated: Dictionary = {player.id: player}
	_check(not easy.should_use_item(player, isolated, 120), "easy slower item decision")
	_check(normal.should_use_item(player, isolated, 120), "normal retains baseline item timing")
	_check(not hard.should_use_item(player, isolated, 180), "hard saves head heal without skipping to reserve weapon")
	player.combat.health = 45.0
	opponent.vehicle.global_position = player.vehicle.global_position - player.vehicle.global_basis.z * 15.0
	isolated[opponent.id] = opponent
	_check(hard.should_use_item(player, isolated, 180), "hard requests oldest heal only")
	opponent.vehicle.global_position = player.vehicle.global_position + player.vehicle.global_basis.z * 15.0
	_check(hard.should_use_item(player, isolated, 180), "head heal independent of reserve target")
	player.combat.slots = ["seeker", "crystal_shield"]
	_check(not hard.should_use_item(player, isolated, 180), "hard cannot skip unaimed seeker to use reserve shield")
	opponent.vehicle.global_position = player.vehicle.global_position - player.vehicle.global_basis.z * 15.0
	_check(hard.should_use_item(player, isolated, 180), "hard uses head seeker with forward target")
	player.combat.effects.crystal_shield = {"remaining": 3.0}
	_check(hard.should_use_item(player, isolated, 180), "reserve effect cannot change decision about head item")
	player.combat.slots = ["crystal_shield", "fanta"]
	_check(not hard.should_use_item(player, isolated, 180), "hard does not skip already active head shield")
	player.combat.slots = ["fanta", "lays_crab"]
	player.combat.effects = {"fanta": {"remaining": 2.0}}
	_check(not hard.should_use_item(player, isolated, 180), "hard avoids redundant head effect without consuming reserve")
	player.combat.effects.clear()
	player.finished = true
	_check(not normal.should_use_item(player, isolated, 120), "finished bots keep inventory")
	player.finished = false
	player.driver = normal
	session._tick = 119
	session._items._pickups.clear()
	session.steps = 1
	while session.steps > 0:
		await physics_frame
		await process_frame
	_check(player.combat.slots == ["lays_crab", ""] and player.combat.effects.has("fanta") and not player.combat.effects.has("lays_crab"), "one bot decision consumes only queue head per physics tick")
	var original_stats: Dictionary = player.vehicle.stats.duplicate(true)
	var original_pose: Transform3D = player.vehicle.global_transform
	player.vehicle.speed_mps = 20.0
	var easy_command: Dictionary = easy.sample(player.vehicle, player.progress, 1.0 / 60.0)
	player.vehicle.rotate_y(0.3)
	_check(easy.sample(player.vehicle, player.progress, 1.0 / 60.0) == easy_command, "easy holds reaction command")
	_check(player.vehicle.stats == original_stats, "driver cannot change stats")
	player.vehicle.global_transform = original_pose
	_check(hard.sample(player.vehicle, player.progress, 1.0 / 60.0).has("throttle"), "hard produces shared pedal command")
	_check(player.vehicle.global_transform == original_pose, "driver does not teleport")
	_check(normal.difficulty == "normal", "network default normal")
	session.free()
	print("BOT_DIFFICULTY_PROBE %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
