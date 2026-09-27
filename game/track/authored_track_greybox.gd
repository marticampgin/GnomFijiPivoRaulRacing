extends Node3D

const Baker = preload("res://track/track_baker.gd")


func build(data: Dictionary) -> void:
	name = "RouteGreybox"
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point: Array in data.collision.road_faces:
		surface.add_vertex(Baker.vector(point))
	surface.generate_normals()
	var road := MeshInstance3D.new()
	road.mesh = surface.commit()
	var road_material := StandardMaterial3D.new()
	road_material.albedo_color = Color("919a9b")
	road_material.roughness = 0.95
	road.material_override = road_material
	add_child(road)
	var barrier_mesh := BoxMesh.new()
	barrier_mesh.size = Vector3.ONE
	var barriers := MultiMesh.new()
	barriers.transform_format = MultiMesh.TRANSFORM_3D
	barriers.mesh = barrier_mesh
	barriers.instance_count = data.collision.barriers.size()
	for index: int in data.collision.barriers.size():
		var item: Dictionary = data.collision.barriers[index]
		var basis: Basis = Basis.looking_at(Baker.vector(item.forward), Vector3.UP).scaled_local(Baker.vector(item.size))
		barriers.set_instance_transform(index, Transform3D(basis, Baker.vector(item.position)))
	var barrier_visual := MultiMeshInstance3D.new()
	barrier_visual.multimesh = barriers
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("d1d7cd")
	barrier_visual.material_override = stone
	add_child(barrier_visual)
	var colors: Array[Color] = [Color("e6c44f"), Color("379368"), Color("4da8bd"), Color("cf7164")]
	for index: int in data.camera_anchors.size():
		var anchor: Dictionary = data.camera_anchors[index]
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, 5.0, 1.0)
		marker.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[index]
		marker.material_override = material
		marker.position = Baker.vector(anchor.position) + Baker.vector(anchor.forward).cross(Vector3.UP).normalized() * 9.0 + Vector3.UP * 2.5
		add_child(marker)
