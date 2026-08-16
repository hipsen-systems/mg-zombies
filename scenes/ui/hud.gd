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

## The player clicked a node in the skill panel (issue #62). Passed straight
## through from [signal SkillPanel.rank_up_requested] for the same reason
## [signal restart_requested] exists: this folder draws the tree and does not own
## the points, so what buying means is scenes/main.gd's decision.
signal skill_rank_up_requested(skill: StringName)

## The skill panel opened or closed, and the game is meant to freeze while it is
## up. Reported rather than acted on: `get_tree().paused` lives on the SceneTree
## rather than the scene, so the script that sets it has to be the one that clears
## it — see the note on the victory panel in this folder's doc.
signal skill_panel_toggled(open: bool)

## How long a transient banner holds before it starts fading, and how long the
## fade takes. Long enough to read mid-fight, short enough that it is gone
## before the fight the checkpoint was banked for.
const FLASH_HOLD := 1.1
const FLASH_FADE := 0.7

@onready var _hero_health_bar: ProgressBar = $HeroHealthBar
@onready var _hero_health_value: Label = $HeroHealthBar/Value
@onready var _xp_bar: ProgressBar = $XPBar
@onready var _xp_value: Label = $XPBar/Value
@onready var _skills_label: Label = $SkillsLabel
@onready var _attack_move_label: Label = $AttackMoveLabel
@onready var _death_label: Label = $DeathLabel
@onready var _death_sub_label: Label = $DeathSubLabel
@onready var _checkpoint_label: Label = $CheckpointLabel
@onready var _level_up_label: Label = $LevelUpLabel
@onready var _unit_info_bar: UnitInfoBar = $UnitInfoBar
@onready var _skill_panel: SkillPanel = $SkillPanel
@onready var _victory_panel: Control = $VictoryPanel
@onready var _restart_button: Button = $VictoryPanel/RestartButton

## The running fade for each flashing label, so two banners up at once do not
## share one tween — arming a checkpoint and levelling on the same kill is an
## ordinary thing to do, not a corner case.
var _flash_tweens := {}


func _ready() -> void:
	_restart_button.pressed.connect(restart_requested.emit)
	_skill_panel.rank_up_requested.connect(skill_rank_up_requested.emit)
	_skill_panel.toggled.connect(skill_panel_toggled.emit)
	_skill_panel.toggled.connect(_on_skill_panel_toggled)
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


## The XP bar and the level beside it (issue #8). Both numbers are measured
## toward the *next* level rather than cumulatively, which is what the bar draws.
func set_experience(current: float, needed: float, level: int) -> void:
	_xp_bar.max_value = maxf(needed, 1.0)
	_xp_bar.value = current
	_xp_value.text = "Lv %d     %d / %d XP" % [level, floori(current), roundi(needed)]


## The unspent points and what they can be spent on.
##
## [param skills] is what the unit reports about itself — see
## [method Hero.skill_summary]. This method formats and never interprets: the
## effect strings are the hero's words, because what a rank buys is a fact about
## him and a panel that knew it would have to be updated with every new skill.
func set_skills(points: int, skills: Array) -> void:
	var parts: PackedStringArray = ["%d point%s" % [points, "" if points == 1 else "s"]]
	for skill in skills:
		parts.append("[%s] %s %d/%d  %s" % [
			skill.get("hotkey", "?"),
			skill.get("name", "?"),
			int(skill.get("rank", 0)),
			int(skill.get("max_rank", 0)),
			skill.get("effect", ""),
		])
	_skills_label.text = "    ".join(parts)
	# The points total is the only part that ever needs chasing: it is what turns
	# a keypress from a no-op into a purchase.
	_skills_label.modulate = Color(1, 0.85, 0.4) if points > 0 else Color(0.72, 0.76, 0.84)


## The whole tree, for the panel (issue #62).
##
## Separate from [method set_skills] because they draw different things from
## different reports — that one is the crib sheet for the two keys, this is every
## node including the locked ones. They are refreshed together because both move
## on the same two events, which is scenes/main.gd's business and not this
## folder's.
func set_skill_catalogue(points: int, catalogue: Array) -> void:
	_skill_panel.set_catalogue(points, catalogue)


## Banners come down when the skill panel goes up, the same rule the death and
## victory screens keep — and this is the likeliest collision of the three rather
## than a corner case. "LEVEL 7 — 1 skill point" is the banner that *tells* the
## player to open this panel, so a player who does what it says immediately reads
## it across the panel's own title. Measured on the first screenshot of the panel,
## not reasoned about.
func _on_skill_panel_toggled(open: bool) -> void:
	if open:
		_clear_flashes()


## Point the info bar at the selected unit. Connected to
## [signal UnitSelection.selection_changed].
func show_unit(unit: Node3D) -> void:
	_unit_info_bar.show_unit(unit)


## Arming the attack command changes what the *next* left-click means, and a
## mode the player cannot see is a mode they will forget they are in.
func set_attack_move_armed(armed: bool) -> void:
	_attack_move_label.visible = armed


func show_death() -> void:
	# Cancel any banner still fading. Arming a checkpoint and dying seconds later
	# is not a corner case — a zombie chasing the hero across a threshold produces
	# exactly that — and "CHECKPOINT" fading out behind "YOU DIED" reads as
	# congratulating the player on the death. "LEVEL 3" does it twice over: the
	# kill that levels the hero is very often the one that leaves him low enough
	# for the next zombie to finish.
	_clear_flashes()
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
	# Same reason show_death() does it: a "CHECKPOINT" or a "LEVEL 4" still fading
	# out under the end of the run is reading out the wrong moment — and the boss
	# is worth enough XP that the winning blow very often levels the hero.
	_clear_flashes()
	# The death screen is a different case and worth being honest about: it
	# cannot be up, because scenes/main.gd stops answering a death once the run
	# is won. Taking it down anyway makes this panel's claim on the screen a rule
	# of this folder, rather than something true only while a guard in another
	# folder keeps it true.
	hide_death()
	# The skill panel goes down and stays down for the same reason, and one
	# stronger: it freezes and unfreezes the tree, so closing it behind a victory
	# screen would hand the player a won run they can still walk around in.
	_skill_panel.set_unavailable()
	_victory_panel.show()
	# After show(), which is what makes the button focusable. Enter then works as
	# well as a click, and by this point nothing else on screen takes input at all.
	_restart_button.grab_focus()


## Confirm that a checkpoint is now armed.
##
## The lit pad in the world is the lasting signal; this is the one that reaches a
## player who is watching the fight rather than the floor they just crossed.
func flash_checkpoint() -> void:
	_flash(_checkpoint_label)


## Announce a level and what it paid (issue #8).
##
## The bar below already shows both, and this exists because it does not *reach*
## a player mid-fight — which is exactly when the kill that levelled them
## happened. Same argument as the checkpoint flash, and it sits on its own line
## above it so a kill that does both is legible rather than one banner over the
## other.
func flash_level_up(level: int, points_awarded: int) -> void:
	_level_up_label.text = "LEVEL %d — %d skill point%s" % [
		level, points_awarded, "" if points_awarded == 1 else "s",
	]
	_flash(_level_up_label)


## Bring a transient banner up and fade it out again.
func _flash(label: Label) -> void:
	_clear_flash(label)
	label.modulate.a = 1.0
	label.show()
	var tween := create_tween()
	_flash_tweens[label] = tween
	tween.tween_interval(FLASH_HOLD)
	tween.tween_property(label, "modulate:a", 0.0, FLASH_FADE)
	tween.tween_callback(label.hide)


## Kill a running fade and take the label down. Every caller needs the tween
## stopped first: it drives `modulate:a`, so it would keep animating a hidden
## label and then re-hide it a second later, over whatever came next.
func _clear_flash(label: Label) -> void:
	var tween: Tween = _flash_tweens.get(label)
	if tween != null and tween.is_valid():
		tween.kill()
	_flash_tweens.erase(label)
	label.hide()


## Take every banner down at once, for the two screens that own the whole view.
func _clear_flashes() -> void:
	_clear_flash(_checkpoint_label)
	_clear_flash(_level_up_label)
