# scenes/

Top-level game scenes and their scripts.

- `main.tscn` — the game entry scene (issue #5): a 40×40 walled test arena
  with two offset "choke" walls to exercise pathfinding, a `NavigationRegion3D`
  wrapping all level geometry, the instanced hero, lighting, and the RTS
  camera. The maze proper replaces this arena in issue #6.
- `main.gd` — attached to the root; bakes the navmesh at runtime in
  `_ready()`. The bake is synchronous (`bake_navigation_mesh(false)`) because
  the web export has threads disabled — don't switch it to on-thread baking.
  Baking at runtime means the .tscn never contains stale baked polygons; level
  geometry just needs to live under `NavigationRegion3D`.

## Navmesh gotchas (learned the hard way)

- The `NavigationMesh` parses **static colliders only**
  (`geometry_parsed_geometry_type = 1`) — parsing visual meshes at runtime
  reads geometry back from the GPU, which Godot warns is a serious perf hit.
  New level geometry therefore *must* have collision shapes to be walkable.
- `cell_height` is 0.05 on both the NavigationMesh and
  `navigation/3d/default_cell_height` in `project.godot` (they must match or
  Godot warns). With the default 0.25, the baked surface floats ~0.5 above the
  floor, and `NavigationAgent3D`'s waypoint-advance check (a full 3D distance
  against `path_desired_distance`) never triggers — the hero stalls at the
  first waypoint, jittering in place.
- `rts_camera.gd` — fixed-angle follow camera on the `RTSCamera` Camera3D
  node. The camera angle is authored by *placing the node* relative to its
  exported `target` (the hero); the script captures that offset in `_ready()`,
  aims once with `look_at()`, and afterwards only translates with exponential
  smoothing. It never rotates at runtime.

## Physics layers (project convention, established here)

| Layer | Used for |
|-------|----------|
| 1     | Ground/floor (click-to-move rays collide with this only) |
| 2     | Walls & static obstacles |
| 3     | Hero |

## Dependencies / signals

- Instances `scenes/hero/hero.tscn`; the camera's `target` export points at it.
- Input action `move_command` (right mouse button) is defined in
  `project.godot` and consumed by the hero, not by anything in this folder.
- No signals emitted or consumed yet.
