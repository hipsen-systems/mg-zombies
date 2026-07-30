---
depends-on: [scenes, assets]
---

# scenes/map/

The playable map (issues #6, #37). Replaces the 40×40 test arena that
`main.tscn` used to carry.

- `level_map.tscn` — a bare `Node3D` with `level_map.gd`. All geometry is
  generated at runtime, so the .tscn stays a single node.
- `level_map.gd` (`class_name LevelMap`) — builds the map from ASCII.

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

Rows must all be the same length. `build()` refuses to build a malformed
layout and `push_error`s instead of half-building one.

Encounters are authored the same way the map is: placing an enemy is editing
one character. Keep `Z` cells well clear of `S` — a zombie within its own
detection radius (12 units = 3 cells) of the start charges the hero before the
player has taken a step. The nearest one on the current map is 7 cells away.

Cells are `CELL_SIZE` = 4 units, matching the KayKit dungeon grid: `wall` is
4×4×1 and `floor_tile_large` is 4×4.

## The shape of the current level

44 × 38 cells, 620 of them open. One route runs from `S` (bottom left) to `B`
(top right) and back is the only way out of anywhere else: **every** path from
start to boss passes through both chokepoints, and there is no loop.

- **Two clearings** 10–13 cells across, joined by a passage 3 cells thick.
- **Two one-cell chokepoints** — a throat out of the start clearing, and a
  tunnel between the clearings that is one cell *tall* and five long.
- **A two-cell door** into the boss arena. Narrow enough to read as a gate,
  wide enough that two units are not forced to queue.
- **Two dead-end spurs** — a chamber north of the first clearing (21 cells) and
  a vault south of the second (24 cells), each holding two zombies. Both hang
  off a two-cell neck, so neither shows up as a single-cell cut.

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

## What gets built

- **Floor** — `floor_tile_large` per open cell, `floor_dirt_large` for the
  start and boss cells so they read as distinct places without custom art.
- **Walls** — a `wall` piece on every edge where an open cell meets rock (or
  the outside of the grid). Because only open cells place walls, a shared edge
  between two open cells never gets one and no edge is ever built twice.
- **Rock caps** — see the gotcha below.
- **Zone markers** — flat emissive plates (green start, red boss). Plain
  `MeshInstance3D`, no collision.
- Public API: `start_position()`, `boss_position()`,
  `zombie_spawn_positions()`, and the `built` signal.

**The map never instances enemies.** It only says where an encounter is;
`scenes/main.gd` reads `zombie_spawn_positions()` and decides what stands
there. That keeps the map pure geometry and lets enemy scenes change without
touching it.

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
- **`_boss_is_reachable()` proves the layout connects, not that the level is
  walkable.** It flood-fills the *grid* after every build and `push_error`s if
  the boss is walled off, so a bad map edit fails loudly instead of being
  discovered by walking there. But it knows nothing about the navmesh, and a
  one-cell chokepoint is exactly where erosion could sever the baked surface
  while the grid still connects. After editing chokepoints, order the hero to
  `boss_position()` and confirm he arrives — that is the only check that covers
  it. On the current layout he walks start to boss in ~29 s.

## Dependencies

- Art: `assets/dungeon/` (`wall`, `floor_tile_large`, `floor_dirt_large`).
- Instanced by `scenes/main.tscn` under `NavigationRegion3D`; `scenes/main.gd`
  reads `start_position()` to place the hero, bakes the navmesh, and then reads
  `zombie_spawn_positions()` to populate the map with `scenes/enemies/`. The
  ordering is load-bearing — `LevelMap._ready()` runs before `Main._ready()`
  because Godot readies children first, so the geometry exists before the bake.

<!-- verified-against: fe31cbd -->
