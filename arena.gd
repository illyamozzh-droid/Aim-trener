extends Node3D
class_name ProceduralArena

signal navigation_baked

@export var arena_size: float = 36.0
@export var wall_height: float = 5.0
@export var bake_navigation: bool = true

var navigation_region: NavigationRegion3D
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_generate_arena()
	if bake_navigation:
		call_deferred("_bake_navigation")

func _generate_arena() -> void:
	_add_box("Floor", Vector3(arena_size, 1.0, arena_size), Vector3(0.0, -0.5, 0.0), Color(0.20, 0.23, 0.26))
	_add_box("NorthWall", Vector3(arena_size, wall_height, 0.7), Vector3(0.0, wall_height * 0.5, -arena_size * 0.5), Color(0.30, 0.33, 0.36))
	_add_box("SouthWall", Vector3(arena_size, wall_height, 0.7), Vector3(0.0, wall_height * 0.5, arena_size * 0.5), Color(0.30, 0.33, 0.36))
	_add_box("EastWall", Vector3(0.7, wall_height, arena_size), Vector3(arena_size * 0.5, wall_height * 0.5, 0.0), Color(0.30, 0.33, 0.36))
	_add_box("WestWall", Vector3(0.7, wall_height, arena_size), Vector3(-arena_size * 0.5, wall_height * 0.5, 0.0), Color(0.30, 0.33, 0.36))
	_add_box("PlatformA", Vector3(8.0, 0.8, 5.0), Vector3(-8.0, 2.0, -7.0), Color(0.25, 0.38, 0.48))
	_add_box("PlatformB", Vector3(7.0, 0.8, 5.0), Vector3(9.0, 3.0, 7.0), Color(0.25, 0.38, 0.48))

	_add_ramp("RampA", Vector3(6.0, 0.45, 5.0), Vector3(-8.0, 0.95, -1.0), deg_to_rad(-18.0))
	_add_ramp("RampB", Vector3(6.0, 0.45, 5.0), Vector3(8.0, 1.45, 1.0), deg_to_rad(18.0))

	for i in range(8):
		var x := _rng.randf_range(-13.0, 13.0)
		var z := _rng.randf_range(-13.0, 13.0)

		if Vector2(x, z).length() < 5.0:
			continue

		_add_box(
			"Cover_%02d" % i,
			Vector3(
				_rng.randf_range(1.5, 3.0),
				_rng.randf_range(1.0, 2.4),
				_rng.randf_range(1.5, 3.0)
			),
			Vector3(x, 0.6, z),
			Color(0.38, 0.34, 0.28)
		)

	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "NavigationRegion3D"

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_max_climb = 0.6
	nav_mesh.agent_max_slope = 42.0

	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = "navmesh_source"

	navigation_region.navigation_mesh = nav_mesh
	add_child(navigation_region)

func _add_box(node_name: String, size: Vector3, position: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.add_to_group("navmesh_source")

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material

	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	add_child(body)

func _add_ramp(node_name: String, size: Vector3, position: Vector3, pitch: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.rotation.x = pitch
	body.add_to_group("navmesh_source")

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.44, 0.48)
	mesh_instance.material_override = material

	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	add_child(body)

func _bake_navigation() -> void:
	if not is_instance_valid(navigation_region) or navigation_region.navigation_mesh == null:
		push_error("NavigationRegion3D or NavigationMesh is missing")
		return

	var region: NavigationRegion3D = navigation_region
	region.bake_navigation_mesh(true)
	await region.bake_finished

	if not is_instance_valid(region):
		push_error("NavigationRegion3D was removed during baking")
		return
	if region.navigation_mesh == null:
		push_error("NavigationMesh disappeared during baking")
		return
	if region.navigation_mesh.get_polygon_count() == 0:
		push_error("NavigationMesh is empty. Check navmesh_source geometry.")
		return

	navigation_baked.emit()
