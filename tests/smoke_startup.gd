extends "res://tests/harness.gd"
## The level comes up as authored, and the navmesh under it is real.
##
## The cheapest test here and the one that fails first when the startup order in
## `scenes/main.gd` is disturbed — every other smoke test is downstream of the
## scene assembling correctly, so this one exists to say so in a single line
## rather than as three confusing timeouts.
##
## [b]The navmesh check is the point of the file.[/b] `NavigationServer3D`
## answers a query against an unbaked map with the map origin rather than an
## error, so a broken bake reads downstream as actors calmly walking to the
## middle of the level. That is the shape of the bug issue #16 was filed about:
## the default `cell_height` floated the baked surface half a unit over the floor
## and the hero jittered in place, with every static check passing.
##
## [b]It also checks a map rule that nothing else can.[/b] `scenes/map/` requires
## that nothing a respawn restores stands within 4 cells of the cell it lands the
## hero on, and `scenes/hero/` leans on that number: it is the only reason he
## cannot be swung at on the frame he comes back. The map's own build-time
## warning reads the spawn list, so it covers `Z` cells and cannot cover the boss
## — which is exactly the placement that would be moved by someone tuning the
## last fight.
##
## [b]Restored is the word this file had right and the docs had wrong[/b] (issue
## #54). The check below was always per-checkpoint over segment >= that
## checkpoint; three folder docs stated it over every placement, which the
## current map does not satisfy — a segment-1 zombie sits 3 cells from the boss
## gate. The docs were corrected to the form measured here.

## Half a cell. The hero is dropped from `SPAWN_CLEARANCE` above the start cell
## and settles under gravity, so "on the start cell" is horizontal.
const START_TOLERANCE := 2.0

## How far off the navmesh the hero may stand. He is placed on the cell centre
## and the surface is eroded by `agent_radius`, so this is slack for the erosion
## and the settle, not for a missing bake — that answers ~90 units out.
const NAVMESH_TOLERANCE := 1.5

## `scenes/map/`: nothing a respawn restores may stand within 4 cells of the
## cell it puts the hero on.
const CELL_SIZE := 4.0
const MIN_SPAWN_CLEARANCE := 4.0 * CELL_SIZE

## The current map meets that rule exactly — two checkpoints sit 4.000 cells
## from the nearest spawn they restore — so the comparison is made with a hair
## of slack rather than resting on float equality at the boundary. There is no
## room above it: one cell of drift in the layout trips this.
const CLEARANCE_EPSILON := 0.01


func _check() -> void:
	var start: Vector3 = level.start_position()
	var flat: Vector3 = hero.global_position - start
	flat.y = 0.0
	check("hero stands on the level's start cell", flat.length() <= START_TOLERANCE,
		"%.2f units off" % flat.length())
	check("hero comes up alive and whole",
		not hero.is_dead() and is_equal_approx(hero.health.current, hero.health.max_health),
		"%.0f/%.0f hp" % [hero.health.current, hero.health.max_health])

	# A query against an unbaked navigation map returns the map origin, so this
	# distance is the difference between "baked and synced" and "silently absent".
	var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(
		hero.get_world_3d().navigation_map, hero.global_position
	)
	check("the navmesh is baked and the hero is standing on it",
		on_mesh.distance_to(hero.global_position) <= NAVMESH_TOLERANCE,
		"%.2f units from the nearest navmesh point" % on_mesh.distance_to(hero.global_position))

	var spawns: Array[Dictionary] = level.zombie_spawns()
	var checkpoints: Array[PackedVector3Array] = level.checkpoints()
	note("%d zombie spawns, %d checkpoints (start included), boss in segment %d"
		% [spawns.size(), checkpoints.size(), level.boss_segment()])
	# One zombie per `Z`, plus the boss: main.gd populates the map from the
	# marks, so a mismatch means a spawn was dropped rather than a map edited.
	check("every spawn marker and the boss are standing in the level",
		living_enemies().size() == spawns.size() + 1,
		"%d alive, %d expected" % [living_enemies().size(), spawns.size() + 1])

	# The clearance rule, read off the map's own markers rather than off the
	# instances standing on them, because it is a claim about the *layout* — and
	# measured per checkpoint against what a respawn there restores (segment >=
	# that checkpoint), which is the form the rule is argued from: those are the
	# enemies that arrive back at their spawns together with the hero.
	#
	# The boss is included, and it is the reason to do this here at all. The
	# map's build-time warning reads the spawn list, so `B` is the one enemy
	# placement on the level bound by this rule with nothing checking it.
	var closest := INF
	var offender := ""
	for index in checkpoints.size():
		var point: Vector3 = checkpoints[index][0]
		var restored: Array[Dictionary] = spawns.duplicate()
		restored.append({"position": level.boss_position(), "segment": level.boss_segment()})
		for placement in restored:
			if int(placement["segment"]) < index:
				continue
			var offset: Vector3 = placement["position"] - point
			offset.y = 0.0
			if offset.length() >= closest:
				continue
			closest = offset.length()
			offender = "%.1f units (%.1f cells) from checkpoint %d" % [
				offset.length(), offset.length() / CELL_SIZE, index,
			]
	check("every enemy a respawn restores stands 4+ cells from where it lands",
		closest >= MIN_SPAWN_CLEARANCE - CLEARANCE_EPSILON, "nearest is %s" % offender)
	note("tightest restored-spawn clearance: %s" % offender)
	done()
