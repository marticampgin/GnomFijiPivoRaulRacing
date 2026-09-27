class_name PrototypeProtocol
extends RefCounted

const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Styles = preload("res://vehicle/driving_styles.gd")
const WIRE_VERSION: int = 5
const TICKET_VERSION: int = 3
const VEHICLE_STATE_VERSION: int = Vehicle.STATE_VERSION
const TRACK_SCHEMA_VERSION: int = 1
const MATCH_ID: String = "prototype-1"
const LOADOUT_HASH: String = "prototype-v8"
const NEUTRAL: Dictionary = {"steering": 0.0, "throttle": 0.0, "brake": 0.0, "drift": false}
# Simulation-only parking command; never serialized as a player input packet.
const BLOCKED: Dictionary = {"steering": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false, "drive_blocked": true}


static func validate_input(data: Dictionary) -> Dictionary:
	if data.size() != 6 or data.get("type") != "input":
		return {}
	var sequence: Variant = data.get("sequence")
	if not _number(sequence) or float(sequence) != floorf(float(sequence)):
		return {}
	if float(sequence) < 1 or float(sequence) > 2147483647:
		return {}
	for key: String in ["steering", "throttle", "brake"]:
		if not _number(data.get(key)):
			return {}
		var minimum: float = -1.0 if key == "steering" else 0.0
		if float(data[key]) < minimum or float(data[key]) > 1.0:
			return {}
	if not data.get("drift") is bool:
		return {}
	return data.duplicate()


static func validate_item_command(data: Dictionary) -> Dictionary:
	if data.size() != 5 or data.get("type") != "use_item":
		return {}
	if not _integer(data.get("sequence"), 1) or not _integer(data.get("race_id"), 1):
		return {}
	if not _integer(data.get("epoch"), 0) or not _integer(data.get("slot"), 0) or int(data["slot"]) > 1:
		return {}
	return data.duplicate()


static func validate_combat(data: Variant) -> Dictionary:
	if not data is Dictionary or data.size() != 7:
		return {}
	if not _bounded(data.get("health"), 0.0, 100.0) or not _number(data.get("max_health")) or data["max_health"] != 100.0:
		return {}
	if not _bounded(data.get("destroyed_remaining"), 0.0, 2.0) or not _bounded(data.get("invulnerable_remaining"), 0.0, 2.0):
		return {}
	if not _integer(data.get("item_ack"), 0):
		return {}
	var slots: Variant = data.get("slots")
	if not slots is Array or slots.size() != 2:
		return {}
	for slot: Variant in slots:
		if not slot is String or not slot in ["", "fanta", "mermaid_rum", "ice_rum", "stroh80", "lays_crab", "bfg10k"]:
			return {}
	var effects: Variant = data.get("effects")
	if not effects is Dictionary or effects.size() > 5:
		return {}
	for key: Variant in effects:
		if not key is String or not key in ["fanta", "mermaid_rum", "ice_rum", "lays_crab", "burn"]:
			return {}
		var effect: Variant = effects[key]
		if not effect is Dictionary or effect.size() != (2 if key == "burn" else 1):
			return {}
		if not _bounded(effect.get("remaining"), 0.0, 4.0 if key == "burn" else 8.0):
			return {}
		if key == "burn" and not _bounded(effect.get("damage"), 0.0, 5.75):
			return {}
	return data.duplicate(true)


static func _bounded(value: Variant, minimum: float, maximum: float) -> bool:
	return _number(value) and float(value) >= minimum and float(value) <= maximum


static func track_identity(manifest: Dictionary) -> Dictionary:
	if not manifest.get("track_id") is String or manifest["track_id"].is_empty() or manifest["track_id"].length() > 64:
		return {}
	if manifest.get("schema_version") != TRACK_SCHEMA_VERSION:
		return {}
	for key: String in ["simulation_revision", "art_revision"]:
		if not _integer(manifest.get(key), 1):
			return {}
	var hash_value: Variant = manifest.get("simulation_hash")
	if not hash_value is String or hash_value.length() != 64:
		return {}
	for character: String in hash_value:
		if not character in "0123456789abcdef":
			return {}
	var result: Dictionary = {}
	for key: String in ["track_id", "schema_version", "simulation_revision", "simulation_hash", "art_revision"]:
		result[key] = manifest[key]
	return result


static func compatibility(manifest: Dictionary) -> Dictionary:
	var track: Dictionary = track_identity(manifest)
	if track.is_empty():
		return {}
	return {"protocol_version": WIRE_VERSION, "vehicle_state_version": VEHICLE_STATE_VERSION, "loadout_hash": LOADOUT_HASH, "track": track}


static func compatible(descriptor: Dictionary, expected_track: Dictionary) -> bool:
	if descriptor.get("protocol_version") != WIRE_VERSION or descriptor.get("vehicle_state_version") != VEHICLE_STATE_VERSION:
		return false
	if descriptor.get("loadout_hash") != LOADOUT_HASH or not descriptor.get("track") is Dictionary:
		return false
	var actual: Dictionary = track_identity(descriptor["track"])
	var expected: Dictionary = track_identity(expected_track)
	if actual.is_empty() or expected.is_empty():
		return false
	# Art can change independently; every simulation field must still agree.
	for key: String in ["track_id", "schema_version", "simulation_revision", "simulation_hash"]:
		if actual[key] != expected[key]:
			return false
	return true


static func validate_hello(data: Dictionary, expected_track: Dictionary) -> bool:
	return (data.size() == 3 and data.get("type") == "join" and data.get("ticket") is String
		and data.get("compatibility") is Dictionary and compatible(data["compatibility"], expected_track))


static func validate_welcome(data: Dictionary, expected_track: Dictionary) -> bool:
	return (data.get("type") == "welcome" and data.get("player_id") is String
		and not data["player_id"].is_empty() and data["player_id"].length() <= 128
		and _integer(data.get("ack"), 0) and data.get("compatibility") is Dictionary
		and (not data.has("item_ack") or _integer(data["item_ack"], 0))
		and compatible(data["compatibility"], expected_track))


static func verify_ticket(ticket: String, secret: String, now: int, expected_track: Dictionary) -> Dictionary:
	if ticket.length() > 2048 or secret.length() < 32:
		return {}
	var parts: PackedStringArray = ticket.split(".")
	if parts.size() != 2 or parts[0].is_empty() or parts[1].length() != 43:
		return {}
	for part: String in parts:
		for character: String in part:
			if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_":
				return {}
	var signature: PackedByteArray = _base64url_decode(parts[1])
	var context: HMACContext = HMACContext.new()
	if context.start(HashingContext.HASH_SHA256, secret.to_utf8_buffer()) != OK:
		return {}
	context.update(parts[0].to_utf8_buffer())
	var expected: PackedByteArray = context.finish()
	if signature.size() != expected.size():
		return {}
	var difference: int = 0
	for index: int in expected.size():
		difference |= signature[index] ^ expected[index]
	if difference != 0:
		return {}
	var parsed: Variant = JSON.parse_string(_base64url_decode(parts[0]).get_string_from_utf8())
	if not parsed is Dictionary:
		return {}
	var claims: Dictionary = parsed
	if claims.get("v") != TICKET_VERSION or not compatible(claims, expected_track):
		return {}
	if claims.get("match_id") != MATCH_ID or claims.get("loadout_hash") != LOADOUT_HASH:
		return {}
	if not Styles.is_valid(claims.get("style_id")):
		return {}
	if not _number(claims.get("expires_at")) or float(claims["expires_at"]) != floorf(float(claims["expires_at"])):
		return {}
	var expiry: int = int(claims["expires_at"])
	if expiry <= now or expiry > now + 120:
		return {}
	for key: String in ["player_id", "display_name", "jti"]:
		if not claims.get(key) is String or claims[key].is_empty() or claims[key].length() > 128:
			return {}
	return claims


static func pack_state(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate()
	var transform: Transform3D = state["transform"]
	result["position"] = _pack_vector(transform.origin)
	result["basis"] = [_pack_vector(transform.basis.x), _pack_vector(transform.basis.y), _pack_vector(transform.basis.z)]
	result.erase("transform")
	result["velocity"] = _pack_vector(state["velocity"])
	result["up_direction"] = _pack_vector(state["up_direction"])
	return result


static func unpack_state(state: Dictionary) -> Dictionary:
	if state.get("version") != VEHICLE_STATE_VERSION or not _vector_valid(state.get("position")):
		return {}
	if state.get("balance_version") != Vehicle.BALANCE_VERSION:
		return {}
	for key: String in ["grounded", "is_drifting", "drift_was_pressed"]:
		if not state.get(key) is bool:
			return {}
	for key: String in ["drift_charge", "boost_remaining", "steering_amount"]:
		if not _number(state.get(key)):
			return {}
	if float(state["drift_charge"]) < 0.0 or float(state["drift_charge"]) > 1.0:
		return {}
	if float(state["boost_remaining"]) < 0.0 or float(state["boost_remaining"]) > 2.0 or absf(float(state["steering_amount"])) > 1.0:
		return {}
	if not _vector_valid(state.get("velocity")) or not _vector_valid(state.get("up_direction")):
		return {}
	var basis_data: Variant = state.get("basis")
	if not basis_data is Array or basis_data.size() != 3:
		return {}
	for axis: Variant in basis_data:
		if not _vector_valid(axis):
			return {}
	var result: Dictionary = state.duplicate()
	var basis: Basis = Basis(_unpack_vector(basis_data[0]), _unpack_vector(basis_data[1]), _unpack_vector(basis_data[2]))
	if absf(basis.determinant()) < 0.001:
		return {}
	result["transform"] = Transform3D(basis.orthonormalized(), _unpack_vector(state["position"]))
	result["velocity"] = _unpack_vector(state["velocity"])
	result["up_direction"] = _unpack_vector(state["up_direction"])
	return result


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= 2147483647


static func _pack_vector(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]


static func _unpack_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _vector_valid(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate: Variant in value:
		if not _number(coordinate) or absf(float(coordinate)) > 1000000.0:
			return false
	return true


static func _base64url_decode(value: String) -> PackedByteArray:
	var padded: String = value.replace("-", "+").replace("_", "/")
	while padded.length() % 4 != 0:
		padded += "="
	return Marshalls.base64_to_raw(padded)
