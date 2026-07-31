---
depends-on: [scenes, scenes/hero, assets]
---

# scenes/map/

The playable map (issues #6, #37) and the checkpoints laid out on it (#38).
Replaces the 40×40 test arena that `main.tscn` used to carry.

- `level_map.tscn` — a bare `Node3D` with `level_map.gd`. All geometry is
  generated at runtime, so the .tscn stays a single node.
- `level_map.gd` (`class_name LevelMap`) — builds the map from ASCII.
- `checkpoint.tscn` / `checkpoint.gd` (`class_name Checkpoint`) — one respawn
  pad, built the same way: a bare `Node3D` that generates its plates and
  triggers at runtime. Instanced by `scenes/main.gd`, not by the builder.

Issue #37 renamed both away from `maze`: the layout is deliberately not a maze
any more, and a class called `Maze` that builds a non-maze is the kind of thing
this project treats as a blocking review finding.

## Authoring a map

The map is the `layout` export: one character per cell, north is row 0.

| Char | Meaning |
|------|---------|
| `#`  | solid rock |
| `.`  | open floor |
| `S`  | start cell (hero spawns here) — exactly one |
| `B`  | boss room centre — exactly one |
| `Z`  | ordinary floor that also marks a zombie spawn — any number |
| `C`  | ordinary floor that also marks a respawn checkpoint — any number |

Rows must all be the same length. `build()` refuses to build a malformed
layout and `push_error`s instead of half-building one.

Encounters are authored the same way the map is: placing an enemy is editing
one character.

**Keep `Z` cells well clear of every cell the hero can start on** — a zombie
within its own detection radius (12 units = 3 cells) charges him before the
player has taken a step. That used to mean `S` alone; since #38 it means every
`C` cell too, and it binds harder there: respawning restores the zombies ahead
of the checkpoint *to their spawns*, so a spawn too close arrives with the hero,
every time, on a player who has just lost a fight. Both checkpoints on the
current map were moved to earn that clearance, and the boss-room guard was moved
four cells deeper into its room for the same reason. Nothing is now within 4
cells of a respawn cell; the nearest to `S` is 7.

Cells are `CELL_SIZE` = 4 units, matching the KayKit dungeon grid: `wall` is
4×4×1 and `floor_tile_large` is 4×4.

## The shape of the current level

44 × 38 cells, 620 of them open. One route runs from `S` (bottom left) to `B`
(top right) and back is the only way out of anywhere else: **every** path from
start to boss passes through both chokepoints, and there is no loop.

- **Two clearings** 10–13 cells across, joined by a passage 3 cells thick.
- **Two one-cell chokepoints** — a throat out of the start clearing, and a
  tunnel between the clearings that is one cell *tall* and three long. (This
  said five until #38 counted it: the cells at either mouth are single-cell
  *cuts*, so every route still crosses all five, but they have open floor above
  and below them and are not part of the enclosed tunnel.)
- **A two-cell door** into the boss arena. Narrow enough to read as a gate,
  wide enough that two units are not forced to queue.
- **Two dead-end spurs** — a chamber north of the first clearing (21 cells) and
  a vault south of the second (24 cells), each holding two zombies. Both hang
  off a two-cell neck, so neither shows up as a single-cell cut.
- **Two checkpoints** past the implicit one on `S`: the three enclosed tunnel
  cells (24 from the start) and a six-cell gate across the boss-room threshold
  (46). Between them the run splits 7 / 9 / 3 zombies. See below for why those
  two and not the obvious third.

**Openness costs nothing in the builder.** Walls are only raised on the
rock/floor boundary, so a 13-wide clearing and a one-cell corridor run the same
code — which is why #37 changed only the layout string.

## Single-file movement is now a choice per location

It used to be a property of the whole map, and encounter design had to assume
it everywhere. It no longer is, and that is the main thing this folder's change
means for the rest of the project.

The navmesh bakes at `agent_radius` 1.0 (see the gotcha below), so the walkable
ribbon through a one-cell gap is only ~1 unit wide. Two 0.4-radius agents fit
across it with ~0.2 to spare, but nothing steers them to opposite edges —
`avoidance_enabled` is off by default and no code sets it — so in practice they
queue. That is still true, and it is still not a tuning tweak to change:
passing needs either wider geometry or agent avoidance.

What changed is where it applies. **Put a chokepoint where a queue is the
encounter you want; put a clearing where units should spread out.** A design
that needs units to pass now has somewhere to do it. The 0.2 of slack is why
avoidance stays a plausible remedy rather than a hopeless one, and why this
paragraph has to be re-checked if it is ever enabled.

## Checkpoints and segments (issue #38)

`checkpoints()` returns one entry per checkpoint, ordered by path distance from
the start; `zombie_spawns()` returns each spawn with the `segment` it belongs
to. Respawning at checkpoint *k* restores exactly the spawns with `segment >= k`
— `scenes/main.gd` does the restoring, this folder only says which is which.

Three rules make that work, and each is load-bearing:

- **A run of adjacent `C` cells is one checkpoint.** Six pads across a six-cell
  door are one thing to arm, so a gate can span a doorway wide enough to walk
  round. A checkpoint the player can miss costs them far more progress than the
  one they believed they had banked.
- **Segments are cut by BFS distance from `S`, not by authored order.** Sort the
  checkpoints by distance, and a spawn belongs to the last checkpoint at or
  before its own. Nothing is numbered by hand, so moving a `C` re-files every
  spawn behind it automatically.
- **`checkpoints()[k][0]` is the nearest cell of checkpoint *k*, and that is the
  respawn point.** A cell, never an average of the group — the centre of an
  L-shaped gate can land in solid rock.

`S` is checkpoint 0 and gets no pad: the hero is standing on it before he can
walk onto anything, and the map already paints it green.

### The authoring constraint, and the one place it bit

**A dead-end spur must be shorter than the run from its neck to the next
checkpoint.** Segments are cut by distance, but "behind the checkpoint" is
really a question about *routes*, and the two only agree while nothing hangs off
the route deeper than the next checkpoint is far. The far end of a long spur
scores a distance past the checkpoint, so a spawn cleared before the checkpoint
is filed ahead of it and comes back on every respawn there — in a place the
player has already left, for no reason they can see.

`_warn_about_split_segments()` checks this at build time and `push_warning`s the
offending cell, so it is a fact about the layout rather than a rule to remember.
It checks *spawns* only: an empty cell filed on the wrong side changes nothing
observable, and the current level has eleven of them in the deep corners of the
south vault. Warning about those would train everyone to ignore it.

This is why the second checkpoint is the boss-room threshold and **not** the
two-cell door one row below it, which is the spot that looks right. The south
vault runs to distance 47; the door is at 44, the threshold at 46. At the door,
the vault's far zombie files into the wrong segment. Moving the checkpoint two
rows on is the whole fix, and it costs nothing — no spawn sits between 45 and
47, so the split is identical either way.

## What gets built

- **Floor** — `floor_tile_large` per open cell, `floor_dirt_large` for the
  start and boss cells so they read as distinct places without custom art.
- **Walls** — a `wall` piece on every edge where an open cell meets rock (or
  the outside of the grid). Because only open cells place walls, a shared edge
  between two open cells never gets one and no edge is ever built twice.
- **Rock caps** — see the gotcha below.
- **Zone markers** — flat emissive plates (green start, red boss). Plain
  `MeshInstance3D`, no collision. **Those two colours are a constraint on
  everything else drawn on the floor:** `scenes/ui/` picks its selection ring
  colours (cyan and orange) specifically to stay legible on top of them, since
  the hero spawns standing on the green one. Recolouring a marker means
  re-checking that folder — and now `checkpoint.gd`, whose violet is the one hue
  left that collides with neither pair. Its pads are the harder case of the two,
  because a marker is somewhere units *stand*: a selection ring is drawn on top
  of a checkpoint pad every time the pad matters.
- Public API: `start_position()`, `boss_position()`, `zombie_spawns()`,
  `checkpoints()`, and the `built` signal.

**The map never instances enemies, and it does not instance checkpoints
either.** It only says where they go; `scenes/main.gd` reads `zombie_spawns()`
and `checkpoints()` and decides what stands there. That keeps the map pure
geometry and lets those scenes change without touching it. The pad is the one
piece of level furniture that is *not* built by the builder, and that is the
reason: it has behaviour, and behaviour belongs on the other side of this seam
even when the art does not.

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
- **The distance flood-fill proves the layout connects, not that the level is
  walkable.** It runs on the *grid* after every build and `push_error`s if the
  boss is walled off (or a checkpoint is), so a bad map edit fails loudly
  instead of being discovered by walking there. It is also what segments are cut
  by, so one BFS answers both questions and they cannot disagree. But it knows
  nothing about the navmesh, and a
  one-cell chokepoint is exactly where erosion could sever the baked surface
  while the grid still connects. After editing chokepoints, order the hero to
  `boss_position()` and confirm he arrives — that is the only check that covers
  it. On the current layout he walks start to boss in ~29 s.

## Dependencies

- Art: `assets/dungeon/` (`wall`, `floor_tile_large`, `floor_dirt_large`).
  `checkpoint.gd` uses none — its pads are `BoxMesh`es, like the zone markers.
- Instanced by `scenes/main.tscn` under `NavigationRegion3D`; `scenes/main.gd`
  reads `start_position()` to place the hero, bakes the navmesh, and then reads
  `checkpoints()` and `zombie_spawns()` to lay the pads and populate the map with
  `scenes/enemies/`. The ordering is load-bearing — `LevelMap._ready()` runs
  before `Main._ready()` because Godot readies children first, so the geometry
  exists before the bake.
- `Checkpoint` emits `reached(index)` and takes `set_armed(bool)` back;
  `scenes/main.gd` owns which one is armed, because only one can be and a node
  deciding that for itself would have to hear about every other one. The pad
  masks physics layer 3 and tests the `hero` group — a runtime contract on
  `scenes/hero/`, which is why it is in the frontmatter above. `Checkpoint`
  never names `Hero` as a type.

<!-- verified-against: a5a431e -->
