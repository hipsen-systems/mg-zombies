---
depends-on: [scenes, scenes/hero, assets]
---

# scenes/map/

The map format and the level builder (issues #6, #37, #38, #39, #73), and the
checkpoints laid out on it. Replaces the 40×40 test arena that `main.tscn`
used to carry.

| File | What it is |
|------|------------|
| `map_data.gd` (`class_name MapData`) | Reads a map file, checks every rule it is held to, and holds the result |
| `level_map.tscn` / `level_map.gd` (`class_name LevelMap`) | Builds a valid `MapData` into KayKit geometry; the only thing that knows a cell in world units |
| `checkpoint.tscn` / `checkpoint.gd` (`class_name Checkpoint`) | One respawn pad: a bare `Node3D` that generates its plates and triggers at runtime. Instanced by `scenes/main.gd`, not by the builder |

**The map files themselves live in [`maps/`](../../maps/CLAUDE.md)**, one
JSON file per map. This folder owns what a file may say and what it must obey;
that one owns which maps exist and what each is like. Until issue #73 the
level was an exported `PackedStringArray` literal inside `level_map.gd` —
data wearing a script as a costume — and every mark on it was a letter in the
grid.

Issue #37 renamed both scripts away from `maze`: the layout is deliberately
not a maze any more, and a class called `Maze` that builds a non-maze is the
kind of thing this project treats as a blocking review finding.

## The map format

**JSON, not a Godot resource, and that is a security decision rather than a
taste.** A `.tres` can carry a script reference, so `load()`ing an untrusted one
runs code on the player's machine; JSON parses to plain data and can do nothing
else. Community-authored maps are a stated horizon goal, which makes this cheap
now and impossible to retrofit later. Resources stay right for content the team
ships — `scenes/skills/` is the correct shape and should not change.

`maps/dungeon.json`, abridged:

```json
{
  "format_version": 1,
  "id": "dungeon",
  "display_name": "The Dungeon",
  "terrain": {
    "kind": "grid",
    "rows": [
      "############",
      "#..........#",
      "############"
    ]
  },
  "markers": [
    {"kind": "spawn", "cell": [6, 34]},
    {"kind": "boss", "cell": [30, 6], "asset": "boss"},
    {"kind": "checkpoint", "cells": [[21, 25], [22, 25], [23, 25]]}
  ],
  "actors": [
    {"asset": "zombie", "cell": [24, 5]}
  ]
}
```

- **`format_version`** is the first thing read and the only thing read from a
  file naming a version this build does not know. Anything that changes what
  the reader accepts — a new key, a new layer, a new marker kind — bumps it,
  because the reader refuses keys it does not know, and a v1 reader must say
  "this is a v2 file" rather than "this key is unknown".
- **`id`** is the map's name in anything that refers to it — a save (issue
  #77), a menu (#79) — so it is a contract like a skill node's id: rename
  `display_name` freely, retire an id rather than reuse it. Ids, and `asset`
  ids, are lowercase letters, digits and underscores, starting with a letter.
- **`terrain`** has one `kind` today, `grid`: rows of `#` (rock) and `.`
  (floor), north first, all the same length. **Only those two characters.**
  The spawn, the boss, a checkpoint, an enemy are all things placed *on* a
  floor cell, in the layer below that owns them, so nothing is ever said
  twice — a `Z` in the grid is refused, not read.
- **Positions are in the terrain's own space**, and for a grid that is a cell:
  `[column, row]`, zero-based, row 0 being the first string. Cells rather than
  world units because a hand-authored file has to be checkable by eye against
  the rows above it, which `[-62.0, 62.0]` is not. Outdoor terrain (issue #75)
  will be a second `kind` with positions in its own units under a different
  key, so the two can never be misread as each other.
- **`markers`** are the hand-placed things a run is made of. Exactly one
  `spawn` and exactly one `boss` — the boss marker carries the `asset` that
  stands on it, because where the run ends and what ends it are one authored
  fact. A `checkpoint` lists its `cells` explicitly: **one entry is one gate**,
  however many pads it spans, and that is authored now rather than derived
  from adjacency as it was in the grid.
- **`actors`** are placements: an `asset` id and a `cell`. A map never names a
  file — `"zombie"`, not a path — and nothing in this folder resolves the id.
  `MapData.assets_used()` lists them for whoever spawns things to check
  against what it can spawn, the same hook a skill tree offers an actor for
  its stat names. Today that is a two-entry table in `scenes/main.gd`; the
  registry (issue #74) replaces it.

**What v1 leaves out, deliberately.** The content pipeline names six layers —
`terrain`, `regions`, `boundaries`, `actors`, `markers`, `decoration` — and a
crowd as one actor entry with a count, a spread and a seed. v1 carries the
three the dungeon has, and a file that already contains `"decoration"` is
refused by name rather than silently read without it. Adding a layer is
additive and bumps the version; it should arrive with the first map that needs
it (#75), not ahead of one.

### Every map is checked, and a map with anything wrong is not built

`MapData.from_file()` returns one line per fault in `problems`, and
`LevelMap.load_map()` pushes each as an error and builds nothing — an empty
level rather than a half-built one, because a half-built level is the failure
that reads as something else downstream. `tests/smoke_map.gd` holds every
shipped map to it, and holds the checker to a broken map for each rule so it
cannot quietly stop checking.

Three stages, each gated on the one before, so a fault is reported once at the
level it belongs to rather than as a cascade:

| Stage | Refuses |
|-------|---------|
| shape | a file that is not JSON (with the line), or not an object; a missing or unknown `format_version`; a key the reader does not know at any level; a missing layer; a ragged grid or a character that is not `#`/`.`; a marker `kind` it does not know; not exactly one spawn and one boss; an id spelt wrong; a cell that is not two whole numbers |
| cells | a placement off the grid or on rock; two things on one cell; a checkpoint whose cells are not one connected gate; two checkpoints that touch |
| route | the boss, a checkpoint or an actor walled off from the spawn; two checkpoints the same path distance from the spawn (their order would be the sort's, not a rule); the respawn clearance and the spur rule below |

**The trap this repo has hit four times is the one this file is built
against**: a parser that reads a malformed input as an empty one. Nothing here
is optional and nothing is defaulted; a fault that stops the read says so, and
the test feeds the reader garbage of each kind and asserts the reason.

## The rules that bind anyone authoring a map

All three are this folder's, and all three are now refused by the validator
rather than remembered — or, for the spur rule, warned about.

**Nothing a respawn restores may stand within 4 cells of the cell it puts the
hero on** (issue #54). Per checkpoint, over the placements with `segment >=`
that checkpoint — those are the ones that arrive back at their cells together
with him, on a player who has just lost a fight. Measured straight-line and
horizontally from the checkpoint's nearest cell, which is where he actually
lands; segment distances are path, because they are about what he had to
walk. **Say which metric, every time**: 7 by the flood-fill and 6.08
straight-line describe the same pair of cells, and the pair is unreadable
together, which is half of how #54's overstatement survived being read.

**`scenes/hero/` leans on that number**, so it is a contract and not just good
practice. 4 cells is 16 units, comfortably outside his `acquire_radius` of 9,
and that gap is the only reason he cannot swing on the frame he respawns — his
own timers are cleared to *full readiness*, deliberately. Shrink the clearance
here and the invariant protecting the player is gone with nothing in that
folder to notice; a skill widening `acquire_radius` does the same from the
other end. Guarded from both sides: `acquire_radius` is left out of the stats
`scenes/hero/` accepts from a tree, and `tests/smoke_skills.gd` asserts that a
*fully invested* hero still sees less far than a respawn is cleared for. The
tree is authored in a third folder, `scenes/skills/`, so the edit that would
break this contract is a `.tres` neither this folder nor `scenes/hero/` would
show in its diff. If a radius skill is ever wanted, the clearance here is what
has to move first.

**The boss is bound by the same rule** (issue #39) and the validator checks it
alongside the actors. `tests/smoke_startup.gd` measures the same rule on the
assembled scene, deliberately as a second layer: the validator asserts what an
author wrote, the test asserts what the player gets.

What the narrower rule leaves uncovered is small and worth knowing. A
placement *behind* a checkpoint — one a respawn there does not restore — may
stand closer than 4 cells to it. If the player walked past it on the way in it
is still standing, possibly inside its own detection radius of the pad, so it
can notice a hero who has just come back. He cannot answer first: his
`acquire_radius` is 9. The invariant `scenes/hero/` leans on still holds,
because that is about what he can acquire on the frame he lands, not about
what can walk up to him afterwards.

**A dead-end spur must be shorter than the run from its neck to the next
checkpoint.** Segments are cut by distance, but "behind the checkpoint" is
really a question about *routes*, and the two only agree while nothing hangs
off the route deeper than the next checkpoint is far. The far end of a long
spur scores a distance past the checkpoint, so a placement cleared before the
checkpoint is filed ahead of it and comes back on every respawn there — in a
place the player has already left, for no reason they can see. The validator
floods the grid with the checkpoint's cells treated as rock and refuses any
placement filed behind a checkpoint that is reachable without passing it.
Placements only, not cells: an empty cell filed on the wrong side changes
nothing observable, and the dungeon has eleven of them.

Cells are `CELL_SIZE` = 4 units, matching the KayKit dungeon grid: `wall` is
4×4×1 and `floor_tile_large` is 4×4.

## Single-file movement is a choice per location

It used to be a property of the whole map, and encounter design had to assume
it everywhere. It no longer is, and that is the main thing the open level
means for the rest of the project.

The navmesh bakes at `agent_radius` 1.0 (see the gotcha below), so the walkable
ribbon through a one-cell gap is only ~1 unit wide. Two 0.4-radius agents fit
across it with ~0.2 to spare, but nothing steers them to opposite edges —
`avoidance_enabled` is off by default and no code sets it — so in practice they
queue. That is still true, and it is still not a tuning tweak to change:
passing needs either wider geometry or agent avoidance.

**Put a chokepoint where a queue is the encounter you want; put a clearing
where units should spread out.** Openness costs nothing in the builder: walls
are only raised on the rock/floor boundary, so a 13-wide clearing and a
one-cell corridor run the same code.

**Issue #67 gave the player a way to use that deliberately**, which is worth
knowing because it is the first thing to make a chokepoint a *tactic* rather
than only a shape. `scenes/hero/`'s hold command roots the hero where he stands
and stops him acquiring anything he would have to walk to, so a one-cell throat
can now be held against a pack that has to arrive down it in single file. The
0.2 of slack is why avoidance stays a plausible remedy rather than a hopeless
one, and why this paragraph has to be re-checked if it is ever enabled.

## Checkpoints and segments (issue #38)

`checkpoints()` returns one entry per checkpoint, ordered by path distance from
the spawn; `actor_spawns()` returns each actor with the `segment` it belongs to.
Respawning at checkpoint *k* restores exactly the placements with
`segment >= k` — `scenes/main.gd` does the restoring, this folder only says
which is which.

Three rules make that work, and each is load-bearing:

- **One `checkpoint` entry is one gate**, however many cells it lists. Six
  pads across a six-cell door are one thing to arm, so a gate can span a
  doorway wide enough to walk round. A checkpoint the player can miss costs
  them far more progress than the one they believed they had banked. The cells
  must be one connected run, and two gates may not touch: a pad the player
  crosses in one step that arms two different checkpoints would make the
  respawn point depend on which foot landed first.
- **Segments are cut by path distance from the spawn, not by authored order.**
  Sort the checkpoints by distance, and a placement belongs to the last
  checkpoint at or before its own. Nothing is numbered by hand, so moving a
  gate re-files every placement behind it automatically — which is why two
  gates at the same distance are refused: their order would be the sort's.
- **`checkpoints()[k][0]` is the nearest cell of checkpoint *k*, and that is
  the respawn point.** A cell, never an average of the group — the centre of an
  L-shaped gate can land in solid rock.

The spawn is checkpoint 0 and gets no pad: the hero is standing on it before
he can walk onto anything, and the map already paints it green.

**The boss is filed under a segment too** (`boss_segment()`, issue #39), by the
same rule and the same code path as an actor — the boss is one authored marker
rather than an entry in `actor_spawns()`, so it is the one thing on the map
that would otherwise have nowhere to read its segment from. Without it a death
in the boss room would clear the boss away with the rest of its segment and
have nothing to put one back, which is the difference between a retry and a
run that cannot be finished.

## What gets built

- **Floor** — `floor_tile_large` per open cell, `floor_dirt_large` for the
  spawn and boss cells so they read as distinct places without custom art.
- **Walls** — a `wall` piece on every edge where an open cell meets rock (or
  the outside of the grid). Because only open cells place walls, a shared edge
  between two open cells never gets one and no edge is ever built twice.
- **Rock caps** — see the gotcha below.
- **Zone markers** — flat emissive plates (green spawn, red boss). Plain
  `MeshInstance3D`, no collision. **Those two colours are a constraint on
  everything else drawn on the floor:** `scenes/ui/` picks its selection ring
  colours (cyan and orange) specifically to stay legible on top of them, since
  the hero spawns standing on the green one. Recolouring a marker means
  re-checking that folder — and `checkpoint.gd`, whose violet is the one hue
  left that collides with neither pair. Its pads are the harder case of the
  two, because a marker is somewhere units *stand*: a selection ring is drawn
  on top of a checkpoint pad every time the pad matters.

  **The red marker stopped being the easy case when #39 stood the boss on it.**
  That was the collision the cyan/orange choice was made against, and it holds:
  an orange ring on the red plate is legible. What does not hold is the ring's
  *size* — the boss is as wide as the ring, so what survives is a crescent at
  its feet rather than a circle around it (issue #49).
- Public API: `load_map(path)`, the `map` it loaded (a `MapData`, null while
  nothing valid is), `bounds()`, `start_position()`, `boss_position()`,
  `boss_segment()`, `boss_asset()`, `actor_spawns()`, `checkpoints()`, and the
  `built` signal. `map_path` is an export and defaults to the dungeon; the
  scene loads it in its own `_ready()`, which is what keeps `scenes/main.gd`'s
  startup order true.

**`bounds()` covers every cell, rock included, and the rock caps are the reason
it can.** It is the rectangle `scenes/`'s camera keeps its view inside (issue
#43), so it has to be the region with *something drawn in it* rather than the
region you can walk on — and because every rock cell is capped rather than left
as a hole, those two are the whole grid and the open floor respectively. The
walkable shape would be the wrong answer twice over: it is full of concavities
no camera can track, and honouring it would push the level's own walls off
screen. It is empty until a map has loaded.

**The map never instances actors, and it does not instance checkpoints
either.** It only says where they go and, for actors, what by id;
`scenes/main.gd` reads `actor_spawns()` and `checkpoints()` and decides what
stands there. That keeps the map data and lets those scenes change without
touching it. The pad is the one piece of level furniture that is *not* built
by the builder, and that is the reason: it has behaviour, and behaviour belongs
on the other side of this seam even when the art does not.

Everything with collision is a `StaticBody3D` whose `BoxShape3D` is derived
from the piece's own mesh AABB, so swapping a piece's art keeps its collider
correct. Floors go on layer 1, walls on layer 2 (the table in
`scenes/CLAUDE.md`); level geometry has `collision_mask = 0` since it only
ever gets collided with.

## Cost, measured

The open level is ~6× the old maze in cells, and one `StaticBody3D` per cell
was the standing worry. It was measured on the #37 branch rather than guessed,
and **it does not bite** — so floor collision is deliberately still per-cell,
one box per tile, and no batching was written.

| | old maze | this level |
|---|---|---|
| cells / open cells | 270 / 120 | 1672 / 620 |
| nodes under `LevelMap` | 1 501 | 5 683 |
| navmesh bake (synchronous, at startup) | ~12 ms | ~55 ms |
| frame time, v-sync off | 2.7 ms | 3.8–4.4 ms |
| draw calls | ~75 | ~105 |

Draw calls barely move because the same few pieces repeat and Godot batches
them. **Revisit batching if the bake approaches a noticeable hitch** — it is a
synchronous startup cost and the web export cannot thread it. Floors only need
a collider for the click ray and the navmesh, so they could become one box per
contiguous run of open cells without changing what the player sees.

**Reading and checking the map costs ~4.5 ms at startup**, measured on #73:
0.1 ms of that is the JSON, the rest is three flood-fills over 620 cells in
GDScript at ~1.5 ms each. The old builder ran the same three floods and paid
the same, so this is a first measurement rather than a regression — and the
obvious fixes (an indexed queue instead of `pop_front()`, no per-cell `String`)
were tried and bought 15%, because the cost is interpreter overhead per
neighbour visit, not any one operation. Not worth chasing further beside a
55 ms bake.

## Gotchas

- **Collision is mandatory, not decoration.** The `NavigationMesh` parses
  static colliders only, so anything without a collider is invisible to
  pathfinding — and anything *with* one becomes navigation input.
- **Rock caps are deliberately collision-free.** Wall pieces only sit on the
  rock/floor boundary, so the middle of every rock cell is an open hole you can
  see the void through from the camera angle. `_add_rock_cap` closes each one
  with a floor tile flush with the top of the walls, tinted dark so rock never
  competes with the lit walkable floor for the player's eye. Giving those caps
  collision would bake navmesh islands *inside* solid rock — and since
  every `Hero` order clamps its destination onto the nearest navmesh point,
  clicking a wall could then order the hero somewhere he can never reach.
- **`agent_radius` on the navmesh is 1.0, not the hero's 0.4.** At 0.5 the
  baked surface hugged the walls, so waypoints landed in the pockets where two
  wall pieces meet at a corner; the hero drove into one, wedged against both
  faces, and `move_and_slide()` returned zero velocity — a dead stop a few
  metres from spawn. Widening it keeps waypoints down the corridor centreline.
  Keep it a multiple of the navmesh `cell_size` (0.25) or Godot warns that the
  value is ceiled to voxel units.
- **A checkpoint's trigger is an `Area3D`, and that is what keeps it out of the
  navmesh.** The bake parses static colliders only, so an `Area3D` is invisible
  to it — where a `StaticBody3D` would bake a hole in the walkable surface at
  every checkpoint. This is the mirror of the rock-cap trap above: there,
  collision had to be withheld from something visible; here, a trigger has to
  sense without being solid. Both come out of the same rule.
- **The validator's flood-fill proves the map connects, not that the level is
  walkable.** It runs on the *grid*, so a walled-off boss or checkpoint is
  refused before anything is built — but it knows nothing about the navmesh,
  and a one-cell chokepoint is exactly where erosion could sever the baked
  surface while the grid still connects. `tests/smoke_traversal.gd` walks the
  hero to `boss_position()` on every run, which is the only check that covers
  it. It is also what segments are cut by, so one BFS answers both questions
  and they cannot disagree.
- **`--check-only` cannot see a new `class_name` until `--import` has run.**
  It reads the global class cache, and a script added on a branch is not in it
  until the project is re-imported — `map_data.gd` reported `MapData` itself as
  an unknown identifier on its first check. Not a fault in the script; the
  same reason `tests/` loads that script by path rather than naming it.

## Dependencies

- Art: `assets/dungeon/` (`wall`, `floor_tile_large`, `floor_dirt_large`).
  `checkpoint.gd` uses none — its pads are `BoxMesh`es, like the zone markers.
- Content: `maps/`, where the files this folder reads live and whose doc says
  what each map is like. `LevelMap` reads `res://maps/dungeon.json` by default.
- Instanced by `scenes/main.tscn` under `NavigationRegion3D`; `scenes/main.gd`
  reads `start_position()` to place the hero, bakes the navmesh, and then reads
  `checkpoints()`, `actor_spawns()` and the `boss_position()` /
  `boss_segment()` / `boss_asset()` triple to lay the pads and populate the map
  with `scenes/enemies/`, resolving each `asset` id through its own table. The
  ordering is load-bearing — `LevelMap._ready()` runs before `Main._ready()`
  because Godot readies children first, so the geometry exists before the
  bake.
- `Checkpoint` emits `reached(index)` and takes `set_armed(bool)` back;
  `scenes/main.gd` owns which one is armed, because only one can be and a node
  deciding that for itself would have to hear about every other one. The pad
  masks physics layer 3 and tests the `hero` group — a runtime contract on
  `scenes/hero/`, which is why it is in the frontmatter above. `Checkpoint`
  never names `Hero` as a type.
- `tests/smoke_map.gd` validates every shipped map and holds the validator to
  a broken one per rule; `tests/smoke_startup.gd` measures the clearance rule
  on the assembled scene.

<!-- verified-against: 67cb196 -->
