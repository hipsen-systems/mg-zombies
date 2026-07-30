---
depends-on: [scenes/map, scenes/hero, scenes/enemies]
---

# scenes/

Top-level game scenes and their scripts.

- `main.tscn` — the game entry scene: a `NavigationRegion3D` wrapping the
  maze (`scenes/map/`), the instanced hero, an `Enemies` holder, lighting, the
  RTS camera, and the `HUD` `CanvasLayer`. The 40×40 test arena that lived here
  for issue #5 is gone; issue #6 replaced it with the real map.
- `main.gd` — attached to the root. Owns the startup order, which is
  load-bearing:
  1. the maze builds itself in its own `_ready()` (Godot readies children
     first);
  2. this script places the hero on the maze's start cell and snaps the camera;
  3. it bakes the navmesh over the geometry that now exists — synchronous
     (`bake_navigation_mesh(false)`) because the web export has threads
     disabled, so don't switch it to on-thread baking;
  4. **then** it spawns one zombie per `Z` cell of the maze. Enemies path on
     the navmesh, so they must not exist before the bake.
- **Enemy spawning** sets `position` *before* `add_child`, because
  `Zombie._ready()` captures `global_position` as the home its roam area and
  leash are measured from. `Enemies` sits at the origin so local and global
  agree.

## HUD

A deliberately minimal `CanvasLayer` in `main.tscn`, driven by a handful of
lines in `main.gd` rather than its own scene — issue #7 needed the hero's HP to
be *visible* to be testable at all, and issue #11 needed the armed-attack state
to be visible for the same reason.

- `HUD/HealthBar` (`ProgressBar`, bottom-left) with a `Value` `Label` child
  showing `current / max`, fed by `Hero.health`'s `health_changed`.
- `HUD/DeathLabel` — hidden until the hero dies.
- `HUD/AttackMoveLabel` — shown while the attack command is armed (`A`
  pressed, waiting for the click). A mode the player cannot see is a mode they
  will forget they are in. Driven by `Hero.attack_move_armed_changed`.
- `HUD/ControlsLabel` — static one-liner naming the two commands, bottom-right.
  The web build is the project's front door and arrives with no instructions.

**This has now outgrown living here**, which is what issue #36 addresses: it
adds a unit info bar and creates `scenes/ui/` to hold all of it. Add UI there,
not here.

## Death and restart

`main.gd` listens for `Hero.died`, shows the death label, waits
`RESTART_DELAY` (2.5 s) and calls `get_tree().reload_current_scene()`. Crude on
purpose — issue #7 explicitly allows it and a run carries no state worth
preserving yet.

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
- `agent_radius` is 1.0 — much wider than the hero's 0.4 capsule, on purpose.
  See `scenes/map/CLAUDE.md`: a tight radius puts waypoints in the corner
  pockets where two wall pieces meet and the hero wedges there. Keep it a
  multiple of `cell_size` (0.25) or Godot warns about voxel rounding.

## Camera

- `rts_camera.gd` (`class_name RTSCamera`) — fixed-angle follow camera on the
  `RTSCamera` `Camera3D`. The angle is authored by *placing the node* relative
  to its exported `target` (the hero); the script captures that offset in
  `_ready()`, aims once with `look_at()`, and afterwards only translates with
  exponential smoothing. It never rotates at runtime.
- `snap_to_target()` moves **and re-aims**. `main.gd` teleports the hero to the
  maze start after the camera's `_ready()` has already run, so without the
  re-aim the camera keeps pointing at wherever the hero sat in the .tscn.
- The offset is `(0, 22.1, 14)` → a ~57° pitch. The old `(0, 16, 24)` (~33°)
  was authored for the small arena; on the 60×72 maze that shallow angle showed
  the map from the outside rather than the hero's corridor.

## Physics layers (project convention, established here)

Named in `project.godot` under `[layer_names]`, so the editor's collision
inspector reads properly.

| Layer | Used for | Who is on it | Who masks it |
|-------|----------|--------------|--------------|
| 1     | Ground/floor (click-to-move rays collide with this only) | floor tiles | hero, zombies |
| 2     | Walls & static obstacles (also what the zombie line-of-sight ray tests) | wall pieces | hero, zombies |
| 3     | Hero | hero | zombies |
| 4     | Enemies | zombies | *nobody* |

The asymmetry in the last two rows is intentional: zombies are blocked by the
hero, the hero is not blocked by zombies, and zombies do not collide with each
other. Mutually-colliding zombies jam solid in a one-cell corridor, and a hero
who can be body-blocked wedges exactly the way `scenes/map/CLAUDE.md`
describes. See `scenes/enemies/CLAUDE.md`.

## Dependencies / signals

- Instances `scenes/map/maze.tscn` and `scenes/hero/hero.tscn` from the .tscn,
  and `scenes/enemies/zombie.tscn` at runtime; the camera's `target` export
  points at the hero.
- **Input actions** are defined in `project.godot` and every one of them is
  consumed by `scenes/hero/`, not by anything in this folder. What each *means*
  is that folder's to document; this is only the inventory:
  `move_command` (right mouse), `select_command` (left mouse),
  `attack_move` (`A`), `cancel_command` (`Escape`).
- `Maze` emits `built`; nothing consumes it yet.
- `main.gd` consumes `Hero.died`, `Hero.health.health_changed` and
  `Hero.attack_move_armed_changed`. Unconsumed so far: `Hero.move_ordered` and
  `Hero.attack_ordered` (for the selection UI, issue #36), and both death
  signals — `Zombie.died` and the hero's attributed `Hero.killed`, which are
  the XP hooks for issue #8.

## Tooling note

`--headless --check-only --script` cannot resolve `class_name` types across
files (it doesn't load the global class cache), so it reports a false
"Could not find type" on scripts that reference `Hero`, `Maze`, or
`RTSCamera`. Run the scene instead to check those.

<!-- verified-against: 8a4044b -->
