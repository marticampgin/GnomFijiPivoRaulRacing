class_name DrivingStyles
extends RefCounted

const IDS: Array[String] = ["handling", "acceleration", "speed", "drift"]
const DEFAULT_ID: String = "handling"
const PROFILES: Dictionary = {
	"handling": {"label": "Handling", "stats": {"top_speed": 32.0, "acceleration": 17.0, "handling": 1.18, "drift": 1.0, "durability": 100.0}},
	"acceleration": {"label": "Acceleration", "stats": {"top_speed": 32.0, "acceleration": 21.0, "handling": 1.0, "drift": 1.0, "durability": 100.0}},
	"speed": {"label": "Speed", "stats": {"top_speed": 37.0, "acceleration": 15.0, "handling": 0.92, "drift": 1.0, "durability": 100.0}},
	"drift": {"label": "Drift", "stats": {"top_speed": 33.0, "acceleration": 16.0, "handling": 1.0, "drift": 1.5, "durability": 100.0}},
}


static func is_valid(id: Variant) -> bool:
	return id is String and IDS.has(id)


static func stats_for(id: String) -> Dictionary:
	return PROFILES.get(id, PROFILES[DEFAULT_ID])["stats"].duplicate(true)


static func describe_all() -> Array:
	var descriptions: Array = []
	for id: String in IDS:
		descriptions.append({"id": id, "label": PROFILES[id]["label"], "stats": stats_for(id)})
	return descriptions
