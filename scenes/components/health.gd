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

## Emitted when health reaches zero. Once per life: further damage on a corpse is
## ignored, so it cannot fire twice — but a component put back on its feet by
## [method revive] can emit it again the next time it is killed.
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


## Put a dead owner back on its feet at full health (issue #38's checkpoint
## respawn). The explicit decision [method heal] refuses to make for you.
##
## Deliberately does not emit anything of its own. Whoever revives an owner is
## the one moving it, healing it and clearing its death state, so a signal here
## would announce a half-finished resurrection.
func revive() -> void:
	current = max_health
	health_changed.emit(current, max_health)
