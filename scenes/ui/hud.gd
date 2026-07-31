class_name HUD
extends CanvasLayer
## Everything drawn over the game (issue #36 moved it out of scenes/main.gd).
##
## The whole HUD is one scene with one script, and every element is fed by a
## method call rather than by reaching in from outside. scenes/main.gd wires the
## hero's signals to these methods and never touches a Label — that is the point
## of the split: the layout can change without a gameplay script changing with
## it.
##
## [b]The hero's own health bar stays, even though the info bar shows his hit
## points whenever he is selected.[/b] It is not a duplicate but the case the
## info bar cannot cover: while an enemy is selected the panel is showing the
## enemy's health, and a player who cannot see their own during a fight is worse
## off than one looking at a redundant bar.

@onready var _hero_health_bar: ProgressBar = $HeroHealthBar
@onready var _hero_health_value: Label = $HeroHealthBar/Value
@onready var _attack_move_label: Label = $AttackMoveLabel
@onready var _death_label: Label = $DeathLabel
@onready var _unit_info_bar: UnitInfoBar = $UnitInfoBar


## Always-visible player health, whatever is selected.
func set_hero_health(current: float, maximum: float) -> void:
	_hero_health_bar.max_value = maximum
	_hero_health_bar.value = current
	_hero_health_value.text = "%d / %d" % [roundi(current), roundi(maximum)]


## Point the info bar at the selected unit. Connected to
## [signal UnitSelection.selection_changed].
func show_unit(unit: Node3D) -> void:
	_unit_info_bar.show_unit(unit)


## Arming the attack command changes what the *next* left-click means, and a
## mode the player cannot see is a mode they will forget they are in.
func set_attack_move_armed(armed: bool) -> void:
	_attack_move_label.visible = armed


func show_death() -> void:
	_death_label.show()
