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

## Emitted when the player asks for a fresh run from the victory screen (issue
## #39). Nothing here acts on it: scenes/main.gd owns what a run is, so what
## "start another one" does is that script's decision and not a widget's.
signal restart_requested

## How long the checkpoint confirmation holds before it starts fading, and how
## long the fade takes. Long enough to read mid-fight, short enough that it is
## gone before the fight the checkpoint was banked for.
const CHECKPOINT_HOLD := 1.1
const CHECKPOINT_FADE := 0.7

@onready var _hero_health_bar: ProgressBar = $HeroHealthBar
@onready var _hero_health_value: Label = $HeroHealthBar/Value
@onready var _attack_move_label: Label = $AttackMoveLabel
@onready var _death_label: Label = $DeathLabel
@onready var _death_sub_label: Label = $DeathSubLabel
@onready var _checkpoint_label: Label = $CheckpointLabel
@onready var _unit_info_bar: UnitInfoBar = $UnitInfoBar
@onready var _victory_panel: Control = $VictoryPanel
@onready var _restart_button: Button = $VictoryPanel/RestartButton

var _checkpoint_tween: Tween = null


func _ready() -> void:
	_restart_button.pressed.connect(restart_requested.emit)
	# The whole tree is paused while the victory panel is up — that is what makes
	# the run over rather than merely won — and a paused Control is skipped by GUI
	# input dispatch, which would leave the button dead under the cursor. This is
	# the one node in the HUD that has to keep running when nothing else does; its
	# children inherit the mode from it.
	_victory_panel.process_mode = Node.PROCESS_MODE_ALWAYS


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
	# Cancel any checkpoint flash still fading. Arming a checkpoint and dying
	# seconds later is not a corner case — a zombie chasing the hero across a
	# threshold produces exactly that — and "CHECKPOINT" fading out behind "YOU
	# DIED" reads as congratulating the player on the death.
	_clear_checkpoint_flash()
	_death_label.show()
	_death_sub_label.show()


## Death is no longer the end of the run (issue #38), so the screen has to come
## back off again.
func hide_death() -> void:
	_death_label.hide()
	_death_sub_label.hide()


## The boss is dead and the run is won (issue #39).
##
## [b]There is deliberately no hide_victory().[/b] The only way off this screen is
## a fresh scene, so a path that took it back down would be one no caller could
## reach — and the death screen's [method hide_death] is the counter-example that
## makes the distinction worth stating rather than assuming.
func show_victory() -> void:
	# Same reason show_death() does it: a "CHECKPOINT" still fading out under the
	# end of the run is reading out the wrong moment.
	_clear_checkpoint_flash()
	_victory_panel.show()
	# After show(), which is what makes the button focusable. Enter then works as
	# well as a click, and by this point nothing else on screen takes input at all.
	_restart_button.grab_focus()


## Confirm that a checkpoint is now armed.
##
## The lit pad in the world is the lasting signal; this is the one that reaches a
## player who is watching the fight rather than the floor they just crossed.
func flash_checkpoint() -> void:
	_clear_checkpoint_flash()
	_checkpoint_label.modulate.a = 1.0
	_checkpoint_label.show()
	_checkpoint_tween = create_tween()
	_checkpoint_tween.tween_interval(CHECKPOINT_HOLD)
	_checkpoint_tween.tween_property(_checkpoint_label, "modulate:a", 0.0, CHECKPOINT_FADE)
	_checkpoint_tween.tween_callback(_checkpoint_label.hide)


## Kill a running fade and take the label down. Both callers need the tween
## stopped first: it drives `modulate:a`, so it would keep animating a hidden
## label and then re-hide it a second later, over whatever came next.
func _clear_checkpoint_flash() -> void:
	if _checkpoint_tween != null and _checkpoint_tween.is_valid():
		_checkpoint_tween.kill()
	_checkpoint_label.hide()
