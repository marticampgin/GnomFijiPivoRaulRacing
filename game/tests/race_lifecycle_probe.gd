extends SceneTree

const Track = preload("res://track/authored_track.gd")

class Race:
	extends "res://app/prototype.gd"
	func _ready() -> void:
		pass

class FakeServer:
	extends Node
	var packet: Dictionary = {}
	func send_to(_peer: int, data: Dictionary, _disposable: bool = false) -> void:
		packet = data
	func close_peer(_peer: int, _reason: String) -> void:
		pass

var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		push_error(label)
		quit(1)
		assert(condition, label)

func run() -> void:
	var race: Node3D = Race.new()
	root.add_child(race)
	race.set_process(false)
	race.set_physics_process(false)
	race._track = Track.new()
	race.add_child(race._track)
	race._track.build(false)
	race._server = FakeServer.new()
	race.add_child(race._server)
	race._players["a"] = race._new_player("a", "A", 0, false)
	race._players["b"] = race._new_player("b", "B", 1, false)
	race._peer_players[1] = "a"
	race._peer_players[2] = "b"
	race._start_race()
	check(race._players.size() == 10 and race._human_count() == 2, "eight bots fill ten-slot grid")
	check(race._race_id == 1 and race._countdown == 300, "generation and five-second countdown")
	var expired: Dictionary = race._players["a"]
	race._players.erase("a")
	expired["expired"] = true
	race._players["a"] = expired
	race._remove_one_bot()
	check(not race._players.has("a") and race._players.size() == 9 and race._players.has("bot:2"), "countdown admission replaces expired human before earlier bot")
	race._players["a"] = race._new_player("a", "A", 0, false)
	var occupied_slots: Dictionary = {}
	for player: Dictionary in race._players.values():
		occupied_slots[player["slot"]] = true
	check(occupied_slots.size() == 10 and race._players.size() == 10, "replacement preserves exactly ten unique grid slots")
	race._players["expired_waiter"] = race._new_player("expired_waiter", "Waiting", 9, false)
	race._players["expired_waiter"]["spectator"] = true
	race._players["expired_waiter"]["expired"] = true
	race._remove_expired_waiters()
	check(not race._players.has("expired_waiter") and race._players.size() == 10, "expired spectator removed without deleting result entrants")
	race._on_packet(1, {"type": "restart", "race_id": 1})
	check(race._race_id == 1 and not race._players["a"]["ready"], "active repeat cannot reset race")
	race._phase = "results"
	race._players["a"]["finished"] = true
	race._players["a"]["finish_order"] = 1
	race._players["b"]["dnf"] = true
	race._players["b"]["result_progress"] = 500.0
	race._broadcast_snapshot()
	check(race._server.packet["players"][0]["id"] == "a", "finisher precedes DNF")
	check(race._server.packet["players"][1]["id"] == "b" and not race._server.packet["players"][1]["finished"], "DNF remains distinct from finish")
	race._on_packet(1, {"type": "restart", "race_id": 0})
	check(not race._players["a"]["ready"], "stale generation vote ignored")
	race._on_packet(1, {"type": "restart", "race_id": 1})
	race._on_packet(1, {"type": "restart", "race_id": 1})
	check(race._race_id == 1 and race._players["a"]["ready"], "duplicate vote cannot bypass other human")
	race._players["waiting"] = race._new_player("waiting", "Waiting", 9, false)
	race._players["waiting"]["spectator"] = true
	race._players["a"]["accepted"] = 22
	race._players["a"]["queue"].append({"sequence": 22})
	var epoch: int = race._players["a"]["epoch"]
	race._on_packet(2, {"type": "restart", "race_id": 1})
	check(race._race_id == 2 and race._phase == "countdown", "all human votes start one new race")
	check(race._players.size() == 10 and not race._players["waiting"]["spectator"], "waiting human promoted and bots refill remaining slots")
	check(race._players["a"]["epoch"] == epoch + 1 and race._players["a"]["queue"].is_empty() and race._players["a"]["ack"] == 22, "reset clears pending commands and increments epoch")
	check(not race._players["a"]["finished"] and not race._players["a"]["ready"] and not race._players["b"]["dnf"], "prior result and ready state cleared")
	check(race._players["a"]["previous_position"] == race._players["a"]["vehicle"].global_position, "reset sweep begins at actual spawn")
	race._on_packet(2, {"type": "restart", "race_id": 1})
	check(race._race_id == 2, "late duplicate cannot reset new countdown")
	race._phase = "racing"
	race._countdown = 0
	race._race_elapsed = 179.999
	await physics_frame
	race._step_server(1.0 / 60.0)
	check(race._phase == "results" and race._players["a"]["dnf"] and not race._players["a"]["finished"], "race deadline produces terminal DNF without fabricated finish")
	race._players["b"]["connected"] = false
	race._players["b"]["disconnected_at"] = Time.get_ticks_msec() - 30001
	await physics_frame
	race._step_server(1.0 / 60.0)
	check(race._players.has("b") and race._players["b"]["expired"], "expired disconnected entrant remains in result roster")
	race._broadcast_snapshot()
	var previous_order: Array = race._server.packet["players"].map(func(player: Dictionary) -> String: return player["id"])
	race._players["b"]["vehicle"].global_position += Vector3(100.0, 0.0, 100.0)
	race._broadcast_snapshot()
	check(previous_order == race._server.packet["players"].map(func(player: Dictionary) -> String: return player["id"]), "terminal standings are frozen despite later movement")
	for player: Dictionary in race._players.values():
		if not player["is_bot"]:
			player["connected"] = false
			player["disconnected_at"] = Time.get_ticks_msec() - 30001
	await physics_frame
	race._step_server(1.0 / 60.0)
	check(race._players.is_empty() and race._phase == "waiting", "last human grace expiry removes bots and returns idle")
	print("RACE_LIFECYCLE_PROBE_OK checks=%d" % checks)
	quit()
