---
depends-on: [scenes, scenes/hero, scenes/enemies, scenes/map, scenes/components, scenes/skills]
---

# tests/

Headless smoke tests (issue #16). Each one brings up the real
`scenes/main.tscn`, drives it through the public gameplay APIs, and exits
non-zero if an assertion fails. There is still no test framework in this project
and these need none: a `SceneTree` script *is* a Godot main loop, so the engine
runs them and the exit code is the result.

They exist because four consecutive PRs (#41, #47, #48, #50) each wrote a
throwaway script of exactly this shape, proved something no static check can
see, and then deleted it. #41's caught the navmesh `cell_height` bug that left
the hero jittering in place with every check green; #48's caught a checkpoint
placed one cell from a spawn.

| File | What it is |
|------|------------|
| `harness.gd` | The shared driver every test extends |
| `run.sh` | Runs the whole suite; used by CI and by hand |
| `smoke_startup.gd` | The level assembles as authored and the navmesh is real |
| `smoke_traversal.gd` | The hero walks start cell to boss room |
| `smoke_combat.gd` | He kills, acquires his own targets, and heals afterwards |
| `smoke_orders.gd` | `S` stops him, and `H` roots him — including across a kill |
| `smoke_progression.gd` | Kills pay XP, levels pay points, and points pay stats |
| `smoke_boss.gd` | The run can be finished: a hero who did the level can kill the boss |
| `smoke_skills.gd` | The skill tree is sound, gates what it says, sells nothing it must not, every node of it is reachable, and a stat that moves says so |
| `bench_crowd.gd` | **Not a test.** What a crowd of 50–400 enemies costs per physics frame (issue #72) |

## `bench_crowd.gd` is the one file here the runner ignores

It extends `harness.gd` like everything else, and the name is the whole
difference: `run.sh` globs `smoke_*.gd`, so a `bench_*` file is invisible to CI.
That is the same naming rule the base class follows, used in the other
direction.

**Keeping it out of the suite is deliberate.** A wall-clock measurement on a
shared CI runner is a coin flip, and a required check that fails for reasons the
PR did not cause is exactly what `RNG_SEED` exists to prevent. What it *does*
assert — that a 400-strong crowd still paths, stands on the navmesh, keeps its
members and really is chasing — is machine-independent, so those are `check()`s
and every timing is a `note()`. Run it by hand when something touches enemy AI,
navigation, or the physics settings:

```bash
"$GODOT" --headless --path . --fixed-fps 60 --script res://tests/bench_crowd.gd
```

~30 s, and it prints a table. The measured ceiling it produced, and what that
means for the crowd sizes the outdoor direction asks for, is in
`scenes/enemies/CLAUDE.md` — this folder owns how the number is taken, that one
owns what the number says.

Three things it had to learn, all of which generalise to any measurement here:

- **The first crowd a process builds is not the price of a crowd.** The original
  run reported a 50-strong crowd at 4.21 ms and a 100-strong one at 3.09 ms. A
  crowd cannot get cheaper as it grows, so that was one-off setup — the
  navigation server meeting agents it had never seen, every code path running
  once — landing inside the first sample and reading as the marginal cost of an
  enemy. There is now a discarded warm-up pass before the table starts.
- **`Performance.TIME_PHYSICS_PROCESS` cannot be used here.** Under
  `--headless --fixed-fps` it reported 37 ms of physics inside a 0.85 ms frame.
  Whatever that monitor is timing in this mode, it is not the frame we are in.
  Wall clock between two `physics_frame` signals is the only number in the file,
  and it is trustworthy for the reason `--fixed-fps` exists: the loop runs flat
  out, so real time elapsed *is* compute cost.
- **A row labelled 200 owes proof that 200 of them were working.** Every way a
  chase sample can quietly become a smaller one — a leash, a lost hero, a crowd
  that arrived and stopped — leaves the timing looking perfectly reasonable. The
  crowd is counted at chase speed while it is timed, and that count is asserted.
  Same shape as the cycle-check rule below: a measurement that cannot fail is
  not a measurement.

## Running them

```bash
bash tests/run.sh "$GODOT"
```

Whole suite, ~5 s. `$GODOT` is the machine-specific binary path from
`CLAUDE.local.md`. One test on its own:

```bash
"$GODOT" --headless --path . --fixed-fps 60 --script res://tests/smoke_combat.gd
```

`build-check` runs `run.sh` as a step of its existing job, so the suite is
gated by a status check that was already required — see the root `CLAUDE.md`.
The tests are excluded from both export presets, so they do not ship in the
public web build.

## Two flags do the work, and neither is optional

- **`--fixed-fps 60` unhooks the main loop from the wall clock.** Without it a
  run costs the time it simulates: the traversal test is 28 s of game time, and
  took 35 s to run. With it, 2.4 s. Keep the number equal to the project's
  physics tick rate; they are separate settings that happen to agree.
- **`harness.gd` seeds the global RNG.** `scenes/enemies/` picks roam targets
  and staggers its sensing tick off `randf()`, which Godot seeds randomly at
  startup, and which zombies happen to be facing the corridor decides how much
  of the gauntlet connects. Unseeded, the traversal test arrived with 73, 54 and
  44 hp on three runs of unchanged code. A survival assertion on a required
  check cannot be a coin flip.

## Writing one

Extend `harness.gd`, override `_check()`, **and finish by calling `done()`**.
Name it `smoke_*.gd` or the runner will not find it; name anything that is *not*
a test something else, which is why the base class is `harness.gd`.

```gdscript
extends "res://tests/harness.gd"

func _check() -> void:
    hero.command_move_to(level.boss_position())
    await wait_for("he gets there", func() -> bool: return ..., 3600)
    check("and is still alive", not hero.is_dead())
    done()
```

`check`, `wait_for`, `step`, `note` and `living_enemies` are the whole API;
`main`, `hero` and `level` are already resolved and settled. The first failure
ends the run, because a smoke test that carries on past a broken assertion
reports a cascade and the first line was already the answer.

## Gotchas

- **`done()` is not ceremony.** A GDScript runtime error inside a coroutine
  kills that coroutine and resumes whoever awaited it, raising nothing and
  returning nothing. The first version of this harness answered a test that died
  halfway through with `PASSED 1 check(s)` and exit 0. Requiring the test to say
  it reached the end converts that into a failure, and forgetting the call fails
  in the safe direction.
- **`_initialize()` cannot `await`** — the engine discards what it returns, so
  suspending there never resumes. Call a coroutine from it instead; that is what
  `harness.gd` does, and it is why `await physics_frame` works at all here.
- **Nothing may be read for `SETTLE_FRAMES` after the scene is added.**
  `scenes/main.gd` bakes the navmesh in `_ready()` and the navigation server
  syncs a frame later; a path or position read before that answers with the map
  origin rather than an error, so the symptom is plausible wrong numbers.
- **A checker has to be shown a failure, not only a pass.** `smoke_skills.gd`
  asserts the shipped skill tree validates clean *and* that a deliberately
  cyclic one does not, because the first assertion alone is equally satisfied by
  a validator that never reports anything. Cross-review of PR #61 read the cycle
  check as dead code for exactly that reason, and could not be answered from the
  suite. Anything here that asserts "no problems found" owes a companion that
  proves the finder works. Deep-duplicate before breaking something: resources
  reached through the hero are shared, and the run is still using them.
- **Assert bounds, never measured values.** Every number in these files was
  measured on one machine, and CI runs a different build on a different OS.
  Budgets are generous on purpose: the traversal test allows 3600 frames for a
  walk that takes 1704.
- **A test may read a component directly; it must not write to one.** Reaching
  past an actor into its `Health` or `Experience` child to *set up* a state is
  the tempting shortcut here, and `scenes/components/` states the convention
  without exceptions — writes go through the owner's forwarding method. A test
  is the worst place to take the first exception, because it is the file
  somebody copies when they write the next one. `smoke_progression.gd` tops up
  XP through the hero and reads the component for its assertions, which is the
  shape to follow. Cross-review of PR #58 caught it doing the opposite.
- **`hero` and `level` are deliberately untyped.** Naming `Hero` or `LevelMap`
  would make this folder fail to parse whenever the global class cache is
  missing — the state a fresh checkout is in until `--import` has run, which is
  exactly when someone wants to know whether the project still works. The cost
  is that `var x := hero.something` cannot infer a type; write `var x: Vector3 =`.

## What this folder asks of the rest of the project

It is the first thing here that turns a convention into something that fails a
PR, so the constraints run outward as well as in:

- **The `hero` and `enemies` groups, and the public order API on
  `scenes/hero/`, are what these drive.** Both were already documented as
  contracts; they are now enforced ones.
- **The traversal test asserts that a plain move order survives the run.**
  `scenes/hero/` records "sprint past the encounter" as a real choice rather
  than a bug, and this is where that stops being a claim. It arrives with 44 of
  100 hp, so a difficulty change with any weight to it will turn this red —
  **that is the signal, not a false alarm.** Re-measure and decide; do not widen
  the margin to make it quiet.
- **`smoke_startup.gd` checks the map's respawn-clearance rule**, which
  `scenes/map/` states and `scenes/hero/` leans on, and covers the boss cell —
  the one enemy placement bound by that rule that the map's own build-time
  warning cannot see, because it reads the spawn list. The current map meets it
  exactly (4.000 cells, twice), so there is no slack to spend.
- **`smoke_progression.gd` guards a rule with no other keeper** (issue #8): that
  reaching a level raises no stat by itself, and every stat gain is bought with
  a point. The root `CLAUDE.md` states it as design intent and `scenes/hero/`
  owns every stat that could quietly break it — but nothing else *checks* it,
  and the failure mode is friendly rather than obviously wrong ("levelling feels
  stingy, give it a little something"). It is the first assertion here that is
  primarily **negative**: what must *not* have changed.
- **`smoke_boss.gd` asserts that the game has an ending** (issue #66), which
  nothing did before and which turned out not to be true. The boss shipped in #39
  with numbers its own doc called a first pass; no build a player can reach could
  kill it, and the run was unfinishable for as long as that went unnoticed —
  with every check here green, because none of them fought it.
  Three things about it are deliberate. It funds the hero with **exactly** what
  the level pays (19 kills, 3 points) rather than the full build every other test
  here constructs, because a cap is checked at the cap and a *floor* has to be
  checked at the floor. It **clears the room first**, which is not a softer fight
  but the same one: those 19 kills are what paid for the points, so a hero
  holding them has already done it. And it plays the fight **badly on purpose** —
  walk in and stand there — so what it asserts is that a solution exists for a
  player who has not mastered the encounter, never that the encounter is easy.
  It was run against the old numbers to prove it discriminates, and it fails
  there with the symptom playtesting reported.
- **`smoke_orders.gd` covers an order that is invisible when it breaks** (issue
  #67). `HOLD` looks exactly like `IDLE` from every angle except the one that
  matters: both stand, both fight back, and the difference only shows when
  something comes within `acquire_radius` but outside reach — an idle hero walks
  to it and a held one does not. A `HOLD` branch that fell through to IDLE's
  behaviour would survive any amount of playing until the moment a player was
  relying on it. Its second half is the `_finish_engagement()` guard, and that
  one was **run against the guard removed** to prove it discriminates: without
  it the order silently ends on the first kill. It closes with **both** ways out
  of the order — a cancel and an ordinary move — because the claim being asserted
  is that *every* command releases a hold, and the cancel alone only proves the
  cancel. They share one choke point today; the second check is what would notice
  that stopping being true. Cross-review of PR #70 asked for it.
  It also carries this folder's sharpest lesson about writing tests here. The
  first version picked the nearest zombie by distance and asserted an idle hero
  would walk to it. He stood still — **correctly**, because that zombie was
  behind rock, and automatic acquisition requires line of sight while this folder
  has no way to ask whether there is any. The fix was to stop asserting what the
  hero *should* target and wait for `current_target()` to fill, which proves
  range and sight together in a question this folder is allowed to ask. **A test
  that reaches for world state the hero reasons about differently is measuring
  its own assumption.**
- **`smoke_skills.gd` is where two cross-folder invariants stop being prose**
  (issue #9). The skill tree is authored in `scenes/skills/` and can silently
  undo a decision made somewhere else: `reach` could out-reach the end boss,
  whose longer swing is the one thing inverting the hero's advantage over every
  zombie (`scenes/enemies/`), and an `acquire_radius` skill could grow past the
  4-cell respawn clearance `scenes/map/` promises and `scenes/hero/` leans on.
  Neither folder can see a `.tres` in a third one. Both are asserted against a
  **fully invested** hero — the test buys the whole tree out — because a cap is
  only worth checking at the cap.
- **`smoke_skills.gd` also guards that the tree stays reachable** (issue #62).
  Four of six nodes had no hotkey and so no way to be bought in play; the panel
  answers that by drawing whatever `Hero.skill_catalogue()` hands it, which makes
  that one report the whole of what a player can reach. Narrowing it to the bound
  skills — which is exactly what `skill_summary()` beside it deliberately does —
  would restore the bug **with the panel still on screen**. So the assertion is
  that the catalogue lists strictly more than the keys reach, not merely that it
  lists something. It also checks the tree falls into more than one prerequisite
  tier, because a `SkillTree.depth()` returning a constant would collapse the
  panel to one row and satisfy every other check here: the same "how would you
  tell this from a function that does nothing" gap the cycle check exists for.
- **`smoke_skills.gd` also holds the seam a screen bug was fixed on** (issue
  #65). `scenes/ui/` reads `unit_info()` once at selection, so a stat moving
  under it left the bar showing the pre-purchase damage; the hero now emits
  `stats_changed` from his fold. What is asserted is not that the signal fires
  but **when** — a listener redrawing from it must already be able to read the
  new value, since a signal emitted before the write would leave the panel
  permanently one purchase behind and looking exactly like the original bug. This
  is the boundary case below in miniature: the invariant lives on the screen, the
  only half of it checkable from here lives on the hero, and the difference is
  worth knowing rather than papering over.
- **It asserts all of that without reading a single `scenes/ui/` node**, which is
  the deliberate part. Everything the panel prints comes from the hero, so the
  hero is where it can be checked — and this folder's boundary below stays true.
  What that leaves unproven is anything about the screen itself, and PR #62 wrote
  **two** throwaways against it rather than one. The first drove the real `HUD`
  and, with a screenshot, found two layout faults. The second reproduced a
  cross-review finding — a 1.2 s window after the boss dies in which the panel
  could be opened over a still-running level — and was run against the code with
  the fix backed out to prove it discriminated, which is the same discipline the
  cycle check above owes. Neither was kept, and both reached into `scenes/ui/`
  private members to do their work, which is exactly why they are not here.
  **Issue #55 is the standing question of whether throwaways like these belong in
  this folder; PR #62 is two more data points for it, and the second is the
  stronger kind — a test that caught a real regression window rather than
  confirming something already believed.**
- **It also settled what that rule says**, which is the more interesting half.
  The check is per checkpoint over the placements a respawn *there* restores;
  three folder docs stated it over every placement on the map, and measuring it
  showed that version to be false by a cell (issue #54, now fixed in those
  docs). A number three docs cited as a contract had never been measured until
  something here measured it — which is the argument for this folder, made
  without anyone planning it.

## Dependencies

Everything here is downstream and nothing depends on it, which is why the
frontmatter above is long. It reads `scenes/main.tscn` and the startup order
`scenes/` owns, the command API and `killed` signal of `scenes/hero/` — plus his
skill API (`gain_experience`, `spend_skill_point`, `skill_rank`,
`skill_refusal`, `skill_problems`, `skill_summary`, `skill_catalogue` and the
`skill_tree` export) since issues #8, #9 and #62, his `unit_info()` report and
the `stats_changed` signal since #65, and `command_hold_position()`,
`is_holding_position()`, `current_order()` and `current_target()` since #67 —
and through that export the
read side of `scenes/skills/`
(`SkillTree.ids`, `node`, `cost_of_next_rank`, `total_cost`, `validate`, and a
node's `max_rank` / `requires` / `effects`; `requires` is also *written*, on a
deep duplicate, to build the broken tree above). Also the
`is_dead()`/group contract and
`xp_reward` of `scenes/enemies/`, `LevelMap`'s public geometry API from
`scenes/map/`, and from `scenes/components/` the `health` and `experience`
children — `current`/`max_health` on one, and `level`/`xp`/`skill_points`,
`xp_to_next()` and the `leveled_up` signal on the other.
It reads no `scenes/ui/` node: nothing here asserts anything about the screen,
including the XP bar #8 added.

`bench_crowd.gd` adds three things to that list, and they are the only places
anything here reaches past the public APIs above.

- It **instances `scenes/enemies/zombie.tscn` itself** rather than letting the
  map decide how many enemies exist — the whole file is a sweep over that number,
  so it cannot come from the layout. `LevelMap.bounds()` comes with it, to
  scatter them over the footprint; that one is new here.
- It **writes four of the enemy's own exports**, and the rule below is not in
  play for any of them: every one is a per-instance export `scenes/enemies/`
  provides precisely so a second enemy needs no second script, all four are on
  the actor itself, and nothing is reached *through* an actor to get at a child
  of it — which is the move "must not write to a component" forbids.
  **The timing differs between them and the difference is deliberate.**
  `attack_damage` and `display_name` are set before `add_child`, the ordering
  `scenes/main.gd` uses. The three radii are set later, at commit time, with the
  enemy already in the tree and ticking: applied at spawn, a 400-unit detection
  radius would make every scattered enemy with line of sight notice the hero
  unprompted, and the roaming rows would quietly have been measuring a second,
  smaller chase.
- It **reads `CharacterBody3D.velocity`** off the crowd to prove it is chasing.
  A public property of the body rather than the enemy's private state, and
  deliberately so: asking the state machine what state it thinks it is in would
  assert this file's assumption instead of the world.

<!-- verified-against: e9f8a21 -->
