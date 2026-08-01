extends "res://tests/harness.gd"
## The hero can walk the whole route, start cell to boss room.
##
## [b]This is the check `scenes/map/` says is the only one that covers the
## chokepoints.[/b] The map proves its layout connects with a flood fill over
## the grid, and that says nothing about the surface the navmesh bakes: the bake
## erodes the walkable ribbon by `agent_radius`, so a one-cell gap can be severed
## while every cell of it still reads as connected. The two could not disagree
## while every corridor was one cell wide, and since issue #37 they can. Ordering
## a unit end to end is the only thing that tells them apart.
##
## It is also the shape of the bug that produced issue #16 — a navmesh whose
## agents never advance past their first waypoint — and the one a static check
## structurally cannot see.
##
## [b]A move order is used rather than an attack-move, and that is the second
## thing being asserted.[/b] `scenes/hero/` records "sprint past the encounter"
## as a real choice rather than a bug: MOVE acquires nothing and runs the
## gauntlet untouched. So arriving alive is a claim about the route being
## survivable at full health, and a difficulty change that quietly ends that
## shows up here rather than in play. He arrives with 44 of 100 hp, so there is
## not much of that claim spare — when this goes red, re-measure and decide
## whether the run got harder on purpose. Do not reach for the budget.

## Close enough to the boss cell to have arrived. The order clamps its
## destination onto the navmesh and the boss is standing on the cell, so the
## hero stops at his attack range rather than on the marker.
const ARRIVAL_RADIUS := 6.0

## 60 s of simulated travel against ~29 s measured. Generous on purpose: the
## number moves with the layout, and a budget that has to be re-tuned after
## every map edit is a budget nobody trusts.
const TRAVEL_BUDGET := 3600


func _check() -> void:
	var goal: Vector3 = level.boss_position()
	var start: Vector3 = hero.global_position
	note("start %s -> boss room %s, %.0f units apart" % [start, goal, start.distance_to(goal)])

	hero.command_move_to(goal)
	# Frame budget rather than a distance-per-second estimate: a stalled agent
	# and a slow one are the same picture, and the only thing that matters is
	# that the run ends rather than hangs.
	await wait_for(
		"hero walks the whole route to the boss room",
		func() -> bool: return hero.global_position.distance_to(goal) <= ARRIVAL_RADIUS,
		TRAVEL_BUDGET,
		{"hero was killed on the way": func() -> bool: return hero.is_dead()},
	)
	note("arrived with %.0f/%.0f hp" % [hero.health.current, hero.health.max_health])

	# He walked past the trash and through both chokepoints without stopping to
	# fight, which is the design claim above. Asserted after arrival rather than
	# during, because being hit is expected — being *stopped* is not.
	check("the boss is still standing when he gets there",
		living_enemies().any(func(e) -> bool: return e.global_position.distance_to(goal) < ARRIVAL_RADIUS))
	done()
