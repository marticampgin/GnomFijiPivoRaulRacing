extends RefCounted

const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Baker = preload("res://track/track_baker.gd")


static func find_pose(track: Node3D, player: Dictionary, players: Dictionary) -> Variant:
	var progress: Dictionary = player.progress
	var anchor: Dictionary = track.data.recovery[int(progress.confirmed_gate) + 1]
	var length: float = track.data.length
	var end: float = length if int(progress.expected_gate) == 0 else float(track.data.gates[int(progress.expected_gate)].s)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = Vehicle.create_collision_shape()
	query.collision_mask = 1
	query.margin = 0.04
	var space: PhysicsDirectSpaceState3D = track.get_world_3d().direct_space_state
	var clearance: float = Vehicle.COLLISION_SIZE.length() + 0.15
	# Before the start, search backward; elsewhere stay inside the confirmed interval.
	for row: int in 7:
		var s: float = float(anchor.s) + float(row) * 4.0 * (-1.0 if not progress.started else 1.0)
		if s < 0.0 or s >= end - 2.0:
			continue
		var sample: Dictionary = track.sample_at(s)
		var forward: Vector3 = Baker.vector(sample.tangent)
		forward.y = 0.0
		var basis := Basis.looking_at(forward.normalized(), Vector3.UP)
		for lane: float in [0.0, -3.8, 3.8]:
			if absf(lane) + Vehicle.COLLISION_SIZE.x * 0.5 + 0.3 > float(sample.width) * 0.5:
				continue
			for lift: float in [0.65, 1.0]:
				var pose := Transform3D(basis, Baker.vector(sample.position) + basis.x * lane + Vector3.UP * lift)
				var occupied: bool = false
				# Read current transforms: earlier recoveries in this tick must reserve their pose immediately.
				for other: Dictionary in players.values():
					if other.id != player.id and pose.origin.distance_to(other.vehicle.global_position) < clearance:
						occupied = true
						break
				if occupied:
					continue
				query.transform = pose
				if not space.intersect_shape(query, 1).is_empty():
					continue
				var ray := PhysicsRayQueryParameters3D.create(pose.origin, pose.origin - Vector3.UP * 2.0, 1)
				var ground: Dictionary = space.intersect_ray(ray)
				if not ground.is_empty() and ground.normal.dot(Vector3.UP) > 0.7:
					return pose
	return null
