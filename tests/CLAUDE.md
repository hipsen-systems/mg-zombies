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
| `smoke_progression.gd` | Kills pay XP, levels pay points, and points pay stats |
| `smoke_skills.gd` | The skill tree is sound, gates what it says, and sells nothing it must not |

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
- **`smoke_skills.gd` is where two cross-folder invariants stop being prose**
  (issue #9). The skill tree is authored in `scenes/skills/` and can silently
  undo a decision made somewhere else: `reach` could out-reach the end boss,
  whose longer swing is the one thing inverting the hero's advantage over every
  zombie (`scenes/enemies/`), and an `acquire_radius` skill could grow past the
  4-cell respawn clearance `scenes/map/` promises and `scenes/hero/` leans on.
  Neither folder can see a `.tres` in a third one. Both are asserted against a
  **fully invested** hero — the test buys the whole tree out — because a cap is
  only worth checking at the cap.
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
`skill_refusal`, `skill_problems` and the `skill_tree` export) since issues #8
and #9 — and through that export the read side of `scenes/skills/`
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

<!-- verified-against: aeec030 -->
