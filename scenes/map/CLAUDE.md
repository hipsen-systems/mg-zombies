# scenes/map/

The playable map (issue #6). Replaces the 40×40 test arena that `main.tscn`
used to carry.

- `maze.tscn` — a bare `Node3D` with `maze.gd`. All geometry is generated at
  runtime, so the .tscn stays a single node.
- `maze.gd` (`class_name Maze`) — builds the map from ASCII.

## Authoring a map

The map is the `layout` export: one character per cell, north is row 0.

| Char | Meaning |
|------|---------|
| `#`  | solid rock |
| `.`  | corridor / room floor |
| `S`  | start cell (hero spawns here) — exactly one |
| `B`  | boss room centre — exactly one |

Rows must all be the same length. `build()` refuses to build a malformed
layout and `push_error`s instead of half-building one.

Cells are `CELL_SIZE` = 4 units, matching the KayKit dungeon grid: `wall` is
4×4×1 and `floor_tile_large` is 4×4. Corridors are one cell wide, which leaves
~3 units clear once the wall pieces straddle the cell edges.

## What gets built

- **Floor** — `floor_tile_large` per open cell, `floor_dirt_large` for the
  start and boss cells so they read as distinct places without custom art.
- **Walls** — a `wall` piece on every edge where an open cell meets rock (or
  the outside of the grid). Because only open cells place walls, a shared edge
  between two open cells never gets one and no edge is ever built twice.
- **Rock caps** — see the gotcha below.
- **Zone markers** — flat emissive plates (green start, red boss). Plain
  `MeshInstance3D`, no collision.
- Public API: `start_position()`, `boss_position()`, and the `built` signal.

Everything with collision is a `StaticBody3D` whose `BoxShape3D` is derived
from the piece's own mesh AABB, so swapping a piece's art keeps its collider
correct. Floors go on layer 1, walls on layer 2 (the table in
`scenes/CLAUDE.md`); level geometry has `collision_mask = 0` since it only
ever gets collided with.

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
  `Hero.command_move_to()` clamps a click onto the nearest navmesh point,
  clicking a wall could then order the hero somewhere he can never reach.
- **`agent_radius` on the navmesh is 1.0, not the hero's 0.4.** At 0.5 the
  baked surface hugged the walls, so waypoints landed in the pockets where two
  wall pieces meet at a corner; the hero drove into one, wedged against both
  faces, and `move_and_slide()` returned zero velocity — a dead stop a few
  metres from spawn. Widening it keeps waypoints down the corridor centreline.
  Keep it a multiple of the navmesh `cell_size` (0.25) or Godot warns that the
  value is ceiled to voxel units.
- `_boss_is_reachable()` flood-fills the grid after every build and
  `push_error`s if the boss is walled off, so a bad map edit fails loudly
  instead of being discovered by walking there.

## Dependencies

- Art: `assets/dungeon/` (`wall`, `floor_tile_large`, `floor_dirt_large`).
- Instanced by `scenes/main.tscn` under `NavigationRegion3D`; `scenes/main.gd`
  reads `start_position()` to place the hero and then bakes the navmesh. The
  ordering is load-bearing — `Maze._ready()` runs before `Main._ready()`
  because Godot readies children first, so the geometry exists before the bake.
