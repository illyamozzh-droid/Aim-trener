extends CanvasLayer
class_name MobileControls

signal move_changed(value: Vector2)
signal look_changed(value: Vector2)
signal jump_pressed
signal slide_pressed
signal focus_pressed

const CONFIG_PATH := "user://hud_layout.json"

var edit_mode: bool = false

var _root: Control
var _joystick: Control
var _look_zone: Control
var _buttons: Dictionary = {}

var _dragged: Control
var _drag_offset: Vector2
var _touch_origin: Vector2
var _active_look_touch: int = -1

func _ready() -> void:
	_build_hud()
	_load_layout()
	get_viewport().size_changed.connect(_layout_if_needed)

func _build_hud() -> void:
	_root = Control.new()
	_root.name = "HUD"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	_joystick = _make_panel(
		"Joystick",
		Vector2(150, 150),
		Vector2(30, -180),
		Color(0.15, 0.18, 0.22, 0.45)
	)

	_look_zone = Control.new()
	_look_zone.name = "LookZone"
	_look_zone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_look_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_look_zone)

	_add_button("Focus", "FOCUS", Vector2(-190, -170), Callable(self, "_on_focus"))
	_add_button("Jump", "JUMP", Vector2(-110, -280), Callable(self, "_on_jump"))
	_add_button("Slide", "SLIDE", Vector2(-110, -170), Callable(self, "_on_slide"))

	var edit_button := Button.new()
	edit_button.text = "EDIT HUD"
	edit_button.position = Vector2(12, 12)
	edit_button.size = Vector2(110, 42)
	edit_button.pressed.connect(toggle_edit_mode)
	_root.add_child(edit_button)

func _make_panel(
	node_name: String,
	size: Vector2,
	offset: Vector2,
	color: Color
) -> Control:
	var panel := Panel.new()
	panel.name = node_name
	panel.size = size

	var viewport_size := get_viewport().get_visible_rect().size

	# Position is calculated relative to the bottom-left screen edge.
	panel.position = Vector2(
		offset.x,
		viewport_size.y + offset.y
	)

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 75
	style.corner_radius_top_right = 75
	style.corner_radius_bottom_left = 75
	style.corner_radius_bottom_right = 75

	panel.add_theme_stylebox_override("panel", style)
	panel.gui_input.connect(_on_joystick_input)

	_root.add_child(panel)

	return panel

func _add_button(
	key: String,
	caption: String,
	offset: Vector2,
	callback: Callable
) -> void:
	var button := Button.new()
	button.name = key
	button.text = caption
	button.size = Vector2(92, 76)

	var viewport_size := get_viewport().get_visible_rect().size

	button.position = Vector2(
		viewport_size.x + offset.x,
		viewport_size.y + offset.y
	)

	button.modulate = Color(1.0, 1.0, 1.0, 0.82)
	button.pressed.connect(callback)
	button.gui_input.connect(_on_draggable_input.bind(button))

	_root.add_child(button)
	_buttons[key] = button

func _on_joystick_input(event: InputEvent) -> void:
	if edit_mode:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_origin = event.position
		else:
			move_changed.emit(Vector2.ZERO)

	elif event is InputEventScreenDrag:
		var delta := (event.position - _touch_origin) / 55.0

		move_changed.emit(
			Vector2(
				clampf(delta.x, -1.0, 1.0),
				clampf(delta.y, -1.0, 1.0)
			)
		)

func _on_draggable_input(event: InputEvent, control: Control) -> void:
	if not edit_mode:
		return

	if event is InputEventScreenTouch and event.pressed:
		_dragged = control
		_drag_offset = control.position - event.position

	elif event is InputEventScreenDrag and _dragged == control:
		control.position = event.position + _drag_offset

	elif event is InputEventScreenTouch and not event.pressed and _dragged == control:
		_dragged = null
		_save_layout()

func _on_focus() -> void:
	if not edit_mode:
		focus_pressed.emit()

func _on_jump() -> void:
	if not edit_mode:
		jump_pressed.emit()

func _on_slide() -> void:
	if not edit_mode:
		slide_pressed.emit()

func toggle_edit_mode() -> void:
	edit_mode = not edit_mode

	if _joystick != null:
		_joystick.modulate.a = 0.8 if edit_mode else 1.0

func _save_layout() -> void:
	var data: Dictionary = {}

	for key in _buttons:
		var control: Control = _buttons[key]

		data[key] = {
			"x": control.position.x,
			"y": control.position.y
		}

	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)

	if file != null:
		file.store_string(JSON.stringify(data))

func _load_layout() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return

	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)

	if file == null:
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return

	for key in parsed:
		if not _buttons.has(key):
			continue
		var entry: Variant = parsed[key]
		if not (entry is Dictionary):
			continue
		var control: Control = _buttons[key] as Control
		if not is_instance_valid(control):
			continue
		var x_value: Variant = entry.get("x", control.position.x)
		var y_value: Variant = entry.get("y", control.position.y)
		if (x_value is int or x_value is float) and (y_value is int or y_value is float):
			control.position = Vector2(float(x_value), float(y_value))

func _layout_if_needed() -> void:
	if not is_instance_valid(_root):
		return

	var viewport_size := get_viewport().get_visible_rect().size

	for key in _buttons:
		var control: Control = _buttons[key] as Control
		if not is_instance_valid(control):
			continue

		control.position.x = clampf(
			control.position.x,
			0.0,
			maxf(0.0, viewport_size.x - control.size.x)
		)

		control.position.y = clampf(
			control.position.y,
			0.0,
			maxf(0.0, viewport_size.y - control.size.y)
		)

	if is_instance_valid(_joystick):
		_joystick.position.x = clampf(
			_joystick.position.x,
			0.0,
			maxf(0.0, viewport_size.x - _joystick.size.x)
		)
		_joystick.position.y = clampf(
			_joystick.position.y,
			0.0,
			maxf(0.0, viewport_size.y - _joystick.size.y)
		)

func _input(event: InputEvent) -> void:
	if edit_mode:
		return

	var viewport_width := get_viewport().get_visible_rect().size.x

	if event is InputEventScreenTouch:
		if event.position.x > viewport_width * 0.38:
			if event.pressed and _active_look_touch == -1:
				_active_look_touch = event.index

			elif not event.pressed and event.index == _active_look_touch:
				_active_look_touch = -1

	elif event is InputEventScreenDrag:
		if event.index == _active_look_touch:
			look_changed.emit(event.relative)
