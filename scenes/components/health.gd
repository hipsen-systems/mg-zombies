class_name Health
extends Node
## Hit points for anything that can be hurt (issue #7).
##
## Added as a child node so hero and zombies share one implementation instead
## of each growing their own copy, and so the skill tree (issue #9) has a single
## place to raise [member max_health] or apply damage modifiers later.
##
## Owners are expected to expose a `take_damage()` of their own that forwards
## here, so an attacker never has to reach through to a child node.

## Emitted on every change, including healing. Carries both numbers so a HUD can
## draw a bar without reaching back into this node.
signal health_changed(current: float, maximum: float)

## Emitted once, when health first reaches zero. Never re-emitted: further
## damage on a corpse is ignored.
signal died

@export var max_health := 100.0

var current: float = 0.0


func _ready() -> void:
	current = max_health


func is_dead() -> bool:
	return current <= 0.0


func take_damage(amount: float) -> void:
	if is_dead() or amount <= 0.0:
		return
	current = maxf(current - amount, 0.0)
	health_changed.emit(current, max_health)
	if is_dead():
		died.emit()


func heal(amount: float) -> void:
	# Healing a corpse would silently revive it; resurrection, if it ever
	# exists, should be an explicit decision and not a side effect of a heal.
	if is_dead() or amount <= 0.0:
		return
	current = minf(current + amount, max_health)
	health_changed.emit(current, max_health)
