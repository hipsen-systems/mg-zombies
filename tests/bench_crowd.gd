extends "res://tests/harness.gd"
## What a crowd of enemies costs per physics frame (issue #72).
##
## The outdoor direction calls for encounters of 100+ enemies, and nothing had
## measured whether that runs. Every enemy in `scenes/enemies/` is a
## `CharacterBody3D` carrying its own `NavigationAgent3D` and re-solving a path
## to the hero on every sense tick, so the cost of a horde is the cost of N
## simultaneous A* queries on the main thread. This file is the number.
##
## [b]It is not a smoke test, and the name is what keeps it out of CI.[/b]
## `run.sh` globs `tests/smoke_*.gd`; this is `bench_*`, so the suite does not
## pick it up. That is deliberate rather than shy: a wall-clock measurement on a
## shared CI runner is a coin flip, and a required check that fails for reasons
## the PR did not cause is the exact failure `harness.gd` seeds the RNG to avoid.
## The robustness half of the question — does a 400-strong crowd still path,
## stand on the floor and behave — [i]is[/i] asserted here, because those
## assertions are machine-independent.
##
## [b]Run it by hand:[/b]
## [codeblock]
## "$GODOT" --headless --path . --fixed-fps 60 --script res://tests/bench_crowd.gd
## [/codeblock]
##
## [b]Three scenarios, because the point is to discriminate between the levers,
## not just to produce one number.[/b] Issue #72 lists five possible fixes; which
## of them is worth building depends entirely on where the time goes:
##
## - [b]idle[/b] — N enemies scattered over the walkable map, roaming, hero
##   standing at the start cell. This is the floor: physics bodies stepping,
##   state machines ticking, and one path request every few seconds each. If
##   [i]this[/i] is what hurts, the lever is distance-based AI level-of-detail or
##   pooling, and no amount of shared pathing helps.
## - [b]chase[/b] — the same scattered crowd, every member committed, hero
##   walking away from them. Every committed enemy re-solves a full-length path
##   to a moving target on every sense tick. This is the case the flow-field
##   proposal exists for: one target, N solvers, all solving the same problem.
## - [b]melee[/b] — the crowd packed inside the hero's reach, so they are in
##   ATTACK rather than CHASE. Included because ATTACK repaths too — `_think()`
##   falls through to the same `target_position` assignment while
##   `_process_attack()` stands still and never reads the path — so a ring of
##   enemies in contact pays for N path solves per tick and throws all of them
##   away. If chase and melee cost the same, that waste is real and cheap to fix.
##
## [b]Headless measures logic, not rendering.[/b] There is no renderer in this
## run, so every millisecond below is navigation, physics and GDScript. That is
## the dominant cost at this scale and the one the levers address, but it means
## the numbers are a floor for the real frame: a crowd that fits in the budget
## here has not yet been shown to fit on screen. Per-instance skeletal animation
## on hundreds of bodies is a separate measurement and a separate issue.
##
## [b]Why the crowd is aggroed with [code]take_damage(0.0)[/code].[/b] Committing
## N enemies by walking the hero into detection range would commit however many
## happened to have line of sight, and the measurement would silently be of a
## different N than the one in the table. Damage aggroes regardless of range,
## sight or leash — `scenes/enemies/` states that as the rule that stops the hero
## whittling a zombie down from outside its detection radius — so a zero-damage
## hit is the public entry point that puts a known number of enemies into CHASE
## and changes nothing else. The crowd's radii are widened for the same reason:
## they hold the whole crowd committed for the length of the window instead of
## letting it leash home one at a time mid-sample.

## The crowd scene. The same one `scenes/main.gd` spawns from the map's `Z`
## cells, so what is measured is the shipping enemy and not a stripped stand-in.
const ZOMBIE_SCENE := preload("res://scenes/enemies/zombie.tscn")

## Crowd sizes, on top of the 20 enemies the level already carries. 0 is the
## baseline the rest are read against — the marginal cost of an enemy is the
## interesting number, and without a zero row it cannot be separated from the
## fixed cost of running the scene at all. 400 is past what issue #72 asked for
## and is there to find the cliff rather than to confirm the plateau.
const COUNTS: Array[int] = [0, 50, 100, 200, 400]

## Frames discarded before each sample: the crowd's first paths get solved, the
## damage-flash tweens finish, and the hero gets moving. One second at 60 Hz.
const WARMUP_FRAMES := 60

## Frames per sample. Four seconds covers 20 sense ticks, so every enemy has
## repathed 20 times and the staggered ticks have gone round several times —
## a window shorter than that samples the stagger rather than the load.
const MEASURE_FRAMES := 240

const FRAME_BUDGET_MS := 1000.0 / 60.0

## Radii given to the crowd [i]at commit time, not at spawn[/i], so that a
## commitment made at the top of a sample survives to the bottom of it. Nothing
## else about the enemy is changed: these gate *which state* it is in, never what
## a tick in that state costs.
##
## Applying them at spawn would wreck the idle sample rather than help it — a
## 400-unit detection radius makes every scattered enemy with line of sight to
## the hero notice him unprompted, and "idle" would quietly become a second,
## smaller chase. Until the commit the crowd carries the shipped 12/18/26.
const CROWD_DETECTION := 400.0
const CROWD_AGGRO := 600.0
const CROWD_LEASH := 4000.0

## The crowd hits for nothing. A hundred enemies in contact kill the hero in a
## single tick, and a dead hero drops the whole crowd into RETURN — which would
## measure the walk home rather than the chase. Zeroing the damage is the
## smallest change that removes the confound: they still enter ATTACK, still
## swing on cooldown, still repath, and the hero survives to be chased.
const CROWD_DAMAGE := 0.0

## Same as `scenes/main.gd`: drop them just above the floor and let gravity
## settle them rather than guessing the tile height.
const SPAWN_CLEARANCE := 0.3

## Scattering: pick a point in the level's footprint, snap it to the navmesh, and
## keep it only if the snap barely moved — a point that snapped a long way was
## inside rock, and accepting it would pile the crowd against the walkable edges
## instead of spreading it over the floor.
const SCATTER_TRIES := 16
const SCATTER_SNAP_TOLERANCE := 2.0

## Melee packing radius. Inside the zombie's 2.0 attack range, so the crowd is in
## ATTACK rather than CHASE. They do not collide with each other, so overlapping
## is not the artefact it would be for anything else.
const MELEE_RADIUS := 1.8

## Horizontal speed above which a crowd member must be chasing rather than
## roaming. Between the shipped `roam_speed` (1.3) and `chase_speed` (3.4), so it
## separates the two without resting on either exact value.
const CHASE_SPEED_FLOOR := 2.0

## What fraction of a committed crowd has to be visibly travelling for a chase
## sample to be of the N it claims. Not all of it: a chaser standing in contact
## with the hero is in ATTACK and correctly still, and a path that finishes on
## the frame it is sampled reads as stopped.
const CHASE_COMMITMENT := 0.75

## Crowd size for the discarded warm-up pass. See [method _check].
const WARMUP_CROWD := 50

## How far a body may sit below the floor before it counts as fallen through.
const FLOOR_TOLERANCE := 2.0

## How far off the navmesh a settled body may stand. Same slack
## `smoke_startup.gd` allows the hero, for the same erosion.
const NAVMESH_TOLERANCE := 1.5

var _crowd_root: Node3D = null
var _rows: Array[Dictionary] = []


func _check() -> void:
	_crowd_root = Node3D.new()
	_crowd_root.name = "BenchCrowd"
	main.add_child(_crowd_root)

	var home: Vector3 = level.start_position() + Vector3(0, SPAWN_CLEARANCE, 0)
	var away: Vector3 = level.boss_position()
	var resident := living_enemies().size()
	note("level carries %d enemies of its own; crowd sizes are on top of that" % resident)

	# Discarded, and the reason it exists is a row this file printed before it
	# did: the first 50-strong crowd the process ever built measured 4.21 ms
	# against the 100-strong crowd's 3.09 ms, with a 29 ms worst frame. A crowd
	# cannot cost less as it grows, so that was one-off setup — the navigation
	# server registering agents it has never seen, and every code path below
	# running for the first time — landing inside the first real sample and
	# reading as the marginal cost of an enemy. Paying it here in the open is
	# cheaper than explaining it in a footnote for the rest of the project.
	_spawn_crowd(WARMUP_CROWD, _scattered_points(WARMUP_CROWD))
	_commit_crowd()
	await step(WARMUP_FRAMES)
	await _sample("discard", WARMUP_CROWD)
	await _clear_crowd(home)

	for count in COUNTS:
		await _measure_count(count, home, away)

	_report()

	# The closing baseline is the whole reason the run can be trusted. Every
	# sample above shares one process, one navigation map and one set of level
	# zombies that have been aggroed and scattered by five passes of the hero, so
	# a drifting scene would show up as a rising trend and read as a crowd cost.
	# Re-measuring the empty case last is how that is told apart from the real
	# thing: if it matches the opening row, nothing accumulated.
	var closing := await _sample("idle", 0)
	var opening: Dictionary = _rows[0]
	var drift: float = absf(closing["mean_ms"] - opening["mean_ms"])
	note("closing baseline %.3f ms against opening %.3f ms — drift %.3f ms"
		% [closing["mean_ms"], opening["mean_ms"], drift])
	check("the run did not drift: an empty scene still costs what it did at the start",
		drift <= maxf(opening["mean_ms"] * 0.5, 0.2),
		"%.3f ms apart" % drift)
	check("the level's own enemies are all still standing",
		living_enemies().size() == resident,
		"%d of %d" % [living_enemies().size(), resident])
	done()


## One crowd size, all three scenarios.
func _measure_count(count: int, home: Vector3, away: Vector3) -> void:
	if _failed:
		return

	# Scattered, roaming, hero out of the way. Measured first because committing
	# the crowd is one-way — a chased enemy does not go back to roaming inside a
	# window — so the idle sample has to be taken off the same placement before
	# the commit rather than off a second one after it.
	_spawn_crowd(count, _scattered_points(count))
	await step(WARMUP_FRAMES)
	_rows.append(await _sample("idle", count))

	# The same bodies, now every one of them solving a path to a moving hero.
	_commit_crowd()
	hero.command_move_to(away)
	await step(WARMUP_FRAMES)
	var chase: Dictionary = await _sample("chase", count)
	_rows.append(chase)
	_assert_crowd_is_sound("chase", count)
	if count > 0:
		# Without this the chase row is an unchecked claim about N. Every way it
		# could be wrong — a leash, a lost hero, a crowd that arrived and stopped —
		# leaves the timing looking perfectly reasonable for a smaller crowd.
		check("chase %d: the crowd really was chasing" % count,
			chase["travelling"] >= int(count * CHASE_COMMITMENT),
			"%d of %d moving at chase speed" % [chase["travelling"], count])
	await _clear_crowd(home)

	# Packed into contact, so they sit in ATTACK and repath for nothing.
	_spawn_crowd(count, _melee_points(count))
	_commit_crowd()
	await step(WARMUP_FRAMES)
	_rows.append(await _sample("melee", count))
	_assert_crowd_is_sound("melee", count)
	await _clear_crowd(home)


# --- Measuring ----------------------------------------------------------------


## Step [constant MEASURE_FRAMES] frames, timing each one.
##
## [b]Wall clock is the honest number here and the engine's own monitor is not.[/b]
## `--fixed-fps` unhooks the main loop from the clock and lets it run flat out, so
## the real time between two `physics_frame` signals is exactly what the frame
## cost to compute — which is the quantity a shipping game has 16.67 ms of.
## `Performance.TIME_PHYSICS_PROCESS` was measured alongside it in the first
## version of this file and then dropped: under `--headless --fixed-fps` it
## reported 37 ms of physics inside a 0.85 ms frame, which cannot be true of a
## slice of that frame. Whatever it is timing there, it is not this — and an
## unexplained number in a table is worse than a missing column, because the
## next reader will average it into something.
##
## [b]The crowd is counted while it is being timed, not assumed.[/b] A chase row
## that says 200 is worth nothing unless 200 enemies were really solving paths,
## and the ways that quietly fails — a leash, a lost hero, an early ATTACK — all
## look identical from outside. Horizontal speed separates them: a committed
## enemy travels at `chase_speed` (3.4), a roaming one at `roam_speed` (1.3), and
## anything standing still at 0.
##
## The maximum matters as much as the mean. A crowd that averages inside the
## budget and spikes past it every twentieth frame is a stutter, and the sense
## ticks are staggered precisely to stop that happening — this is where that
## staggering is either working or not.
func _sample(label: String, count: int) -> Dictionary:
	var frames := PackedFloat64Array()
	frames.resize(MEASURE_FRAMES)
	var travelling := 0
	var total_ms := 0.0
	for i in MEASURE_FRAMES:
		# The clock starts *after* the previous iteration's bookkeeping and stops
		# at the next physics frame, so counting the crowd below is outside every
		# figure here. It has to be: that loop is O(crowd), which is the one axis
		# this file measures, and folding it in would tilt exactly the slope the
		# whole exercise is for.
		var frame_start := Time.get_ticks_usec()
		await physics_frame
		frames[i] = (Time.get_ticks_usec() - frame_start) / 1000.0
		total_ms += frames[i]
		travelling = maxi(travelling, _travelling_crowd())

	var sorted := frames.duplicate()
	sorted.sort()
	var row := {
		"scenario": label,
		"count": count,
		"alive": living_enemies().size(),
		"travelling": travelling,
		"mean_ms": total_ms / MEASURE_FRAMES,
		"p95_ms": sorted[int(MEASURE_FRAMES * 0.95)],
		"max_ms": sorted[MEASURE_FRAMES - 1],
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}
	print("      %-6s %4d crowd  %6.2f ms mean  %6.2f p95  %6.2f max  %d alive, %d at chase speed"
		% [label, count, row["mean_ms"], row["p95_ms"], row["max_ms"], row["alive"],
			row["travelling"]])
	return row


## Crowd members currently moving faster than they could be roaming.
##
## Read off `CharacterBody3D.velocity`, which is public and set by the enemy's own
## `move_and_slide()`, rather than off its private state — the point is to check
## what the bodies are doing, and asking the state machine what it thinks it is
## doing would be measuring this file's assumption instead.
func _travelling_crowd() -> int:
	var moving := 0
	for zombie in _crowd_root.get_children():
		var flat := Vector2(zombie.velocity.x, zombie.velocity.z)
		if flat.length() > CHASE_SPEED_FLOOR:
			moving += 1
	return moving


## The table, printed once at the end so it can be pasted somewhere.
##
## Marginal cost per enemy is the number the levers are judged against: a fixed
## overhead that does not grow with the crowd is not a crowd problem, and only
## the slope says which of the two this is.
func _report() -> void:
	var baseline := {}
	for row in _rows:
		if row["count"] == 0:
			baseline[row["scenario"]] = row["mean_ms"]

	print("")
	print("  crowd  scenario    mean ms   p95 ms   max ms   % of 16.67ms   us per enemy")
	print("  -----  --------  ---------  -------  -------  -------------  -------------")
	for row in _rows:
		var per_enemy := "         —"
		if row["count"] > 0:
			var marginal: float = row["mean_ms"] - float(baseline.get(row["scenario"], 0.0))
			per_enemy = "%10.1f" % (marginal * 1000.0 / row["count"])
		print("  %5d  %-8s  %9.3f  %7.3f  %7.3f  %12.1f%%  %s"
			% [row["count"], row["scenario"], row["mean_ms"], row["p95_ms"], row["max_ms"],
				100.0 * row["mean_ms"] / FRAME_BUDGET_MS, per_enemy])
	print("")


# --- Building and tearing down the crowd ---------------------------------------


## Points spread over the walkable floor of the whole level.
func _scattered_points(count: int) -> Array[Vector3]:
	var footprint: Rect2 = level.bounds()
	var points: Array[Vector3] = []
	for i in count:
		var snapped_point := Vector3.ZERO
		for attempt in SCATTER_TRIES:
			var wanted := Vector3(
				footprint.position.x + randf() * footprint.size.x,
				0.0,
				footprint.position.y + randf() * footprint.size.y
			)
			snapped_point = _on_navmesh(wanted)
			# A point that barely moved was already on the floor. One that moved a
			# long way was inside rock, and taking it would stack the crowd along
			# the rock edges — which is a different measurement (short paths,
			# clumped agents) wearing this one's label.
			if snapped_point.distance_to(wanted) <= SCATTER_SNAP_TOLERANCE:
				break
		points.append(snapped_point)
	return points


## Points packed inside the hero's reach, so the crowd lands in ATTACK.
func _melee_points(count: int) -> Array[Vector3]:
	var centre: Vector3 = hero.global_position
	var points: Array[Vector3] = []
	for i in count:
		var angle := randf() * TAU
		var distance := sqrt(randf()) * MELEE_RADIUS
		points.append(_on_navmesh(
			centre + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		))
	return points


## Instance the crowd at [param points].
##
## Every export set here is set [i]before[/i] `add_child`, the same ordering
## `scenes/main.gd` uses and for the same reason: `Zombie._ready()` captures
## where it stands as home, and the enemy is in the tree and thinking from the
## frame it is added.
func _spawn_crowd(count: int, points: Array[Vector3]) -> void:
	for i in count:
		var zombie := ZOMBIE_SCENE.instantiate()
		zombie.position = points[i] + Vector3(0, SPAWN_CLEARANCE, 0)
		# The radii stay as authored until _commit_crowd() widens them; only the
		# damage is zeroed here, because a scattered crowd can land next to the
		# hero and the idle sample must not turn into a fight he loses.
		zombie.attack_damage = CROWD_DAMAGE
		zombie.display_name = "Bench Zombie"
		_crowd_root.add_child(zombie)


## Put the whole crowd into CHASE, through the public damage entry point.
##
## Zero damage, so nothing about the fight changes — but `Zombie.take_damage()`
## aggroes on being hit regardless of range, sight or leash, which is the only
## way to commit a known number of enemies rather than however many the geometry
## happened to give line of sight to.
func _commit_crowd() -> void:
	for zombie in _crowd_root.get_children():
		zombie.detection_radius = CROWD_DETECTION
		zombie.aggro_radius = CROWD_AGGRO
		zombie.leash_radius = CROWD_LEASH
		zombie.take_damage(0.0)


## Remove the crowd and put the hero back where the next sample starts.
##
## `remove_child` before `queue_free`, copying `scenes/main.gd`: a freed but
## still parented enemy stays in the `enemies` group until the end of the frame,
## and the hero can acquire and walk to one in between.
func _clear_crowd(home: Vector3) -> void:
	for zombie in _crowd_root.get_children():
		_crowd_root.remove_child(zombie)
		zombie.queue_free()
	# respawn_at() rather than a bare position write: it is the public teleport,
	# and it also clears the order, the target and the damage the level's own
	# zombies did on the way past — so every sample starts from the same hero.
	hero.respawn_at(home)
	await step(WARMUP_FRAMES)


# --- Robustness ----------------------------------------------------------------


## The half of issue #72 that is not a stopwatch: at 400 enemies, does anything
## actually break?
##
## These are machine-independent, which is why they are assertions where the
## timings are only notes. All three are failures that would read as balance or
## art problems rather than as scale problems, so they are worth naming: a crowd
## that silently loses members, one whose paths resolve to the map origin, and
## one whose bodies fall out of the world.
func _assert_crowd_is_sound(scenario: String, count: int) -> void:
	if count == 0 or _failed:
		return

	var standing := 0
	var off_mesh := 0
	var sunk := 0
	var worst_off := 0.0
	var worst_depth := 0.0
	for zombie in _crowd_root.get_children():
		if not is_instance_valid(zombie) or zombie.is_dead():
			continue
		standing += 1
		var here: Vector3 = zombie.global_position
		var nearest := _on_navmesh(here)
		var gap := nearest.distance_to(here)
		if gap > NAVMESH_TOLERANCE:
			off_mesh += 1
			worst_off = maxf(worst_off, gap)
		if here.y < -FLOOR_TOLERANCE:
			sunk += 1
			worst_depth = minf(worst_depth, here.y)

	# The hero kills what wanders into his reach, and over a five-second window
	# he gets through about one. Anything more than a handful means the crowd is
	# being destroyed rather than measured, and the row above is of a smaller N
	# than it claims.
	check("%s %d: the crowd is still standing" % [scenario, count],
		standing >= count - 5, "%d of %d" % [standing, count])
	# An unsynced navigation map answers a query with the map origin rather than
	# an error, so a crowd that quietly failed to path would stand exactly here
	# looking fine. This is the check that tells the two apart.
	check("%s %d: every body is on the navmesh" % [scenario, count],
		off_mesh == 0, "%d adrift, worst %.2f units" % [off_mesh, worst_off])
	check("%s %d: nothing fell through the floor" % [scenario, count],
		sunk == 0, "%d below, worst %.2f units" % [sunk, worst_depth])


func _on_navmesh(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(
		hero.get_world_3d().navigation_map, point
	)
