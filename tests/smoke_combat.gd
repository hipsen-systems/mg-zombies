extends "res://tests/harness.gd"
## The hero fights: he kills what he is pointed at, picks up his own targets on
## an attack-move, and heals once the fighting stops (issues #7, #11).
##
## This is the throwaway script from PR #41 made permanent. It caught nothing
## when it was written, and it still proves four behaviours no static check can
## reach — every one of them is an emergent result of navigation, sensing,
## cooldowns and physics agreeing with each other over several hundred frames.
##
## [b]Every assertion here is a bound, not a number.[/b] How long a kill takes
## depends on how far the hero has to walk, which depends on the layout, which
## issue #37 has already changed once. "Dead inside 30 s" survives that; "dead
## in 583 frames" is a false alarm waiting to happen.

## Budget for one engagement — closing the distance plus the fight itself.
## Measured at ~10 s and ~6 s for the two below.
const ENGAGE_BUDGET := 1800

## Seconds of quiet to prove regeneration, comfortably past `regen_delay` (5 s).
const REGEN_FRAMES := 600

var _kills: Array = []


func _check() -> void:
	# The XP hook for issue #8. Connected before the first swing, because
	# attribution is the thing being checked and a late connection would test
	# only that the signal exists.
	hero.killed.connect(func(victim: Node3D) -> void: _kills.append(victim))

	var target = _nearest_enemy()
	if not check("there is something to fight", target != null):
		return
	note("nearest zombie is %.1f units away with %.0f hp"
		% [hero.global_position.distance_to(target.global_position), target.health.current])

	# --- 1. an explicit attack order closes and kills -------------------------
	var hp_before: float = hero.health.current
	hero.command_attack(target)
	await wait_for(
		"an attack order closes the distance and kills",
		func() -> bool: return not is_instance_valid(target) or target.is_dead(),
		ENGAGE_BUDGET,
		{"the hero lost the fight": func() -> bool: return hero.is_dead()},
	)
	# Not a fixed cost: it is the trade being real that matters. A kill that
	# costs nothing means the zombie never swung back.
	check("trading blows costs the hero health", hero.health.current < hp_before,
		"%.0f -> %.0f hp" % [hp_before, hero.health.current])
	check("the kill is attributed to the hero", _kills.size() == 1,
		"killed fired %d time(s)" % _kills.size())

	# --- 2. attack-move acquires a target on its own --------------------------
	var next = _nearest_enemy()
	if not check("there is a second zombie to attack-move at", next != null):
		return
	var approach: Vector3 = next.global_position
	note("attack-moving at a zombie %.1f units away" % hero.global_position.distance_to(approach))
	hero.command_attack_move(approach)
	await wait_for(
		"attack-move engages and kills without being handed a target",
		func() -> bool: return not is_instance_valid(next) or next.is_dead(),
		ENGAGE_BUDGET,
		{"the hero lost the fight": func() -> bool: return hero.is_dead()},
	)
	check("both kills are attributed", _kills.size() == 2,
		"killed fired %d time(s)" % _kills.size())

	# --- 3. out-of-combat regeneration ----------------------------------------
	# The reason the checkpoint in issue #38 is not also the healing mechanic:
	# without this, clearing a fight at low health leaves dying on purpose as
	# the only way to carry on.
	var hp_low: float = hero.health.current
	hero.command_stop()
	await step(REGEN_FRAMES)
	check("health comes back out of combat", hero.health.current > hp_low,
		"%.0f -> %.0f hp over %.0f s" % [
			hp_low, hero.health.current, REGEN_FRAMES / float(Engine.physics_ticks_per_second),
		])
	done()


## Nearest living enemy to the hero, horizontally.
func _nearest_enemy():
	var best = null
	var best_distance := INF
	for enemy in living_enemies():
		var offset: Vector3 = enemy.global_position - hero.global_position
		offset.y = 0.0
		if offset.length() < best_distance:
			best_distance = offset.length()
			best = enemy
	return best
