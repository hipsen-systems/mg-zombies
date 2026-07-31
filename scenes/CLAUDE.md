---
depends-on: [scenes/map, scenes/hero, scenes/enemies, scenes/ui]
---

# scenes/

Top-level game scenes and their scripts.

- `main.tscn` — the game entry scene: a `NavigationRegion3D` wrapping the
  level map (`scenes/map/`), the instanced hero, `Enemies` and `Checkpoints`
  holders, lighting, the RTS camera, and two instances from `scenes/ui/` — the
  `HUD` and the `UnitSelection` node that holds the selection ring. The 40×40
  test arena that lived here for issue #5 is gone; issue #6 replaced it with the
  real map, and issue #37 replaced that maze with an open single-path level.
- `main.gd` — attached to the root. Owns the startup order, which is
  load-bearing:
  1. the map builds itself in its own `_ready()` (Godot readies children
     first);
  2. this script places the hero on the map's start cell and snaps the camera;
  3. it bakes the navmesh over the geometry that now exists — synchronous
     (`bake_navigation_mesh(false)`) because the web export has threads
     disabled, so don't switch it to on-thread baking. On the open level this
     costs ~55 ms at startup, up from ~12 ms on the maze;
  4. **then** it lays the checkpoint pads and spawns one zombie per `Z` cell of
     the map. Enemies path on the navmesh, so they must not exist before the
     bake.
- **Enemy spawning** sets `position` *before* `add_child`, because
  `Zombie._ready()` captures `global_position` as the home its roam area and
  leash are measured from. `Enemies` sits at the origin so local and global
  agree. `Checkpoint.setup()` has the same rule for the same reason: it builds
  its pads and triggers in `_ready()` and has nothing to build them from until
  it has been told its cells.

## HUD and selection

**Both live in `scenes/ui/` now** (issue #36). They were inline here while the
HUD was a handful of Labels driven by a handful of lines in `main.gd`; the unit
info bar was the element that made that untenable.

What is left here is the wiring, and only the wiring: `main.gd` connects the
hero's `health_changed`, `attack_move_armed_changed`, `died` and
`select_clicked` to methods on the two `scenes/ui/` nodes, and connects
`UnitSelection.selection_changed` to the `HUD`. It never touches a Label. Add UI
there, not here, and keep it reachable by method rather than by node path.

One ordering rule lives in `_ready()`: `selection_changed` is connected
**before** `select_unit(_hero)` is called, because the info bar learns the
initial selection from that signal and nothing re-sends it.

## Death and respawn (issue #38)

`main.gd` listens for `Hero.died`, shows the death screen, waits
`RESPAWN_DELAY` (2.5 s) and puts him back at the armed checkpoint. The scene
reload issue #7 allowed is gone: a run now carries state worth preserving, which
is the whole point of the feature.

**This script owns the respawn rule**, because it is the only thing here that
knows both the armed checkpoint and what is currently standing in the level.
`scenes/map/` says where the checkpoints are and which segment each spawn
belongs to; deciding what a death costs is this folder's.

- **Only the segment ahead of the armed checkpoint is restored.** Everything
  cleared behind it stays cleared, so a death costs the fight and not the run;
  everything ahead comes back, so a hard fight cannot be whittled down by dying
  at it repeatedly.
- **Clear first, then spawn.** Restoring a segment means putting it back *as
  authored*, which is not the same as topping up the survivors — a zombie left
  mid-chase would otherwise stay standing where it ran the hero down, beside a
  fresh copy of every one that died. Removing and re-instancing is also what
  makes "restored zombies are home in ROAM" true for free, rather than needing a
  reset method on the enemy.
- **`remove_child` before `queue_free`**, so a cleared zombie leaves the
  `enemies` group this frame rather than at the end of it. The hero can acquire
  and walk toward a queued-but-still-parented target on the tick between.
- **Each zombie carries its segment as node metadata** (`SEGMENT_META`). A list
  kept here would be a second record of a set the scene tree already holds, and
  zombies remove themselves from it when a corpse finishes fading.
- **The most recently armed checkpoint wins, not the furthest reached.** Walking
  back through an earlier pad really does hand back the ground in between — the
  lit pad is always the promise being made, which is the version a player can
  read off the screen.
- The camera is snapped after the teleport, for the same reason `_ready()` snaps
  after placing the hero, and the info bar is pointed back at him *before* the
  clear: it has no way to notice a unit that is removed rather than killed.

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
  map's start cell after the camera's `_ready()` has already run, so without the
  re-aim the camera keeps pointing at wherever the hero sat in the .tscn.
- The offset is `(0, 22.1, 14)` → a ~57° pitch. The old `(0, 16, 24)` (~33°)
  was authored for the small arena; on the 60×72 maze that shallow angle showed
  the map from the outside rather than the hero's surroundings. The level is now
  176×152, which does not change the offset but does make issue #43 (the camera
  has no level bounds, so the view runs off the edge at spawn) more visible.

## Physics layers (project convention, established here)

Named in `project.godot` under `[layer_names]`, so the editor's collision
inspector reads properly.

| Layer | Used for | Who is on it | Who masks it |
|-------|----------|--------------|--------------|
| 1     | Ground/floor (ground-click rays collide with this only) | floor tiles | hero, zombies |
| 2     | Walls & static obstacles (also tested by both line-of-sight rays, by the hero's attack-targeting click, and by the selection click, so none of them sees through rock) | wall pieces | hero, zombies |
| 3     | Hero (also what the selection ray tests, and what the checkpoint pads' `Area3D`s detect) | hero | zombies |
| 4     | Enemies (also what the hero's attack-targeting ray and the selection ray test) | zombies | *nobody* |

**"Who masks it" is about bodies, not queries.** A `collision_mask` decides what
a body is stopped by; a ray query carries its own mask and is stopped by
nothing. Every layer now has a ray consumer, and three of the four have no body
masking them for that purpose, so the two columns answer different questions —
read `nobody` in the last row as "nothing is *blocked* by enemies", which is
what the paragraph below depends on. Ray consumers belong in the "Used for"
column, and adding one is a change to this table even though no mask moved. That
distinction is what a cross-review of PR #41 caught: the hero gained an
attack-targeting ray against layer 4 while this row still read as though nothing
touched it. Issue #36 added the third such consumer — `scenes/ui/`'s selection
ray, which is the first thing of any kind to query layer 3.

**An `Area3D`'s mask is a third kind of consumer**, and it goes in the same
column for the same reason. Issue #38's checkpoint pads mask layer 3, but an
area is not blocked by what it masks and does not block it either — it only
*notices*. So the hero is not stopped by a pad, and nothing about his own mask
changed. Three questions now, one column each: what stops a body, what a ray
finds, what an area notices.

The asymmetry in the last two rows is intentional: zombies are blocked by the
hero, the hero is not blocked by zombies, and zombies do not collide with each
other. Mutually-colliding zombies jam solid in a one-cell corridor, and a hero
who can be body-blocked wedges exactly the way `scenes/map/CLAUDE.md`
describes. See `scenes/enemies/CLAUDE.md`.

## Dependencies / signals

- Instances `scenes/map/level_map.tscn`, `scenes/hero/hero.tscn`,
  `scenes/ui/hud.tscn` and `scenes/ui/unit_selection.tscn` from the .tscn, and
  `scenes/enemies/zombie.tscn` and `scenes/map/checkpoint.tscn` at runtime. Two
  exports are wired here as `NodePath`s and both point at the hero: the camera's
  `target` and `UnitSelection.hero`.
- **Input actions** are defined in `project.godot` and every one of them is
  consumed by `scenes/hero/`, not by anything in this folder. What each *means*
  is that folder's to document; this is only the inventory:
  `move_command` (right mouse), `select_command` (left mouse),
  `attack_move` (`A`), `cancel_command` (`Escape`).
- `LevelMap` emits `built`; nothing consumes it yet.
- `main.gd` consumes `Checkpoint.reached` and calls `Checkpoint.set_armed()`
  back on every pad, so exactly one is lit. It calls `Hero.respawn_at()` and, on
  the way, `HUD.show_death()` / `hide_death()` / `flash_checkpoint()`.
- `main.gd` consumes `Hero.died`, `Hero.health.health_changed`,
  `Hero.attack_move_armed_changed` and `Hero.select_clicked`, forwarding each to
  `scenes/ui/`. Unconsumed so far: `Hero.move_ordered` and `Hero.attack_ordered`
  — this doc used to earmark them "for the selection UI, issue #36", and that
  turned out to be wrong: selection is deliberately inert and reads nothing
  about what the hero is doing. They now have no planned consumer. Also
  unconsumed are both death signals, `Zombie.died` and the hero's attributed
  `Hero.killed`, which are the XP hooks for issue #8.

## Tooling note

`--headless --check-only --script` cannot resolve `class_name` types across
files (it doesn't load the global class cache), so it reports a false
"Could not find type" on scripts that reference `Hero`, `LevelMap`, or
`RTSCamera`. Run the scene instead to check those.

<!-- verified-against: 35ada3a -->
