extends CharacterBody3D
class_name SimPlayer

signal action_recorded(direction: Vector3, jumped: bool, slid: bool, focused: bool)

@export var move_speed: float = 7.0
@export var acceleration: float = 18.0
@export var air_acceleration: float = 6.0
@export var jump_velocity: float = 5.5
@export var mouse_sensitivity: float = 0.0025
@export var focus_distance: float = 80.0
@export var slide_speed: float = 11.0
@export var slide_duration: float = 0.65

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var move_input: Vector2 = Vector2.ZERO
var look_input: Vector2 = Vector2.ZERO
var slide_timer: float = 0.0
var is_sliding: bool = false
var can_focus: bool = true
var _focus_cooldown: float = 0.0

var _capsule: CollisionShape3D
var _camera_pivot: Node3D
var _camera: Camera3D

var _stand_height: float = 1.8
var _slide_height: float = 1.0
var _look_pitch: float = 0.0

func _ready() -> void:
	_build_body_if_needed()
	# Mouse capture is not useful on touch devices and can interfere with
	# platform input. Keep desktop capture only.
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_body_if_needed() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		_capsule = CollisionShape3D.new()
		_capsule.name = "CollisionShape3D"

		var shape := CapsuleShape3D.new()
		shape.radius = 0.38
		shape.height = _stand_height

		_capsule.shape = shape
		_capsule.position.y = _stand_height * 0.5
		add_child(_capsule)
	else:
		_capsule = get_node("CollisionShape3D") as CollisionShape3D
		if _capsule == null:
			push_error("SimPlayer: CollisionShape3D has an invalid type")
			return

	if get_node_or_null("CameraPivot") == null:
		_camera_pivot = Node3D.new()
		_camera_pivot.name = "CameraPivot"
		_camera_pivot.position.y = 1.55
		add_child(_camera_pivot)
	else:
		_camera_pivot = get_node("CameraPivot") as Node3D

	if _camera_pivot == null:
		push_error("SimPlayer: CameraPivot could not be created")
		return

	if _camera_pivot.get_node_or_null("Camera3D") == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.current = true
		_camera_pivot.add_child(_camera)
	else:
		_camera = _camera_pivot.get_node("Camera3D") as Camera3D
		if _camera == null:
			push_error("SimPlayer: Camera3D has an invalid type")
			return

func set_move_input(value: Vector2) -> void:
	move_input = value.limit_length(1.0)

func add_look_input(value: Vector2) -> void:
	look_input += value

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			add_look_input(event.relative)

	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	_apply_look()

	_focus_cooldown = maxf(0.0, _focus_cooldown - delta)

	var input_dir := move_input

	if input_dir == Vector2.ZERO:
		input_dir = Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_back"
		)

	var basis := global_transform.basis
	var wish := (-basis.z * input_dir.y + basis.x * input_dir.x)

	wish.y = 0.0
	wish = wish.normalized()

	var target_speed := slide_speed if is_sliding else move_speed
	var target_velocity := wish * target_speed
	var accel := acceleration if is_on_floor() else air_acceleration

	if is_sliding:
		slide_timer -= delta

		if slide_timer <= 0.0:
			_end_slide()
	else:
		velocity.x = move_toward(
			velocity.x,
			target_velocity.x,
			accel * delta
		)

		velocity.z = move_toward(
			velocity.z,
			target_velocity.z,
			accel * delta
		)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		jump()

	move_and_slide()

func _apply_look() -> void:
	if look_input != Vector2.ZERO:
		rotate_y(-look_input.x * mouse_sensitivity)

		_look_pitch = clampf(
			_look_pitch - look_input.y * mouse_sensitivity,
			deg_to_rad(-80),
			deg_to_rad(80)
		)

		if is_instance_valid(_camera_pivot):
			_camera_pivot.rotation.x = _look_pitch
		look_input = Vector2.ZERO

func jump() -> void:
	if is_on_floor():
		velocity.y = jump_velocity
		action_recorded.emit(
			Vector3(velocity.x, 0.0, velocity.z),
			true,
			false,
			false
		)

func start_slide() -> void:
	if is_sliding or not is_on_floor():
		return

	is_sliding = true
	slide_timer = slide_duration

	_set_capsule_height(_slide_height)

	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)

	if flat_velocity.length() < 1.0:
		flat_velocity = -global_transform.basis.z * move_speed

	flat_velocity = flat_velocity.normalized() * slide_speed

	velocity.x = flat_velocity.x
	velocity.z = flat_velocity.z

	action_recorded.emit(flat_velocity, false, true, false)

func _end_slide() -> void:
	if not _has_standing_room():
		slide_timer = 0.1
		return

	is_sliding = false
	_set_capsule_height(_stand_height)

func _set_capsule_height(height: float) -> void:
	if not is_instance_valid(_capsule):
		return
	var shape := _capsule.shape as CapsuleShape3D

	if shape == null:
		return

	shape.height = height
	_capsule.position.y = height * 0.5

func _has_standing_room() -> bool:
	var world := get_world_3d()
	if world == null or not is_instance_valid(_capsule):
		return true
	var query := PhysicsShapeQueryParameters3D.new()

	var shape := CapsuleShape3D.new()
	shape.radius = 0.37
	shape.height = _stand_height

	query.shape = shape
	query.transform = Transform3D(
		Basis.IDENTITY,
		global_position + Vector3.UP * (_stand_height * 0.5)
	)

	query.exclude = [get_rid()]
	query.collision_mask = collision_mask

	return world.direct_space_state.intersect_shape(query, 1).is_empty()

func focus_target() -> void:
	if _focus_cooldown > 0.0 or not is_instance_valid(_camera):
		return
	var world := get_world_3d()
	if world == null:
		return

	_focus_cooldown = 0.12

	var from := _camera.global_position
	var to := from + (-_camera.global_transform.basis.z * focus_distance)

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = true

	var hit := world.direct_space_state.intersect_ray(query)
	var focused := false

	if not hit.is_empty():
		var collider: Object = hit.get("collider")

		if is_instance_valid(collider) and collider.has_method("register_focus"):
			collider.call("register_focus")
			focused = true

	action_recorded.emit(
		Vector3(velocity.x, 0.0, velocity.z),
		false,
		false,
		focused
	)

func get_camera() -> Camera3D:
	return _camera
