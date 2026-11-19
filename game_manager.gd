extends Node3D
class_name SimGameManager

@export var bot_count: int = 5
@export var target_scene: PackedScene
@export var player_scene: PackedScene

var player: SimPlayer
var arena: ProceduralArena
var controls: MobileControls
var memory: AIMemory

var score: int = 0
var focused_targets: int = 0

var _status_label: Label

func _ready() -> void:
	bot_count = maxi(bot_count, 0)
	memory = AIMemory.new()

	_create_arena()
	_create_player()
	_create_controls()
	_create_status()

	_spawn_targets()

func _create_arena() -> void:
	arena = ProceduralArena.new()
	arena.name = "Arena"
	# Connect before entering the tree so even a very fast bake completion
	# cannot be missed.
	arena.navigation_baked.connect(_on_navigation_ready)
	add_child(arena)

func _create_player() -> void:
	if is_instance_valid(player_scene):
		var instance: Node = player_scene.instantiate()
		if instance is SimPlayer:
			player = instance as SimPlayer
		else:
			push_error("Invalid player_scene: root node must inherit SimPlayer; using built-in player")
			if is_instance_valid(instance):
				instance.free()
			player = SimPlayer.new()
	else:
		player = SimPlayer.new()

	player.name = "Player"
	player.position = Vector3(0.0, 0.2, 10.0)

	add_child(player)
	player.action_recorded.connect(_on_player_action)

func _create_controls() -> void:
	if player == null:
		push_error("Cannot create controls: player is missing")
		return

	controls = MobileControls.new()
	controls.name = "MobileControls"
	add_child(controls)

	controls.move_changed.connect(player.set_move_input)
	controls.look_changed.connect(player.add_look_input)
	controls.jump_pressed.connect(player.jump)
	controls.slide_pressed.connect(player.start_slide)
	controls.focus_pressed.connect(player.focus_target)

func _create_status() -> void:
	var layer := CanvasLayer.new()
	layer.name = "StatusLayer"
	add_child(layer)

	_status_label = Label.new()
	_status_label.position = Vector2(16, 64)
	_status_label.add_theme_font_size_override("font_size", 22)

	layer.add_child(_status_label)
	_update_status()

func _spawn_targets() -> void:
	for i in range(bot_count):
		var target: SimTarget

		if is_instance_valid(target_scene):
			var instance: Node = target_scene.instantiate()
			if instance is SimTarget:
				target = instance as SimTarget
			else:
				push_error("Invalid target_scene: root node must inherit SimTarget; using built-in bot")
				if is_instance_valid(instance):
					instance.free()
				target = SimTarget.new()
		else:
			target = SimTarget.new()

		target.name = "Target_%02d" % i

		var angle := TAU * float(i) / float(maxi(bot_count, 1))

		target.position = Vector3(
			cos(angle) * 10.0,
			0.2,
			sin(angle) * 10.0
		)

		target.set_memory(memory)

		add_child(target)
		target.focused.connect(_on_target_focused)

func _on_player_action(
	direction: Vector3,
	jumped: bool,
	slid: bool,
	focused: bool
) -> void:
	memory.record_player_action(direction, jumped, slid, focused)
	_update_status()

func _on_target_focused(_target: SimTarget) -> void:
	focused_targets += 1
	score += 10
	_update_status()

func _on_navigation_ready() -> void:
	for child in get_children():
		if child is SimTarget and is_instance_valid(child):
			var target: SimTarget = child as SimTarget
			if is_instance_valid(target):
				target.activate_navigation()

func _update_status() -> void:
	if not is_instance_valid(_status_label):
		return

	_status_label.text = "Очки: %d   Зафиксировано целей: %d" % [
		score,
		focused_targets
	]
