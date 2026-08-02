extends SceneTree
## Shared driver for the headless smoke tests (issue #16).
##
## A smoke test extends this, overrides [method _check], and asserts against the
## real `scenes/main.tscn` — the scene the player gets — brought up headless and
## stepped one physics frame at a time. No test framework is involved: Godot's
## own [SceneTree] is the main loop, and the exit code is the result.
##
## [b]Run one with:[/b]
## [codeblock]
## "$GODOT" --headless --path . --fixed-fps 60 --script res://tests/smoke_x.gd
## [/codeblock]
##
## [b]Why the file is called harness.gd and not smoke_harness.gd.[/b] The CI
## runner executes every `tests/smoke_*.gd`, so anything matching that glob is a
## test. A base class named to match would be run as one and pass vacuously.
##
## [b]--fixed-fps is not an optimisation, it is the thing that makes this
## affordable.[/b] Without it the main loop paces itself against the wall clock
## and a run costs its own simulated duration — 35 s for the traversal test.
## With it the loop runs flat out on a fixed delta: the same run takes 2.4 s,
## and the simulation stops depending on how fast the machine happens to be.
## Everything below counts *physics frames* rather than seconds for the same
## reason. The fixed delta is half of what makes a run repeatable; the other
## half is [constant RNG_SEED].
##
## [b]Three rules the throwaway versions of this script learned the hard way,
## kept here so no test has to remember them:[/b]
##
## - [b]Wait out the startup before touching anything.[/b] `main.gd` bakes the
##   navmesh in `_ready()` and the navigation server syncs a frame later, so a
##   position or a path read too early is the map origin rather than a real
##   answer. [constant SETTLE_FRAMES] covers it.
## - [b]Every wait is budgeted, and running out is a failure.[/b] A hung CI job
##   is a far worse outcome than a red one, and it is the failure mode this
##   style of test invites: waiting on something that will never happen.
## - [b]Assert against measured values with margin, never exact ones.[/b] Path
##   lengths shift with the layout and the numbers here are measured on one
##   machine. "Kills it inside N frames" survives a map edit; "kills it in 583
##   frames" is a false alarm waiting for issue #37's successor.
##
## [b]And one rule this file enforces rather than states: a test must end by
## calling [method done].[/b] A GDScript runtime error inside a coroutine kills
## that coroutine and resumes whoever was awaiting it, with nothing raised and
## nothing returned — so the first version of this harness answered a test that
## died halfway with "PASSED 1 check(s)" and exit 0. A run is now only green if
## the test says it reached the end, which is the safe direction to fail in:
## forgetting the call reports a failure, where the missing signal it replaces
## reported success.

## Physics frames to let the scene settle after `main.tscn` is added: the
## navmesh bake, the first server sync, and the actors falling the
## `SPAWN_CLEARANCE` they are dropped from.
const SETTLE_FRAMES := 30

## Default budget for [method wait_for], in physics frames — 30 s at 60 Hz.
const DEFAULT_BUDGET := 1800

## Hard ceiling on a whole run, in simulated seconds. This is a deadlock guard,
## not a budget: a GDScript error inside a coroutine kills that coroutine
## silently, and nothing would then ever call [method quit]. It is measured in
## simulated time, so a slow CI runner cannot trip it — only a stuck one.
const WATCHDOG_SECONDS := 300.0

## Fixed seed for the global RNG, set before the scene is built.
##
## [b]Without it these tests are a coin flip, and the traversal one is the proof:[/b]
## the walk to the boss room takes the same 1704 frames every run, because the
## hero's pathing is deterministic — but he arrived with 73 hp on one run and
## 54 on the next, because `scenes/enemies/` picks roam targets and staggers its
## sensing tick off the global RNG, which Godot seeds randomly at startup. Which
## zombies happen to be facing the corridor decides how much of the gauntlet
## actually connects. An unseeded run of a survival assertion is a required
## check that fails a PR for reasons the PR did not cause.
##
## The value is arbitrary; only its fixity matters. Changing it is a legitimate
## way to sample a different run of the game — expect the measured numbers in
## these files to move with it, and re-measure rather than widening a margin.
const RNG_SEED := 20260801

## The scene under test, and the two nodes every test so far needs out of it.
##
## Deliberately untyped. Naming `Hero` or `LevelMap` here would make this folder
## fail to parse whenever the global class cache is missing — which is the state
## a fresh checkout is in until `--import` has run, exactly when someone is most
## likely to be trying to find out whether the project still works.
var main: Node = null
var hero = null
var level = null

var _passes := 0
var _failed := false
var _completed := false
var _reported := false
var _elapsed := 0.0


func _initialize() -> void:
	# _initialize() itself cannot await — the engine calls it and discards what
	# it returns, so an await here suspends startup and never resumes. Calling a
	# coroutine from it is the whole workaround: _drive() returns immediately and
	# is resumed by the frame signals it awaits.
	_drive()


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _reported and _elapsed > WATCHDOG_SECONDS:
		fail("watchdog", "no result after %.0f s of simulated time — a coroutine is stuck or dead" % _elapsed)
	return false


## What a smoke test implements. Override it, drive the scene through
## [method step] and the public order APIs, assert with [method check] and
## [method wait_for], and finish by calling [method done].
func _check() -> void:
	fail("harness", "this smoke test does not override _check()")


## Called by a smoke test as its last statement, to claim it got that far.
## See the note at the top for why a run is not green without it.
func done() -> void:
	_completed = true


func _drive() -> void:
	await process_frame
	# Before the scene exists: the zombies draw their first roam target and their
	# sensing offset in `_ready()`, so a seed set afterwards would already be late.
	seed(RNG_SEED)
	var scene := load("res://scenes/main.tscn")
	main = scene.instantiate() if scene != null else null
	if main == null:
		fail("scene", "res://scenes/main.tscn did not instantiate")
		return
	root.add_child(main)
	await step(SETTLE_FRAMES)

	hero = get_first_node_in_group("hero")
	# By type rather than by node name, so renaming a node in main.tscn does not
	# quietly turn every test green-on-nothing.
	var levels := main.find_children("*", "LevelMap", true, false)
	level = levels[0] if not levels.is_empty() else null
	if hero == null or level == null:
		fail("scene", "main.tscn came up without a hero (%s) or a level (%s)" % [hero, level])
		return

	var before := _passes
	await _check()
	if not _failed:
		# Both halves are about a test that stopped early without saying so: the
		# first catches a coroutine killed mid-run, the second an override that
		# asserted nothing at all and would otherwise report a green empty run.
		if not _completed:
			fail("test", "_check() did not reach done() — look for a script error above")
		elif _passes == before:
			fail("test", "_check() ran to the end without asserting anything")
	_finish()


# --- Stepping ----------------------------------------------------------------

## Advance the simulation by [param frames] physics ticks.
func step(frames: int) -> void:
	for i in frames:
		await physics_frame


## Step until [param condition] returns true, up to [param budget] frames.
##
## Records a pass with what it cost, or a failure naming the budget it burned —
## which is the message that tells you whether something is broken or merely
## slower than the margin allows.
##
## [param abort_when] maps a reason to a [Callable]: if one of them goes true the
## wait gives up immediately and reports that reason. It exists because the
## interesting ways these waits fail are not "the condition stayed false" — the
## hero died on the way, the target was cleared out from under the test — and a
## budget timeout describes none of them. Waiting the full 30 s to report the
## wrong cause is the failure mode worth designing out.
func wait_for(
	what: String, condition: Callable, budget := DEFAULT_BUDGET, abort_when := {}
) -> bool:
	if _failed:
		return false
	var frames := 0
	while not condition.call():
		for reason in abort_when:
			if abort_when[reason].call():
				return fail(what, "%s (after %s)" % [reason, _frames_text(frames)])
		if frames >= budget:
			return fail(what, "still false after %s" % _frames_text(budget))
		await physics_frame
		frames += 1
	return check(what, true, _frames_text(frames))


# --- Reporting ---------------------------------------------------------------

## Record an assertion that is true or false right now.
func check(what: String, ok: bool, detail := "") -> bool:
	if _failed:
		return false
	if not ok:
		return fail(what, detail)
	_passes += 1
	print("PASS  ", what, "" if detail.is_empty() else "  (%s)" % detail)
	return true


## Record a value the test measured but does not assert on. Keeps the numbers a
## reader needs to judge a margin in the log, without freezing them into a check.
func note(text: String) -> void:
	print("      ", text)


## Fail the run. The first failure ends it: a smoke test that carries on after
## one assertion has broken reports a cascade, and the first line was the answer.
func fail(what: String, detail := "") -> bool:
	if _failed:
		return false
	_failed = true
	printerr("FAIL  ", what, "" if detail.is_empty() else ": %s" % detail)
	_finish()
	return false


func _finish() -> void:
	if _reported:
		return
	_reported = true
	if _failed:
		printerr("FAILED after %d passing check(s)" % _passes)
	else:
		print("PASSED %d check(s)" % _passes)
	# Ends the run: with the tree gone the frame signals stop firing, so a
	# coroutine suspended on one is never resumed and no further test code runs.
	quit(1 if _failed else 0)


# --- Reading the world -------------------------------------------------------

## Every enemy currently standing, corpses and cleared instances excluded.
func living_enemies() -> Array:
	var alive: Array = []
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.is_inside_tree() and not enemy.is_dead():
			alive.append(enemy)
	return alive


func _frames_text(frames: int) -> String:
	return "%d frames, %.1f s" % [frames, frames / float(Engine.physics_ticks_per_second)]
