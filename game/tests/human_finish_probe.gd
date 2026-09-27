extends SceneTree

const DT: float = 1.0 / 60.0

class TestTrack extends "res://track/authored_track.gd":
	var finish_requests: Array = []

	func advance_progress(progress: Dictionary, previous: Vector3, current: Vector3, discontinuity: bool = false) -> Array:
		for index: int in finish_requests.size():
			if is_same(finish_requests[index], progress):
				finish_requests.remove_at(index)
				progress.finished = true
				progress.lap = 3
				return [{"type": "finish"}]
		return super.advance_progress(progress, previous, current, discontinuity)

class TestSession extends "res://race/local_race_session.gd":
	var requested: bool = false

	func _physics_process(_delta: float) -> void:
		if requested:
			requested = false
			_step_session(DT)

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _step(session: TestSession) -> void:
	session.requested = true
	while session.requested:
		await physics_frame
		await process_frame


func _run() -> void:
	_check_completion_rules()
	for humans: int in [1, 2]:
		var session := TestSession.new()
		root.add_child(session)
		var track := TestTrack.new()
		session.add_child(track)
		track.build(false)
		session.configure(track)
		var seats: Array = []
		for seat: int in humans:
			seats.append({"device": seat - 1})
		_check(session.start_local(seats, [0]), "%d humans start" % humans)
		session._phase = "racing"
		session._countdown = 0
		_check(session._players.size() == 10, "bots fill grid")
		var bot: Dictionary = session._players["bot:%d" % humans]
		if humans > 1:
			track.finish_requests.append(bot.progress)
			await _step(session)
			_check(bot.finished and session._phase == "racing", "bot finish cannot end human race")
		for seat: int in humans:
			track.finish_requests.append(session._players["local:%d" % seat].progress)
			await _step(session)
			var expected: String = "results" if seat == humans - 1 else "racing"
			_check(session._phase == expected, "finish seat %d/%d transitions in same tick" % [seat + 1, humans])
		_check(session._finish_remaining > 29.0, "results do not wait for countdown")
		if humans == 1:
			_check(session._finish_count == 1, "solo human ends race before any of nine bots finish")
		var unfinished: Dictionary = session._players["bot:%d" % (humans + 1)]
		_check(not unfinished.finished and unfinished.dnf, "unfinished bots receive DNF")
		_check(unfinished.has("result_progress"), "unfinished bot final progress frozen")
		var race_id: int = session._race_id
		for seat: int in humans:
			_check(session.ready_seat(seat), "finished human can request repeat")
		await _step(session)
		_check(session._phase == "countdown" and session._race_id == race_id + 1, "repeat starts without bot readiness")
		_check(session._players.size() == 10, "repeat restores full grid")
		_check(not session._players["local:0"].finished and session._finish_remaining == -1.0, "repeat clears finish state")
		session.queue_free()
		await process_frame
	print("HUMAN_FINISH_PROBE %d/%d passed" % [_checks - _failures, _checks])
	quit(1 if _failures else 0)


func _check_completion_rules() -> void:
	var session := TestSession.new()
	var human := {"is_bot": false, "spectator": false, "finished": false, "connected": false}
	var bot := {"is_bot": true, "spectator": false, "finished": true}
	session._players = {"human": human, "bot": bot}
	_check(not session._race_participants_finished(), "disconnected human retains reconnect window")
	human.finished = true
	bot.finished = false
	_check(session._race_participants_finished(), "finished human does not wait for bot")
	human.spectator = true
	_check(not session._race_participants_finished(), "spectator cannot prematurely end bot race")
	human.spectator = false
	human.expired = true
	_check(not session._race_participants_finished(), "expired human cannot prematurely end bot race")
	session._players.erase("human")
	_check(not session._race_participants_finished(), "bot-only fixture waits for bots")
	bot.finished = true
	_check(session._race_participants_finished(), "bot-only fixture completes when bots finish")
	session.free()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
