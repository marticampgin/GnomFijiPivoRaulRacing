extends SceneTree

const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Contacts = preload("res://vehicle/vehicle_contacts.gd")
var world: Node3D
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var a: CharacterBody3D = _car(Vector3(0, 1, 0))
	var b: CharacterBody3D = _car(Vector3(0, 1, -2))
	await physics_frame
	a.velocity = Vector3(0, 0, -30)
	b.velocity = Vector3(0, 0, -10)
	Contacts.resolve([a, b], {})
	_check(a.velocity.z > -30 and b.velocity.z < -10, "rear impact slows rear and accelerates front")
	_check(absf(a.velocity.z + b.velocity.z + 40) < 0.001, "equal masses conserve planar momentum")
	_check(a.velocity.length_squared() + b.velocity.length_squared() <= 1000.01, "impact never creates energy")
	var energy: float = a.velocity.length_squared() + b.velocity.length_squared()
	for frame: int in 8:
		Contacts.resolve([a, b], {})
	_check(a.velocity.length_squared() + b.velocity.length_squared() <= energy + 0.001, "resting contact has no repeated kick")
	a.position = Vector3(0, 1, 0)
	b.position = Vector3(0, 1, -2)
	a.velocity = Vector3(0, 0, -30)
	b.velocity = Vector3(0, 0, 30)
	await physics_frame
	Contacts.resolve([a, b], {})
	_check(a.velocity.length() < 1 and b.velocity.length() < 1, "head-on impact slows both")
	a.position = Vector3(0, 1, 0)
	b.position = Vector3(Vehicle.COLLISION_SIZE.x - 0.15, 1, 0)
	a.velocity = Vector3(10, 0, -20)
	b.velocity = Vector3(0, 0, -20)
	await physics_frame
	Contacts.resolve([a, b], {})
	_check(a.velocity.x < 10 and b.velocity.x > 0, "side impact transfers lateral momentum")
	_check(a.global_basis.y == Vector3.UP and b.global_basis.y == Vector3.UP, "contacts never rotate or flip")
	a.position = Vector3(0, 1, 0)
	b.position = Vector3(0, 8, 0)
	a.velocity = Vector3(0, 0, -30)
	b.velocity = Vector3.ZERO
	await physics_frame
	_check(Contacts.resolve([a, b], {}) == 0 and b.velocity == Vector3.ZERO, "separate bridge elevations do not collide")
	a.position = Vector3(0, 1, 3)
	b.position = Vector3(0, 1, -3)
	var before: Dictionary = {a.get_instance_id(): a.global_transform, b.get_instance_id(): b.global_transform}
	a.position.z = -3
	b.position.z = 3
	a.velocity = Vector3(0, 0, -90)
	b.velocity = Vector3(0, 0, 90)
	await physics_frame
	Contacts.resolve([a, b], before)
	_check(a.velocity.length() < 1 and b.velocity.length() < 1, "relative sweep catches two moving cars")
	_check(a.position.z > b.position.z, "sweep prevents exchanging sides")
	a.position = Vector3(0, 1, 0)
	b.position = Vector3(0, 1, -(Vehicle.COLLISION_SIZE.z - 0.15))
	var c: CharacterBody3D = _car(Vector3(0, 1, -(Vehicle.COLLISION_SIZE.z - 0.15) * 2.0))
	a.velocity = Vector3(0, 0, -30)
	b.velocity = Vector3.ZERO
	c.velocity = Vector3.ZERO
	await physics_frame
	Contacts.resolve([a, b, c], {})
	_check(c.velocity.z < 0, "three-car pack propagates contact")
	_check(a.velocity.length_squared() + b.velocity.length_squared() + c.velocity.length_squared() <= 900.01, "pack does not gain energy")
	c.position = Vector3(30, 1, 30)
	var wall := StaticBody3D.new()
	var wall_collider := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(1, 4, 10)
	wall_collider.shape = wall_shape
	wall.add_child(wall_collider)
	wall.position = Vector3(2, 1, 0)
	world.add_child(wall)
	var wall_limit: float = 1.5 - Vehicle.COLLISION_SIZE.x * 0.5
	a.position = Vector3(wall_limit - Vehicle.COLLISION_SIZE.x + 0.25, 1, 0)
	b.position = Vector3(wall_limit - 0.02, 1, 0)
	a.velocity = Vector3(10, 0, 0)
	b.velocity = Vector3.ZERO
	await physics_frame
	Contacts.resolve([a, b], {})
	_check(b.position.x <= wall_limit + 0.02, "separation does not push a car through terrain wall")
	_check(b.position.x - a.position.x > Vehicle.COLLISION_SIZE.x - 0.15, "wall-pinned car gives separation remainder to other car")
	a.position = Vector3(-10, 1, 0)
	b.position = Vector3(-10, 1, -2)
	c.position = a.position
	a.velocity = Vector3(0, 0, -30)
	b.velocity = Vector3.ZERO
	c.velocity = Vector3.ZERO
	await physics_frame
	Contacts.resolve([a, b], {}, [c])
	_check(b.velocity.z < 0 and c.velocity == Vector3.ZERO, "spectator exclusion cannot mask an active pair or apply impulse")
	a.position = Vector3(-30, 1, 0)
	b.position = Vector3(-28.4, 1, 0)
	a.velocity = Vector3(10, 0, 0)
	b.velocity = Vector3.ZERO
	await physics_frame
	Contacts.resolve([a, b], {}, [c])
	_check(a.velocity.x < 10 and b.velocity.x > 0, "visible 2.18m-wide karts collide before side silhouettes overlap")
	a.position = Vector3(-30, 1, 0)
	b.position = Vector3(-30, 1, -2.4)
	a.velocity = Vector3(0, 0, -30)
	b.velocity = Vector3.ZERO
	await physics_frame
	Contacts.resolve([a, b], {}, [c])
	_check(a.velocity.z > -30 and b.velocity.z < 0, "visible 2.696m-long karts collide before bumpers overlap")
	a.position = Vector3(-50, 1, 0)
	b.position = Vector3(-50, 1, 0)
	a.velocity = Vector3.ZERO
	b.velocity = Vector3.ZERO
	await physics_frame
	Contacts.resolve([a, b], {}, [c])
	_check(a.position.distance_to(b.position) > Vehicle.COLLISION_SIZE.x - 0.15, "coincident respawn karts separate horizontally")
	_check(a.position.y == 1.0 and b.position.y == 1.0 and a.velocity == Vector3.ZERO and b.velocity == Vector3.ZERO, "deep separation adds no vertical kick or energy")
	var coincident_a: Vector3 = a.position
	var coincident_b: Vector3 = b.position
	a.position = Vector3(-50, 1, 0)
	b.position = Vector3(-50, 1, 0)
	await physics_frame
	Contacts.resolve([b, a], {}, [c])
	_check(a.position.distance_to(coincident_a) < 0.01 and b.position.distance_to(coincident_b) < 0.01, "coincident identity tie-break is stable when pair order reverses")
	a.position = Vector3(-50, 1, 0)
	b.position = Vector3(-49.7, 1, 0)
	await physics_frame
	Contacts.resolve([a, b], {}, [c])
	_check(b.position.x - a.position.x > Vehicle.COLLISION_SIZE.x - 0.15, "deep offset overlap separates along planar narrowphase normal")
	a.position = Vector3(-50, 1, 0)
	b.position = Vector3(-50, 1.9, 0)
	await physics_frame
	_check(Contacts.resolve([a, b], {}, [c]) == 0, "tall planar fallback never creates contact across a vertical gap")
	print("VEHICLE_CONTACTS_PROBE ", JSON.stringify({"checks": checks, "failures": failures}))
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _car(location: Vector3) -> CharacterBody3D:
	var body: CharacterBody3D = Vehicle.new()
	var collider := CollisionShape3D.new()
	collider.shape = Vehicle.create_collision_shape()
	body.add_child(collider)
	body.collision_layer = 2
	body.collision_mask = 1
	body.position = location
	world.add_child(body)
	return body


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
