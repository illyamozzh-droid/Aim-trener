extends RefCounted
class_name AIMemory

var samples: int = 0
var jump_rate: float = 0.0
var slide_rate: float = 0.0
var strafe_bias: float = 0.0
var focus_accuracy: float = 0.0
var recent_direction: Vector3 = Vector3.ZERO
var behavior_weights: Dictionary = {
	"approach": 0.45,
	"circle": 0.35,
	"evade": 0.20
}

func record_player_action(direction: Vector3, jumped: bool, slid: bool, focus_hit: bool) -> void:
	samples += 1
	var alpha: float = 1.0 / min(samples, 20)
	jump_rate = lerpf(jump_rate, 1.0 if jumped else 0.0, alpha)
	slide_rate = lerpf(slide_rate, 1.0 if slid else 0.0, alpha)
	focus_accuracy = lerpf(focus_accuracy, 1.0 if focus_hit else 0.0, alpha)
	if direction.length_squared() > 0.01:
		var lateral: float = signf(direction.x)
		strafe_bias = lerpf(strafe_bias, lateral, alpha)
		recent_direction = direction.normalized()
	_update_weights()

func _update_weights() -> void:
	var evade: float = clampf(0.20 + jump_rate * 0.20 + slide_rate * 0.25 + focus_accuracy * 0.25, 0.10, 0.75)
	var circle: float = clampf(0.35 + absf(strafe_bias) * 0.20, 0.15, 0.65)
	var approach: float = maxf(0.10, 1.0 - evade - circle)
	var total: float = approach + circle + evade
	behavior_weights = {
		"approach": approach / total,
		"circle": circle / total,
		"evade": evade / total
	}

func choose_behavior(rng: RandomNumberGenerator) -> String:
	var roll: float = rng.randf()
	var threshold: float = float(behavior_weights["approach"])
	if roll < threshold:
		return "approach"
	threshold += float(behavior_weights["circle"])
	if roll < threshold:
		return "circle"
	return "evade"

func get_summary() -> Dictionary:
	return {
		"samples": samples,
		"jump_rate": jump_rate,
		"slide_rate": slide_rate,
		"strafe_bias": strafe_bias,
		"focus_accuracy": focus_accuracy,
		"behavior_weights": behavior_weights.duplicate(true)
	}
