extends Node3D

const ROUND_DURATION: float = 30.0
const TARGET_COUNT: int = 3
const TARGET_RADIUS: float = 0.52
const SHOT_DISTANCE: float = 60.0
const LOOK_SENSITIVITY: float = 0.0022
const MAX_PITCH: float = 1.3962634
const TARGET_GROUP: StringName = &"aim_targets"

const GRID_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 color_a : source_color = vec3(0.018, 0.030, 0.048);
uniform vec3 color_b : source_color = vec3(0.030, 0.050, 0.072);
uniform vec3 grid_color : source_color = vec3(0.095, 0.155, 0.190);
uniform vec2 cell_count = vec2(22.0, 22.0);
uniform float line_width = 0.025;
void fragment() {
    vec2 grid_uv = UV * cell_count;
    vec2 cell_id = floor(grid_uv);
    vec2 cell_uv = fract(grid_uv);
    float checker = mod(cell_id.x + cell_id.y, 2.0);
    vec3 base_color = mix(color_a, color_b, checker * 0.16);
    vec2 edge_distance = min(cell_uv, vec2(1.0) - cell_uv);
    float nearest_edge = min(edge_distance.x, edge_distance.y);
    float grid_line = 1.0 - smoothstep(line_width, line_width * 1.8, nearest_edge);
    ALBEDO = mix(base_color, grid_color, grid_line * 0.85);
}
"""

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _grid_shader: Shader
var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _camera: Camera3D
var _targets: Array[Area3D] = []

var _hud_layer: CanvasLayer
var _hud_root: Control
var _hud_label: Label
var _fire_button: Button
var _instructions_label: Label
var _result_overlay: ColorRect
var _result_label: Label
var _restart_button: Button

var _score: int = 0
var _shots: int = 0
var _hits: int = 0
var _time_left: float = ROUND_DURATION
var _round_finished: bool = false
var _pitch: float = 0.0
var _last_displayed_second: int = -1
var _visibility_check_timer: float = 0.0

# Finger ID currently controlling camera rotation. A different finger can
# press the FIRE button because GUI controls are not captured as aim input.
var _aim_touch_index: int = -1


func _ready() -> void:
    _rng.randomize()
    Input.emulate_mouse_from_touch = false
    _create_environment()
    _create_room()
    _create_camera()
    _create_targets()
    _create_hud()
    _start_round()


func _process(delta: float) -> void:
    if _round_finished:
        return
    _time_left = maxf(0.0, _time_left - delta)
    var seconds_left: int = int(ceil(_time_left))
    if seconds_left != _last_displayed_second:
        _last_displayed_second = seconds_left
        _update_hud()
    _visibility_check_timer += delta
    if _visibility_check_timer >= 0.25:
        _visibility_check_timer = 0.0
        _ensure_targets_in_view()
    if _time_left <= 0.0:
        _finish_round()


func _create_environment() -> void:
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.008, 0.014, 0.026, 1.0)
    var world_environment := WorldEnvironment.new()
    world_environment.name = "WorldEnvironment"
    world_environment.environment = environment
    add_child(world_environment)


func _create_room() -> void:
    _grid_shader = Shader.new()
    _grid_shader.code = GRID_SHADER_CODE
    _add_grid_plane("Floor", Vector2(30.0, 44.0), Vector3.ZERO, Vector3.ZERO, Vector2(22.0, 32.0))
    _add_grid_plane("BackWall", Vector2(30.0, 12.0), Vector3(0.0, 6.0, -22.0), Vector3(deg_to_rad(90.0), 0.0, 0.0), Vector2(22.0, 9.0))
    _add_grid_plane("FrontWall", Vector2(30.0, 12.0), Vector3(0.0, 6.0, 22.0), Vector3(deg_to_rad(-90.0), 0.0, 0.0), Vector2(22.0, 9.0))
    _add_grid_plane("LeftWall", Vector2(12.0, 44.0), Vector3(-15.0, 6.0, 0.0), Vector3(0.0, 0.0, deg_to_rad(-90.0)), Vector2(9.0, 32.0))
    _add_grid_plane("RightWall", Vector2(12.0, 44.0), Vector3(15.0, 6.0, 0.0), Vector3(0.0, 0.0, deg_to_rad(90.0)), Vector2(9.0, 32.0))


func _add_grid_plane(plane_name: String, plane_size: Vector2, plane_position: Vector3, plane_rotation: Vector3, cell_count: Vector2) -> void:
    var plane_mesh := PlaneMesh.new()
    plane_mesh.size = plane_size
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = plane_name
    mesh_instance.mesh = plane_mesh
    mesh_instance.position = plane_position
    mesh_instance.rotation = plane_rotation
    var material := ShaderMaterial.new()
    material.shader = _grid_shader
    material.set_shader_parameter("cell_count", cell_count)
    mesh_instance.material_override = material
    add_child(mesh_instance)


func _create_camera() -> void:
    _yaw_pivot = Node3D.new()
    _yaw_pivot.name = "YawPivot"
    add_child(_yaw_pivot)
    _pitch_pivot = Node3D.new()
    _pitch_pivot.name = "PitchPivot"
    _pitch_pivot.position = Vector3(0.0, 1.65, 0.0)
    _yaw_pivot.add_child(_pitch_pivot)
    _camera = Camera3D.new()
    _camera.name = "Camera3D"
    _camera.current = true
    _camera.fov = 82.0
    _camera.near = 0.05
    _camera.far = SHOT_DISTANCE
    _pitch_pivot.add_child(_camera)


func _create_targets() -> void:
    var target_colors: Array[Color] = [
        Color(0.15, 0.91, 0.82, 1.0),
        Color(1.0, 0.34, 0.48, 1.0),
        Color(1.0, 0.76, 0.22, 1.0)
    ]
    for index in range(TARGET_COUNT):
        var target := Area3D.new()
        target.name = "Target_%02d" % (index + 1)
        target.collision_layer = 1
        target.collision_mask = 0
        target.add_to_group(TARGET_GROUP)
        var collision := CollisionShape3D.new()
        collision.name = "CollisionShape3D"
        var sphere_shape := SphereShape3D.new()
        sphere_shape.radius = TARGET_RADIUS
        collision.shape = sphere_shape
        target.add_child(collision)
        var sphere_mesh := SphereMesh.new()
        sphere_mesh.radius = TARGET_RADIUS
        sphere_mesh.height = TARGET_RADIUS * 2.0
        sphere_mesh.radial_segments = 16
        sphere_mesh.rings = 8
        var visual := MeshInstance3D.new()
        visual.name = "Visual"
        visual.mesh = sphere_mesh
        var target_material := StandardMaterial3D.new()
        target_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        target_material.albedo_color = target_colors[index % target_colors.size()]
        visual.material_override = target_material
        target.add_child(visual)
        add_child(target)
        _targets.append(target)
        _place_target(target)


func _place_target(target: Area3D) -> void:
    if not is_instance_valid(target) or not is_instance_valid(_camera):
        return

    var chosen_position: Vector3 = _camera.global_transform * Vector3(0.0, 0.0, -13.0)
    const MIN_TARGET_Y: float = TARGET_RADIUS + 0.18
    const MAX_TARGET_Y: float = 12.0 - TARGET_RADIUS - 0.18

    for attempt in range(24):
        var local_position := Vector3(
            _rng.randf_range(-5.0, 5.0),
            _rng.randf_range(-1.35, 2.15),
            -_rng.randf_range(10.5, 16.5)
        )
        var candidate: Vector3 = _camera.global_transform * local_position
        # Floor is at world Y=0: keep the whole sphere above it.
        candidate.y = clampf(candidate.y, MIN_TARGET_Y, MAX_TARGET_Y)
        var has_enough_space: bool = true
        for other in _targets:
            if other == target or not is_instance_valid(other):
                continue
            if other.global_position.distance_to(candidate) < 2.0:
                has_enough_space = false
                break
        chosen_position = candidate
        if has_enough_space:
            break
    target.global_position = chosen_position


func _ensure_targets_in_view() -> void:
    if not is_instance_valid(_camera):
        return
    var camera_inverse: Transform3D = _camera.global_transform.affine_inverse()
    for target in _targets:
        if not is_instance_valid(target):
            continue
        var camera_local_position: Vector3 = camera_inverse * target.global_position
        var depth: float = -camera_local_position.z
        var outside_view: bool = (
            depth < 5.0
            or absf(camera_local_position.x) > depth * 0.62
            or absf(camera_local_position.y) > depth * 0.38
        )
        if outside_view:
            _place_target(target)


func _create_hud() -> void:
    _hud_layer = CanvasLayer.new()
    _hud_layer.name = "HUDLayer"
    _hud_layer.layer = 10
    add_child(_hud_layer)
    _hud_root = Control.new()
    _hud_root.name = "HUDRoot"
    _hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _hud_root.mouse_filter = Control.MOUSE_FILTER_PASS
    _hud_layer.add_child(_hud_root)

    _hud_label = Label.new()
    _hud_label.name = "StatsLabel"
    _hud_label.anchor_left = 0.0
    _hud_label.anchor_top = 0.0
    _hud_label.anchor_right = 1.0
    _hud_label.anchor_bottom = 0.0
    _hud_label.offset_left = 20.0
    _hud_label.offset_top = 14.0
    _hud_label.offset_right = -20.0
    _hud_label.offset_bottom = 54.0
    _hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hud_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _hud_label.add_theme_font_size_override("font_size", 25)
    _hud_label.add_theme_color_override("font_color", Color(0.91, 0.97, 1.0, 1.0))
    _hud_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
    _hud_label.add_theme_constant_override("outline_size", 4)
    _hud_root.add_child(_hud_label)
    _add_crosshair()
    _add_fire_button()
    _add_instructions()
    _add_result_overlay()


func _add_crosshair() -> void:
    var horizontal := ColorRect.new()
    horizontal.name = "CrosshairHorizontal"
    horizontal.color = Color(0.95, 1.0, 1.0, 0.95)
    horizontal.mouse_filter = Control.MOUSE_FILTER_IGNORE
    horizontal.anchor_left = 0.5
    horizontal.anchor_top = 0.5
    horizontal.anchor_right = 0.5
    horizontal.anchor_bottom = 0.5
    horizontal.offset_left = -9.0
    horizontal.offset_top = -1.0
    horizontal.offset_right = 9.0
    horizontal.offset_bottom = 1.0
    _hud_root.add_child(horizontal)

    var vertical := ColorRect.new()
    vertical.name = "CrosshairVertical"
    vertical.color = Color(0.95, 1.0, 1.0, 0.95)
    vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
    vertical.anchor_left = 0.5
    vertical.anchor_top = 0.5
    vertical.anchor_right = 0.5
    vertical.anchor_bottom = 0.5
    vertical.offset_left = -1.0
    vertical.offset_top = -9.0
    vertical.offset_right = 1.0
    vertical.offset_bottom = 9.0
    _hud_root.add_child(vertical)

    var center_dot := ColorRect.new()
    center_dot.name = "CrosshairCenter"
    center_dot.color = Color(1.0, 0.70, 0.22, 1.0)
    center_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    center_dot.anchor_left = 0.5
    center_dot.anchor_top = 0.5
    center_dot.anchor_right = 0.5
    center_dot.anchor_bottom = 0.5
    center_dot.offset_left = -2.0
    center_dot.offset_top = -2.0
    center_dot.offset_right = 2.0
    center_dot.offset_bottom = 2.0
    _hud_root.add_child(center_dot)


func _add_fire_button() -> void:
    _fire_button = Button.new()
    _fire_button.name = "FireButton"
    _fire_button.text = "FIRE"
    _fire_button.focus_mode = Control.FOCUS_NONE
    _fire_button.anchor_left = 1.0
    _fire_button.anchor_top = 1.0
    _fire_button.anchor_right = 1.0
    _fire_button.anchor_bottom = 1.0
    _fire_button.offset_left = -150.0
    _fire_button.offset_top = -112.0
    _fire_button.offset_right = -24.0
    _fire_button.offset_bottom = -24.0
    _fire_button.add_theme_font_size_override("font_size", 22)
    _fire_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
    _fire_button.pressed.connect(_shoot)
    _hud_root.add_child(_fire_button)


func _add_instructions() -> void:
    _instructions_label = Label.new()
    _instructions_label.name = "ControlHint"
    _instructions_label.text = "DRAG ANYWHERE TO AIM  •  PRESS FIRE TO SHOOT"
    _instructions_label.anchor_left = 0.0
    _instructions_label.anchor_top = 1.0
    _instructions_label.anchor_right = 0.0
    _instructions_label.anchor_bottom = 1.0
    _instructions_label.offset_left = 22.0
    _instructions_label.offset_top = -48.0
    _instructions_label.offset_right = 500.0
    _instructions_label.offset_bottom = -18.0
    _instructions_label.add_theme_font_size_override("font_size", 15)
    _instructions_label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.91, 0.9))
    _instructions_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hud_root.add_child(_instructions_label)


func _add_result_overlay() -> void:
    _result_overlay = ColorRect.new()
    _result_overlay.name = "ResultOverlay"
    _result_overlay.color = Color(0.0, 0.0, 0.0, 0.78)
    _result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _result_overlay.visible = false
    _result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    _hud_root.add_child(_result_overlay)
    var center := CenterContainer.new()
    center.name = "ResultCenter"
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_STOP
    _result_overlay.add_child(center)
    var panel := PanelContainer.new()
    panel.name = "ResultPanel"
    panel.custom_minimum_size = Vector2(360.0, 230.0)
    center.add_child(panel)
    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 18)
    panel.add_child(content)
    _result_label = Label.new()
    _result_label.name = "ResultLabel"
    _result_label.text = "ROUND COMPLETE"
    _result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _result_label.add_theme_font_size_override("font_size", 25)
    _result_label.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0, 1.0))
    content.add_child(_result_label)
    _restart_button = Button.new()
    _restart_button.name = "RestartButton"
    _restart_button.text = "PLAY AGAIN"
    _restart_button.custom_minimum_size = Vector2(240.0, 58.0)
    _restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    _restart_button.add_theme_font_size_override("font_size", 20)
    _restart_button.pressed.connect(_start_round)
    content.add_child(_restart_button)


func _start_round() -> void:
    _score = 0
    _shots = 0
    _hits = 0
    _time_left = ROUND_DURATION
    _round_finished = false
    _last_displayed_second = -1
    _visibility_check_timer = 0.0
    _aim_touch_index = -1
    for target in _targets:
        if is_instance_valid(target):
            _place_target(target)
    if is_instance_valid(_result_overlay):
        _result_overlay.visible = false
    if is_instance_valid(_fire_button):
        _fire_button.visible = true
    _update_hud()


func _shoot() -> void:
    if _round_finished or not is_instance_valid(_camera):
        return
    _shots += 1
    var viewport_size: Vector2 = get_viewport().get_visible_rect().size
    var screen_center: Vector2 = viewport_size * 0.5
    var ray_origin: Vector3 = _camera.project_ray_origin(screen_center)
    var ray_direction: Vector3 = _camera.project_ray_normal(screen_center)
    var query := PhysicsRayQueryParameters3D.create(
        ray_origin,
        ray_origin + ray_direction * SHOT_DISTANCE
    )
    query.collision_mask = 1
    query.collide_with_areas = true
    query.collide_with_bodies = false
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    if not hit.is_empty():
        var collider: Variant = hit.get("collider")
        if collider is Area3D and (collider as Area3D).is_in_group(TARGET_GROUP):
            _hits += 1
            _score += 100
            _place_target(collider as Area3D)
    _update_hud()


func _finish_round() -> void:
    if _round_finished:
        return
    _round_finished = true
    _time_left = 0.0
    if is_instance_valid(_fire_button):
        _fire_button.visible = false
    var accuracy_text: String = "%.1f" % _get_accuracy()
    _result_label.text = (
        "ROUND COMPLETE\nPTS %d\nHITS %d / %d\nACCURACY %s%%"
        % [_score, _hits, _shots, accuracy_text]
    )
    _result_overlay.visible = true
    _update_hud()


func _get_accuracy() -> float:
    if _shots <= 0:
        return 0.0
    return 100.0 * float(_hits) / float(_shots)


func _update_hud() -> void:
    if not is_instance_valid(_hud_label):
        return
    var seconds_left: int = int(ceil(_time_left))
    var accuracy_text: String = "%.1f" % _get_accuracy()
    _hud_label.text = (
        "PTS " + str(_score)
        + "      TIME " + str(seconds_left)
        + "      ACC " + accuracy_text + "%"
    )


func _input(event: InputEvent) -> void:
    if _round_finished:
        return

    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            # A touch on HUD/FIRE is reserved for the corresponding Control.
            if _is_over_hud(touch.position):
                return
            # Capture only one aim finger. Other fingers remain free for FIRE.
            if _aim_touch_index == -1:
                _aim_touch_index = touch.index
        elif touch.index == _aim_touch_index:
            _aim_touch_index = -1

    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if drag.index == _aim_touch_index and not _is_over_hud(drag.position):
            if drag.screen_relative.length_squared() > 0.0:
                _apply_look(drag.screen_relative)

    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if not _is_over_hud(motion.position):
            _apply_look(motion.relative)

    elif event is InputEventMouseButton:
        var mouse_button := event as InputEventMouseButton
        if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT:
            if not _is_over_hud(mouse_button.position):
                _shoot()


func _is_over_hud(screen_position: Vector2) -> bool:
    if is_instance_valid(_result_overlay) and _result_overlay.visible:
        if _result_overlay.get_global_rect().has_point(screen_position):
            return true
    if is_instance_valid(_fire_button) and _fire_button.visible:
        if _fire_button.get_global_rect().has_point(screen_position):
            return true
    if is_instance_valid(_hud_label) and _hud_label.visible:
        if _hud_label.get_global_rect().has_point(screen_position):
            return true
    if is_instance_valid(_instructions_label) and _instructions_label.visible:
        if _instructions_label.get_global_rect().has_point(screen_position):
            return true
    return false


func _apply_look(delta_pixels: Vector2) -> void:
    if not is_instance_valid(_yaw_pivot) or not is_instance_valid(_pitch_pivot):
        return
    _yaw_pivot.rotate_y(-delta_pixels.x * LOOK_SENSITIVITY)
    _pitch = clampf(
        _pitch - delta_pixels.y * LOOK_SENSITIVITY,
        -MAX_PITCH,
        MAX_PITCH
    )
    _pitch_pivot.rotation.x = _pitch
