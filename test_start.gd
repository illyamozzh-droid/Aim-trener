extends Control

const ROUND_DURATION: float = 30.0
const TARGET_SIZE: Vector2 = Vector2(82.0, 82.0)
const TARGET_MARGIN: float = 10.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _menu: CenterContainer
var _training: Control
var _arena: ColorRect
var _target: Button
var _score_label: Label
var _time_label: Label
var _result_overlay: CenterContainer
var _result_label: Label

var _score: int = 0
var _round_time_left: float = ROUND_DURATION
var _shown_seconds: int = -1
var _round_active: bool = false


func _ready() -> void:
	_rng.randomize()
	_build_background()
	_build_menu()
	_build_training()
	_show_menu()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _process(delta: float) -> void:
	if not _round_active:
		return

	_round_time_left = maxf(0.0, _round_time_left - delta)
	var seconds_left: int = ceili(_round_time_left)
	if seconds_left != _shown_seconds:
		_shown_seconds = seconds_left
		_time_label.text = "Время: %d" % _shown_seconds

	if _round_time_left <= 0.0:
		_finish_round()


func _build_background() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color(0.035, 0.047, 0.065, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)


func _build_menu() -> void:
	_menu = CenterContainer.new()
	_menu.name = "MenuScreen"
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)

	var panel := PanelContainer.new()
	panel.name = "MenuPanel"
	panel.custom_minimum_size = Vector2(380.0, 300.0)
	panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(
			Color(0.075, 0.095, 0.125, 1.0),
			Color(0.20, 0.28, 0.36, 1.0)
		)
	)
	_menu.add_child(panel)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)

	var title := _make_label(
		"SPATIAL ACCURACY\nSIMULATOR",
		28,
		Color(0.92, 0.96, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	title.custom_minimum_size = Vector2(0.0, 88.0)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(title)

	var subtitle := _make_label(
		"Офлайн-тренировка точности",
		16,
		Color(0.66, 0.73, 0.82),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	content.add_child(subtitle)

	var start_button := _make_button(
		"СТАРТ",
		Vector2(230.0, 58.0),
		22
	)
	start_button.name = "StartButton"
	start_button.pressed.connect(_start_training)
	content.add_child(start_button)

	var hint := _make_label(
		"30 секунд · нажимай по мишени",
		14,
		Color(0.55, 0.63, 0.73),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	content.add_child(hint)


func _build_training() -> void:
	_training = Control.new()
	_training.name = "TrainingScreen"
	_training.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_training.visible = false
	add_child(_training)

	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.anchor_left = 0.0
	top_bar.anchor_top = 0.0
	top_bar.anchor_right = 1.0
	top_bar.anchor_bottom = 0.0
	top_bar.offset_left = 18.0
	top_bar.offset_top = 14.0
	top_bar.offset_right = -18.0
	top_bar.offset_bottom = 58.0
	top_bar.add_theme_constant_override("separation", 12)
	_training.add_child(top_bar)

	_score_label = _make_label(
		"Попадания: 0",
		20,
		Color(0.92, 0.96, 1.0),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_score_label)

	_time_label = _make_label(
		"Время: 30",
		20,
		Color(0.45, 0.90, 0.78),
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	top_bar.add_child(_time_label)

	_arena = ColorRect.new()
	_arena.name = "TrainingArea"
	_arena.color = Color(0.055, 0.073, 0.095, 1.0)
	_arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arena.offset_left = 14.0
	_arena.offset_top = 78.0
	_arena.offset_right = -14.0
	_arena.offset_bottom = -82.0
	_training.add_child(_arena)

	_target = _make_button("+", TARGET_SIZE, 42)
	_target.name = "AimTarget"
	_target.custom_minimum_size = TARGET_SIZE
	_target.size = TARGET_SIZE
	_target.focus_mode = Control.FOCUS_NONE
	_target.add_theme_stylebox_override(
		"normal",
		_make_round_target_style(Color(0.92, 0.24, 0.31, 1.0))
	)
	_target.add_theme_stylebox_override(
		"hover",
		_make_round_target_style(Color(1.0, 0.34, 0.40, 1.0))
	)
	_target.add_theme_stylebox_override(
		"pressed",
		_make_round_target_style(Color(0.72, 0.15, 0.22, 1.0))
	)
	_target.add_theme_stylebox_override(
		"disabled",
		_make_round_target_style(Color(0.34, 0.37, 0.42, 1.0))
	)
	_target.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_target.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	_target.pressed.connect(_on_target_pressed)
	_arena.add_child(_target)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.anchor_left = 0.0
	footer.anchor_top = 1.0
	footer.anchor_right = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = 18.0
	footer.offset_top = -64.0
	footer.offset_right = -18.0
	footer.offset_bottom = -12.0
	footer.add_theme_constant_override("separation", 12)
	_training.add_child(footer)

	var instructions := _make_label(
		"Нажимай на мишень, чтобы набрать очки",
		15,
		Color(0.66, 0.73, 0.82),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	instructions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(instructions)

	var back_button := _make_button("В МЕНЮ", Vector2(150.0, 48.0), 16)
	back_button.name = "BackButton"
	back_button.pressed.connect(_show_menu)
	footer.add_child(back_button)

	_result_overlay = CenterContainer.new()
	_result_overlay.name = "ResultOverlay"
	_result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_overlay.visible = false
	_training.add_child(_result_overlay)

	_result_label = _make_label(
		"",
		28,
		Color(1.0, 1.0, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_result_label.custom_minimum_size = Vector2(300.0, 110.0)
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_overlay.add_child(_result_label)


func _make_label(
	caption: String,
	font_size: int,
	font_color: Color,
	alignment: int
) -> Label:
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	return label


func _make_button(caption: String, minimum_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = minimum_size
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_stylebox_override(
		"normal",
		_make_button_style(Color(0.10, 0.48, 0.43, 1.0), Color(0.20, 0.78, 0.66, 1.0))
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_button_style(Color(0.13, 0.58, 0.51, 1.0), Color(0.35, 0.90, 0.76, 1.0))
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_button_style(Color(0.07, 0.36, 0.33, 1.0), Color(0.18, 0.68, 0.58, 1.0))
	)
	button.add_theme_stylebox_override(
		"disabled",
		_make_button_style(Color(0.18, 0.22, 0.27, 1.0), Color(0.30, 0.35, 0.42, 1.0))
	)
	return button


func _make_button_style(background_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 14.0
	style.content_margin_top = 8.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 8.0
	return style


func _make_panel_style(background_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.content_margin_left = 24.0
	style.content_margin_top = 20.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 20.0
	return style


func _make_round_target_style(background_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = Color(1.0, 0.88, 0.90, 1.0)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 41
	style.corner_radius_top_right = 41
	style.corner_radius_bottom_left = 41
	style.corner_radius_bottom_right = 41
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _start_training() -> void:
	_score = 0
	_round_time_left = ROUND_DURATION
	_shown_seconds = -1
	_round_active = true

	_score_label.text = "Попадания: 0"
	_time_label.text = "Время: %d" % int(ROUND_DURATION)
	_result_overlay.visible = false
	_target.disabled = false

	_menu.visible = false
	_training.visible = true
	call_deferred("_move_target")


func _on_target_pressed() -> void:
	if not _round_active:
		return

	_score += 1
	_score_label.text = "Попадания: %d" % _score
	_move_target()


func _move_target() -> void:
	if not is_instance_valid(_arena) or not is_instance_valid(_target):
		return

	var area_size: Vector2 = _arena.size
	if area_size.x <= 0.0 or area_size.y <= 0.0:
		return

	var maximum_x: float = maxf(TARGET_MARGIN, area_size.x - _target.size.x - TARGET_MARGIN)
	var maximum_y: float = maxf(TARGET_MARGIN, area_size.y - _target.size.y - TARGET_MARGIN)
	_target.position = Vector2(
		_rng.randf_range(TARGET_MARGIN, maximum_x),
		_rng.randf_range(TARGET_MARGIN, maximum_y)
	)


func _finish_round() -> void:
	_round_active = false
	_target.disabled = true
	_result_label.text = "Время вышло!\nПопаданий: %d" % _score
	_result_overlay.visible = true


func _show_menu() -> void:
	_round_active = false
	if is_instance_valid(_menu):
		_menu.visible = true
	if is_instance_valid(_training):
		_training.visible = false


func _on_viewport_size_changed() -> void:
	if _round_active:
		call_deferred("_move_target")
