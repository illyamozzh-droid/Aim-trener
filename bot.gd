extends CharacterBody3D
class_name SimTarget

signal focused(target: SimTarget)
signal target_reached(target: SimTarget)

@export var move_speed: float = 7.0
@export var jump_velocity: float = 5.5
@export var focus_reaction_time: float = 0.45
@export var wander_radius: float = 14.0

var memory: AIMemory
var navigation: NavigationAgent3D
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

var _rng := RandomNumberGenerator.new()
var _origin: Vector3
var _decision_timer: float = 0.0
var _focus_timer: float = 0.0
var _behavior: String = "approach"
var _target_point: Vector3
var _visual: MeshInstance3D
var _shape: CollisionShape3D
var _navigation_initialized: bool = false
var _previous_navigation_finished: bool = true
var _fallback_decision_timer: float = 0.0

func _ready() -> void:
	_rng.randomize()
	_origin = global_position
	_build_nodes()

func _build_nodes() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		_shape = CollisionShape3D.new()
		_shape.name = "CollisionShape3D"

		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.38
		capsule.height = 1.8

		_shape.shape = capsule
		_shape.position.y = 0.9
		add_child(_shape)
	else:
		_shape = get_node("CollisionShape3D") as CollisionShape3D
		if _shape == null:
			push_error("SimTarget: CollisionShape3D has an invalid type")
			return

	if get_node_or_null("NavigationAgent3D") == null:
		navigation = NavigationAgent3D.new()
		navigation.name = "NavigationAgent3D"
		navigation.path_desired_distance = 0.6
		navigation.target_desired_distance = 0.8
		add_child(navigation)
	else:
		navigation = get_node("NavigationAgent3D") as NavigationAgent3D
		if navigation == null:
			push_error("SimTarget: NavigationAgent3D has an invalid type")
			return

	if get_node_or_null("Visual") == null:
		_visual = MeshInstance3D.new()
		_visual.name = "Visual"

		var mesh := CapsuleMesh.new()
		mesh.radius = 0.38
		mesh.height = 1.8

		_visual.mesh = mesh
		_visual.position.y = 0.9

		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.95, 0.55, 0.18)
		_visual.material_override = material

		add_child(_visual)
	else:
		_visual = get_node("Visual") as MeshInstance3D
		if _visual == null:
			push_error("SimTarget: Visual has an invalid type")
			return

func activate_navigation() -> void:
	# Called by the arena manager only after the bake_finished signal.
	if not is_inside_tree() or not is_instance_valid(navigation):
		return
	var navigation_map: RID = navigation.get_navigation_map()
	if not navigation_map.is_valid():
		return
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return
	_navigation_initialized = true
	_pick_destination()

func _move_without_navigation(delta: float) -> void:
	_fallback_decision_timer -= delta
	if _fallback_decision_timer <= 0.0:
		_fallback_decision_timer = _rng.randf_range(1.0, 2.0)
		var offset := Vector3(
			_rng.randf_range(-wander_radius, wander_radius),
			0.0,
			_rng.randf_range(-wander_radius, wander_radius)
		)
		_target_point = _origin + offset
	var direction := _target_point - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.5:
		direction = direction.normalized()
		velocity.x = move_toward(velocity.x, direction.x * move_speed, 10.0 * delta)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, 10.0 * delta)
		look_at(global_position + direction, Vector3.UP)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()

func set_memory(value: AIMemory) -> void:
	memory = value

func _physics_process(delta: float) -> void:
	_decision_timer -= delta
	_focus_timer = maxf(0.0, _focus_timer - delta)

	if not _navigation_initialized:
		_move_without_navigation(delta)
		return

	if not is_instance_valid(navigation):
		_navigation_initialized = false
		_move_without_navigation(delta)
		return

	if _decision_timer <= 0.0:
		_decision_timer = _rng.randf_range(1.2, 2.4)
		_choose_behavior()

	var navigation_finished := navigation.is_navigation_finished()

	if not navigation_finished:
		var next_pos := navigation.get_next_path_position()
		var direction := next_pos - global_position
		direction.y = 0.0

		if direction.length() > 0.1:
			direction = direction.normalized()

			velocity.x = move_toward(
				velocity.x,
				direction.x * move_speed,
				16.0 * delta
			)

			velocity.z = move_toward(
				velocity.z,
				direction.z * move_speed,
				16.0 * delta
			)

			look_at(global_position + direction, Vector3.UP)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)

	if navigation_finished and not _previous_navigation_finished:
		target_reached.emit(self)

	_previous_navigation_finished = navigation_finished

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif _behavior == "evade" and _rng.randf() < 0.012:
		velocity.y = jump_velocity

	move_and_slide()

func _choose_behavior() -> void:
	_behavior = memory.choose_behavior(_rng) if memory != null else ["approach", "circle", "evade"][_rng.randi_range(0, 2)]

	var offset := Vector3(
		_rng.randf_range(-wander_radius, wander_radius),
		0.0,
		_rng.randf_range(-wander_radius, wander_radius)
	)

	match _behavior:
		"approach":
			_target_point = _origin + offset * 0.55

		"circle":
			var angle := _rng.randf_range(0.0, TAU)
			_target_point = _origin + Vector3(cos(angle), 0.0, sin(angle)) * wander_radius

		"evade":
			_target_point = _origin + offset

	_set_navigation_target(_target_point)

func _pick_destination() -> void:
	_target_point = _origin + Vector3(
		_rng.randf_range(-wander_radius, wander_radius),
		0.0,
		_rng.randf_range(-wander_radius, wander_radius)
	)

	_set_navigation_target(_target_point)

func _set_navigation_target(point: Vector3) -> void:
	if not _navigation_initialized or not is_instance_valid(navigation):
		return
	var navigation_map: RID = navigation.get_navigation_map()
	if not navigation_map.is_valid() or NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		_navigation_initialized = false
		return

	var closest_point := NavigationServer3D.map_get_closest_point(
		navigation_map,
		point
	)

	navigation.target_position = closest_point
	_previous_navigation_finished = false

func register_focus() -> void:
	_focus_timer = focus_reaction_time
	focused.emit(self)

	_behavior = "evade"

	var away := global_position - _origin

	if away.length_squared() < 0.1:
		away = Vector3.RIGHT

	_target_point = global_position + away.normalized() * 5.0 + Vector3(
		_rng.randf_range(-3.0, 3.0),
		0.0,
		_rng.randf_range(-3.0, 3.0)
	)

	_set_navigation_target(_target_point)

func get_current_behavior() -> String:
	return _behavior
