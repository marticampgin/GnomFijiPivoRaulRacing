extends SceneTree

const Vehicle = preload("res://vehicle/racing_vehicle.gd")
const Baker = preload("res://track/track_baker.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var body := StaticBody3D.new()
	var floor_collider := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20, 1, 100)
	floor_collider.shape = floor_shape
	body.add_child(floor_collider)
	body.rotation.x = deg_to_rad(6.0)
	body.position.y = 5.0
	root.add_child(body)
	var car := Vehicle.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.25, 0.7, 2.1)
	collider.shape = shape
	car.add_child(collider)
	root.add_child(car)
	car.reset_at(Transform3D(Basis.IDENTITY, Vector3(0, 5.0 - 35.0 * tan(deg_to_rad(6.0)) + 1.0, 35)))
	for tick: int in 600:
		await physics_frame
		car.step({"throttle": 1.0}, 1.0 / 60.0)
		if tick % 120 == 0:
			print("SLOPE_STEP ", JSON.stringify({"tick": tick, "position": Baker.vec(car.position), "velocity": Baker.vec(car.velocity), "grounded": car.grounded, "wall": car.is_on_wall()}))
		if car.position.z < -35.0:
			break
	var passed: bool = car.position.z < -35.0
	print("SLOPE_PROBE ", JSON.stringify({"passed": passed, "position": Baker.vec(car.position)}))
	quit(0 if passed else 1)
