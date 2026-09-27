class_name ItemCatalog
extends RefCounted

const IDS: Array[String] = ["fanta", "mermaid_rum", "ice_rum", "stroh80", "lays_crab", "bfg10k"]
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
