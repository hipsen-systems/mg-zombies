class_name Experience
extends Node
## Levels earned by killing things, and the skill points they pay out (issue #8).
##
## Added as a child node for the same reason [Health] is: it is per-actor state
## with no opinion about which actor, so a levelling ally or a rival that grows
## over a run needs no second copy of the arithmetic.
##
## [b]A level awards points and nothing else.[/b] Levelling up does not raise a
## single stat by itself — every stat gain in the game is bought by spending a
## point, which is what keeps two heroes of the same level genuinely different
## builds rather than the same hero twice. That rule is the game's, not this
## node's, which is why it is written in the root CLAUDE.md; what this node
## enforces is only its half: it hands out points and never touches a stat.
## Deciding what a point buys belongs to whoever owns the stats — today
## scenes/hero/, and issue #9's data model after that.
##
## Owners are expected to expose the granting, the same way they forward
## [method Health.take_damage] rather than letting an attacker reach through to
## the component.

## Emitted whenever XP or the level moves. Carries everything a bar needs, so a
## HUD never reaches back into this node — [param current] and [param needed] are
## both measured toward the *next* level, not cumulatively over the run.
signal xp_changed(current: float, needed: float, level: int)

## Emitted once per level gained, in order, with the points that level paid.
## [b]This is the hook the skill tree hangs off[/b] (issue #9): a listener that
## grants a talent choice, opens a panel or plays a sting subscribes here and
## needs to know nothing else about XP.
signal leveled_up(level: int, points_awarded: int)

## Emitted when the unspent-point total changes, by earning or by spending.
signal points_changed(points: int)

## XP required for the very first level-up, and how much more each subsequent
## level costs. Linear on purpose: a curve is a balance decision, and there is
## nothing to balance it against until the skill tree exists. Exports rather
## than constants so that decision can be made per-actor without touching this.
@export var xp_to_first_level := 30.0
@export var xp_step_per_level := 15.0

## Points paid per level gained.
@export var points_per_level := 1

## Runs start at level 1 with nothing banked.
var level := 1
var xp := 0.0
var skill_points := 0


## XP needed to reach the next level, from the current one.
func xp_to_next() -> float:
	return xp_to_first_level + xp_step_per_level * float(level - 1)


## Award XP, levelling up as many times as it pays for.
##
## The loop is not defensive coding: one kill can cross two thresholds once a
## boss or an objective is worth more than a level, and a version that levelled
## once and banked the rest would swallow a point silently.
func grant(amount: float) -> void:
	if amount <= 0.0:
		return
	xp += amount
	var leveled := false
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		skill_points += points_per_level
		leveled = true
		# Inside the loop, so a listener that reads `level` or `skill_points`
		# sees the level being announced rather than the last of a batch.
		leveled_up.emit(level, points_per_level)
	if leveled:
		points_changed.emit(skill_points)
	xp_changed.emit(xp, xp_to_next(), level)


## Spend [param amount] points, or refuse and change nothing.
##
## The refusal is the whole value of routing spending through here: a caller
## that checked [member skill_points] itself and then decremented it would work
## until two skills were bought in the same frame.
func spend(amount := 1) -> bool:
	if amount <= 0 or amount > skill_points:
		return false
	skill_points -= amount
	points_changed.emit(skill_points)
	return true


## Push the current state at a fresh listener. Nothing re-sends these signals,
## so a HUD connected after the fact would otherwise draw an empty bar until the
## first kill.
func emit_current() -> void:
	points_changed.emit(skill_points)
	xp_changed.emit(xp, xp_to_next(), level)
