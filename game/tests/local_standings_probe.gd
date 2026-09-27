extends SceneTree

const Track = preload("res://track/authored_track.gd")

class TestLocal extends "res://race/local_race_session.gd":
	var distance_calls: int = 0
	var distances: Dictionary = {}

	func _race_progress(player: Dictionary) -> float:
		distance_calls += 1
		return float(distances.get(player.id, 0.0))

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session := TestLocal.new()
	root.add_child(session)
	var track := Track.new()
	session.add_child(track)
	track.build(false)
	session.configure(track)
	_check(session.start_local([{"device": -1}, {"device": 0}, {"device": 1}, {"device": 2}], [0, 1, 2]), "fixture starts")
	for scenario: String in ["racing", "ties", "finished", "results"]:
		session._phase = "results" if scenario == "results" else "racing"
		for player: Dictionary in session._players.values():
			var slot: int = player.slot
			session.distances[player.id] = 100.0 if scenario == "ties" else float((slot * 7) % 10) * 100.0
			player.result_progress = float((slot * 3) % 10) * 100.0
			player.finished = scenario in ["finished", "results"] and slot in [2, 7]
			player.finish_order = 0 if slot == 7 else 1
		var expected: Array = session._players.values()
		expected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.finished or b.finished:
				return int(a.finish_order) < int(b.finish_order) if a.finished and b.finished else bool(a.finished)
			var distance_a: float = float(a.get("result_progress", 0.0)) if session._phase == "results" else session._race_progress(a)
			var distance_b: float = float(b.get("result_progress", 0.0)) if session._phase == "results" else session._race_progress(b)
			return int(a.slot) < int(b.slot) if is_equal_approx(distance_a, distance_b) else distance_a > distance_b)
		session.distance_calls = 0
		var actual: Dictionary = session.presentation()
		_check(actual.players.map(func(p: Dictionary) -> String: return p.id) == expected.map(func(p: Dictionary) -> String: return p.id), scenario + " preserves legacy ordering")
		_check(session.distance_calls == 0 if scenario == "results" else session.distance_calls <= 10, "%s computes each distance at most once (calls=%d)" % [scenario, session.distance_calls])
		for seat: int in 4:
			_check(actual.seats[seat].position == actual.players.filter(func(p: Dictionary) -> bool: return p.id == "local:%d" % seat)[0].position, scenario + " seat position agrees with standings")
	session.free()
	await process_frame
	print("LOCAL_STANDINGS_PROBE %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
