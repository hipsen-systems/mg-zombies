extends "res://tests/harness.gd"
## The two commands issue #67 added actually command something: `S` stops, and
## `H` stands ground rather than merely standing still for a moment.
##
## [b]Hold is the one that needs a test, and the reason is that it looks like
## IDLE from every angle except the one that matters.[/b] Both stand, both fight
## back, both leave the hero rooted for as long as nothing comes near. The
## difference only shows when something *does*: an idle hero acquires anything
## within `acquire_radius` — nine units, four times his reach — and walks to it,
## and a held hero does not move at all. A `HOLD` branch that fell through to
## IDLE's behaviour would pass every eyeball check in a running game right up
## until the moment the player was relying on it.
##
## The second half is the trap this was written against. `_finish_engagement()`
## drops the hero to IDLE when a target dies and there is no attack-move to
## resume, so without a guard the hold ends **on the first kill** — he stands his
## ground until it matters and then quietly stops, which is worse than not having
## the command, because by then the player has looked away.
##
## [b]The setup is driven off the hero's own acquisition, and the first version
## of this file is why.[/b] It picked the nearest zombie by distance and asserted
## an idle hero would walk to it; he stood still, correctly, because that zombie
## was behind rock — automatic acquisition requires line of sight and `tests/`
## cannot ask whether it has any. Waiting for him to take a target is the same
## question asked in a way this folder is allowed to ask it, and it proves range
## and sight together.
##
## Nothing here reads a `scenes/ui/` node, so the marker #67 also added is not
## covered; that boundary is this folder's, and issue #55 is where it is argued.

## Frames to watch him stand. 2 s — long enough that a hero who was going to
## walk has walked, since he covers 6 units a second.
const WATCH_FRAMES := 120

## How long to let him chase before taking the measurement away from him. Short
## on purpose: he closes at 6 units a second against a 3.4 approach, so a longer
## look would put him in melee and there would be nothing left to walk to.
const CHASE_FRAMES := 20

## What counts as having stayed put, and what counts as having moved. Bounds
## rather than measured values: settling and turning in place put a held hero a
## little off his mark, and a chase only has to cover half of a closing gap.
const STAYED_PUT := 0.6
const DEFINITELY_MOVED := 0.8


func _check() -> void:
	# --- 1. S cancels a move in flight ----------------------------------------
	var start: Vector3 = hero.global_position
	hero.command_move_to(level.boss_position())
	await wait_for("a move order gets him under way", func() -> bool:
		return hero.global_position.distance_to(start) > 1.5, 600)
	hero.command_stop()
	var stopped: Vector3 = hero.global_position
	await step(WATCH_FRAMES)
	check("and S stops him where he stands",
		hero.global_position.distance_to(stopped) < STAYED_PUT,
		"drifted %.2f units" % hero.global_position.distance_to(stopped))

	# --- 2. an acquiring order takes a target and goes to it ------------------
	# The contrast case, and it is what makes section 3 mean anything: "a held
	# hero did not move" is equally satisfied by a hero who was never going to.
	#
	# Attack-move rather than a plain move, and the difference is not cosmetic. A
	# MOVE order acquires nothing, so he walks past the zombie while it charges
	# him, and by the time the order finishes and he stands idle it is already on
	# top of him — measured at 2.79 units against a 2.2 reach, half a step to
	# close, which is no test of whether he travels. ATTACK_MOVE acquires from the
	# same branch of `_reassess()` that IDLE does, while he is still approaching,
	# so the target is taken at a distance he genuinely has to cross.
	var target = _nearest_living_enemy()
	if not check("there is a zombie to walk toward", target != null):
		return
	hero.command_attack_move(target.global_position)
	if not await wait_for("an acquiring order takes a target of its own",
		func() -> bool: return hero.is_dead() or hero.current_target() != null, 1800):
		return
	if not check("and is alive to do something about it", not hero.is_dead()):
		return
	var reach_at_acquire := _distance_to_target()
	check("which he has to walk to reach",
		reach_at_acquire > hero.attack_range,
		"%.2f units against a reach of %.1f" % [reach_at_acquire, hero.attack_range])

	var chase_from: Vector3 = hero.global_position
	await step(CHASE_FRAMES)
	var chase_moved: float = hero.global_position.distance_to(chase_from)
	check("and he closes on it", chase_moved > DEFINITELY_MOVED,
		"moved %.2f units in %d frames" % [chase_moved, CHASE_FRAMES])

	# --- 3. a held hero does not ----------------------------------------------
	var gap_at_hold := _distance_to_target()
	hero.command_hold_position()
	check("H puts him in hold", hero.is_holding_position())
	check("with the same target still out of reach", gap_at_hold > hero.attack_range,
		"%.2f units" % gap_at_hold)
	var held_from: Vector3 = hero.global_position
	await step(WATCH_FRAMES)
	var held_moved: float = hero.global_position.distance_to(held_from)
	check("a held hero stands his ground instead of closing",
		held_moved < STAYED_PUT,
		"moved %.2f units, against %.2f while acquiring" % [held_moved, chase_moved])
	if not check("and is alive to have held it", not hero.is_dead()):
		return

	# --- 4. and the hold outlives the kill ------------------------------------
	# The guard in _finish_engagement(). Without it this is where the order ends,
	# silently, at the first moment it was doing any work.
	var killed_something := [false]
	hero.connect(&"killed", func(_victim: Node3D) -> void: killed_something[0] = true)
	if not await wait_for("something walks into him and dies for it",
		func() -> bool: return killed_something[0] or hero.is_dead(), 1800):
		return
	if not check("he killed it rather than the other way round", not hero.is_dead()):
		return
	check("and he is still holding afterwards", hero.is_holding_position(),
		"order is %d" % hero.current_order())

	# --- 5. and any other order releases it -----------------------------------
	hero.command_stop()
	check("S stands him down again", not hero.is_holding_position())
	done()


func _nearest_living_enemy():
	var best = null
	var best_distance := INF
	for enemy in living_enemies():
		var distance: float = hero.global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## Distance to the enemy the hero has actually taken, or INF if he has none.
## His target rather than the nearest body: those differ whenever the nearest is
## behind rock, which is the mistake the header records.
func _distance_to_target() -> float:
	var target = hero.current_target()
	if target == null:
		return INF
	return hero.global_position.distance_to(target.global_position)
