class_name VehicleContacts
extends RefCounted

const PASSES: int = 4
const MARGIN: float = 0.015
const Vehicle = preload("res://vehicle/racing_vehicle.gd")


## Authoritative only. Previous transforms are keyed by body instance ID.
## excluded_bodies supplies other layer-2 karts (spectators/finished racers).
## Godot supplies convex narrowphase/continuous casts; response is equal-mass,
## inelastic and planar, so contacts cannot add kinetic energy or tip a kart.
static func resolve(bodies: Array, previous_transforms: Dictionary, excluded_bodies: Array = [], impacts: Array = []) -> int:
	var contacts: int = 0
	var pair_impacts: Dictionary = {}
	if bodies.size() < 2:
		return contacts
	var all_rids: Array[RID] = []
	for body: CharacterBody3D in bodies + excluded_bodies:
		if not all_rids.has(body.get_rid()):
			all_rids.append(body.get_rid())
	for iteration: int in PASSES:
		for i: int in bodies.size():
			for j: int in range(i + 1, bodies.size()):
				var a: CharacterBody3D = bodies[i]
				var b: CharacterBody3D = bodies[j]
				var contact: Dictionary = _contact(a, b, previous_transforms, iteration == 0, all_rids)
				if contact.is_empty():
					continue
				contacts += 1
				var normal: Vector3 = contact.normal
				var closing: float = (a.velocity - b.velocity).dot(normal)
				if closing < 0.0:
					# Report the strongest approach once per pair, not once per solver pass.
					var key: Vector2i = Vector2i(i, j)
					if -closing > float(pair_impacts.get(key, {}).get("closing", 0.0)):
						pair_impacts[key] = {"a": a, "b": b, "closing": -closing}
					var impulse: Vector3 = normal * (-closing * 0.5)
					a.velocity += impulse
					b.velocity -= impulse
				var distance: float = contact.depth
				if distance > 0.0:
					# CharacterBody terrain masks stay enabled during separation.
					var moved_a: float = _move(a, normal * distance * 0.5).dot(normal)
					var moved_b: float = _move(b, -normal * (distance - moved_a)).dot(-normal)
					if moved_b < distance - moved_a:
						_move(a, normal * maxf(0.0, distance - moved_a - moved_b))
		for body: CharacterBody3D in bodies:
			body.speed_mps = body.velocity.slide(body.up_direction).length()
	impacts.append_array(pair_impacts.values())
	return contacts


static func _move(body: CharacterBody3D, motion: Vector3) -> Vector3:
	var before: Vector3 = body.global_position
	body.move_and_collide(motion)
	return body.global_position - before


static func _contact(a: CharacterBody3D, b: CharacterBody3D, previous: Dictionary, swept: bool, all_rids: Array[RID]) -> Dictionary:
	var relative_end: Vector3 = a.global_position - b.global_position
	var relative_start: Vector3 = relative_end
	if swept:
		var start_a: Transform3D = previous.get(a.get_instance_id(), a.global_transform)
		var start_b: Transform3D = previous.get(b.get_instance_id(), b.global_transform)
		relative_start = start_a.origin - start_b.origin
	var diameter: float = Vehicle.COLLISION_SIZE.length() + MARGIN * 2.0
	if Geometry3D.get_closest_point_to_segment(Vector3.ZERO, relative_start, relative_end).length_squared() > diameter * diameter:
		return {}
	var collider: CollisionShape3D = a.get_child(0) as CollisionShape3D
	var space: PhysicsDirectSpaceState3D = a.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.collision_mask = 2
	query.margin = MARGIN
	# Exclude every layer-2 object except this pair's target, including spectators.
	var excluded: Array[RID] = all_rids.duplicate()
	excluded.erase(b.get_rid())
	if not excluded.has(a.get_rid()):
		excluded.append(a.get_rid())
	query.exclude = excluded
	query.transform = a.global_transform * collider.transform
	var info: Dictionary = space.get_rest_info(query)
	var rewind: float = 0.0
	if swept:
		var old_a: Transform3D = previous.get(a.get_instance_id(), a.global_transform)
		var old_b: Transform3D = previous.get(b.get_instance_id(), b.global_transform)
		var motion_b: Vector3 = b.global_position - old_b.origin
		var relative_motion: Vector3 = a.global_position - old_a.origin - motion_b
		# Work in B's translated frame: both trajectories participate in the cast.
		query.transform = a.global_transform * collider.transform
		query.transform.origin -= relative_motion
		query.motion = relative_motion
		var initial: Dictionary = space.get_rest_info(query)
		if not initial.is_empty():
			info = initial
		elif relative_motion.length_squared() > 0.000001:
			var fractions: PackedFloat32Array = space.cast_motion(query)
			if fractions.size() == 2 and fractions[0] < 1.0:
				query.transform.origin += relative_motion * minf(1.0, fractions[1] + 0.001)
				query.motion = Vector3.ZERO
				var swept_info: Dictionary = space.get_rest_info(query)
				if not swept_info.is_empty():
					info = swept_info
					rewind = (1.0 - fractions[0]) * relative_motion.length()
	if info.is_empty() or info.rid != b.get_rid():
		return {}
	var up: Vector3 = (a.up_direction + b.up_direction).normalized()
	var normal: Vector3 = Vector3(info.normal).slide(up)
	query.transform = a.global_transform * collider.transform
	query.motion = Vector3.ZERO
	if normal.length_squared() < 0.01:
		# A deep respawn overlap's shortest 3D escape is often vertical. First
		# require real overlap, then ask Godot for the planar escape of the same
		# footprint with extra height; this never joins separate bridge decks.
		var real_overlap: Dictionary = space.get_rest_info(query)
		if real_overlap.is_empty() or real_overlap.rid != b.get_rid():
			return {}
		query.transform.basis.y *= 8.0
		if (a.global_position - b.global_position).slide(up).length_squared() < 0.000001:
			var direction: float = 1.0 if a.get_instance_id() < b.get_instance_id() else -1.0
			query.transform.origin += a.global_basis.x.slide(up).normalized() * direction * 0.001
		var planar_info: Dictionary = space.get_rest_info(query)
		if planar_info.is_empty() or planar_info.rid != b.get_rid():
			return {}
		normal = Vector3(planar_info.normal).slide(up)
		if normal.length_squared() < 0.01:
			return {}
	normal = normal.normalized()
	var depth: float = 0.0
	var points: PackedVector3Array = space.collide_shape(query, 8)
	for index: int in range(0, points.size() - 1, 2):
		depth = maxf(depth, absf((points[index] - points[index + 1]).dot(normal)))
	# Only undo the inward component; preserve tangential travel during a scrape.
	if rewind > 0.0:
		var old_a: Transform3D = previous.get(a.get_instance_id(), a.global_transform)
		var old_b: Transform3D = previous.get(b.get_instance_id(), b.global_transform)
		var relative: Vector3 = a.global_position - old_a.origin - b.global_position + old_b.origin
		depth = maxf(depth, rewind * maxf(0.0, -relative.normalized().dot(normal)))
	return {"normal": normal, "depth": depth + MARGIN}
