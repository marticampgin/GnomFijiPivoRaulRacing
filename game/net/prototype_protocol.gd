class_name PrototypeProtocol
extends RefCounted

const VERSION: int = 1
const MATCH_ID: String = "prototype-1"
const LOADOUT_HASH: String = "prototype-v1"
const NEUTRAL: Dictionary = {"steering": 0.0, "throttle": 0.0, "brake": 1.0, "drift": false}


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


static func verify_ticket(ticket: String, secret: String, now: int) -> Dictionary:
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
	if claims.get("v") != VERSION or claims.get("protocol_version") != VERSION:
		return {}
	if claims.get("match_id") != MATCH_ID or claims.get("loadout_hash") != LOADOUT_HASH:
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
	if state.get("version") != VERSION or not _vector_valid(state.get("position")):
		return {}
	if state.get("balance_version") != "vehicle-prototype-v1":
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
