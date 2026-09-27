class_name ItemCatalog
extends RefCounted

const IDS: Array[String] = ["fanta", "mermaid_rum", "ice_rum", "stroh80", "lays_crab", "bfg10k"]
# Versioned MVP balance baseline, not a guaranteed comeback for trailing racers.
const LOOT_VERSION: int = 1
const LOOT_GAP_METERS: float = 150.0
const TRAILING_WEIGHTS: Dictionary = {
	"fanta": 1.40, "mermaid_rum": 1.05, "ice_rum": 1.20,
	"stroh80": 1.15, "lays_crab": 0.90, "bfg10k": 1.25,
}
const DEFINITIONS: Dictionary = {
	"fanta": {"duration": 4.0, "speed": 1.30},
	"mermaid_rum": {"repair": 50.0, "duration": 4.0, "blur": 0.2},
	"ice_rum": {"repair": 15.0, "duration": 5.0, "speed": 1.15, "blur": 0.5},
	"stroh80": {"radius": 5.0, "damage": 25.0, "burn_damage": 5.0, "burn_duration": 4.0, "speed": 25.0, "gravity": 12.0},
	"lays_crab": {"duration": 8.0, "damage_multiplier": 1.15},
	"bfg10k": {"radius": 9.0, "damage": 55.0, "speed": 42.0, "gravity": 0.0},
}


static func definition(id: String) -> Dictionary:
	return DEFINITIONS.get(id, {}).duplicate(true)


static func loot_weights(place: int, racers: int, leader_gap: float) -> Dictionary:
	var rank_factor: float = clampf(float(place - 1) / float(maxi(1, racers - 1)), 0.0, 1.0)
	var gap_factor: float = clampf(leader_gap / LOOT_GAP_METERS, 0.0, 1.0) if is_finite(leader_gap) else 0.0
	var support: float = rank_factor * 0.65 + gap_factor * 0.35
	var result: Dictionary = {}
	for id: String in IDS:
		result[id] = lerpf(1.0, float(TRAILING_WEIGHTS[id]), support)
	return result
