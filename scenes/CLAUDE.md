---
depends-on: [scenes/map, scenes/hero, scenes/enemies, scenes/ui, scenes/components]
---

# scenes/

Top-level game scenes and their scripts.

- `main.tscn` — the game entry scene: a `NavigationRegion3D` wrapping the
  level map (`scenes/map/`), the instanced hero, `Enemies` and `Checkpoints`
  holders, lighting, the RTS camera, and three instances from `scenes/ui/` — the
  `HUD`, the `UnitSelection` node that holds the selection ring, and the
  `OrderMarker` that pings where an order landed (issue #67). The 40×40
  test arena that lived here for issue #5 is gone; issue #6 replaced it with the
  real map, and issue #37 replaced that maze with an open single-path level.
- `main.gd` — attached to the root. Owns the startup order, which is
  load-bearing:
  1. the map builds itself in its own `_ready()` (Godot readies children
     first);
  2. this script places the hero on the map's start cell, hands the camera the
     map's bounds, and snaps it — in that order, because the snap is the frame
     the player opens on and an unbounded one opens on void (issue #43);
  3. it bakes the navmesh over the geometry that now exists — synchronous
     (`bake_navigation_mesh(false)`) because the web export has threads
     disabled, so don't switch it to on-thread baking. On the open level this
     costs ~55 ms at startup, up from ~12 ms on the maze;
  4. **then** it lays the checkpoint pads, spawns one zombie per `Z` cell of
     the map, and puts the boss on the `B` cell. Enemies path on the navmesh, so
     they must not exist before the bake.
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

**One wire runs the other way**: `HUD.restart_requested` into `_restart_run()`.
The victory screen asks, this script decides — a widget must not be the thing
that knows what starting a run means.

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

## Winning, and starting again (issue #39)

The boss is the only enemy whose `died` anything listens to, and `main.gd` is
where the listening happens: this folder already owns what a death costs, so it
owns what a kill is worth beside it. The screen itself belongs to `scenes/ui/`;
what winning *means* belongs here.

- **The boss is spawned like a zombie and restored like one.** It comes from
  `LevelMap.boss_position()` / `boss_segment()` rather than the spawn list,
  because it is one authored instance — but it is parented under `Enemies` with
  the same segment metadata, so `_clear_from_segment()` sweeps it up and
  `_spawn_boss()` puts it back on exactly the terms the zombies around it get.
  That is what makes dying to the boss a retry: without it a respawn at the gate
  would clear the boss away and leave a run that cannot be finished.
- **Winning freezes the tree** (`get_tree().paused`), which is what makes the
  run *over* rather than merely won — otherwise the hero can still be commanded
  around, and still killed, behind a VICTORY banner. `scenes/ui/` keeps the
  victory panel processing so its button still answers.
- **Death is ignored once the boss is down.** `_run_over` is set on the boss's
  `died`, before the beat that precedes the screen, because the boss room still
  has zombies in it and the hero is standing in the middle of them. A respawn
  starting behind the victory screen would take the win back. **It is tested on
  both sides of the respawn wait**, and the second test is not the first one
  repeated: a run can be won *during* that wait, and `create_timer` keeps
  counting through the pause a win brings with it. That half is unreachable
  today only because the hero is the only thing that can damage the boss and
  cannot swing while dead — an invariant about who damages what which no folder
  owns and nothing states. Cross-review of PR #50 asked for the line rather than
  the invariant, and it was right to.
- **The beat before the screen is load-bearing, not polish.** A corpse tween is
  bound to the corpse, so pausing on the frame the boss dies leaves it halfway
  through toppling over, underneath a banner saying it is dead.
- **Restarting reloads the scene, where a death deliberately does not.** The
  asymmetry is the point: a death has to preserve everything cleared behind the
  armed checkpoint, which is why issue #38 took the reload *out* of that path;
  a restart has to discard exactly that. Rebuilding is the only version of
  "discard all of it" that cannot forget a piece of run state — **and issue #8
  is where that stopped being a prediction.** XP, level and skill ranks are the
  first state a restart has to throw away, and `_restart_run` gained no line for
  them: they live on the hero, so the reload takes them. The pause flag remains
  the one exception, and it is the exception that proves the rule — it lives on
  the `SceneTree` rather than the scene, so it has to be cleared by hand or the
  new run comes up frozen.

## Progression (issue #8)

`main.gd` connects `Hero.killed` and turns it into XP. It is the same ownership
as the two sections above: this script decides what a death costs and what
winning means, so it decides what a kill is worth beside them.

- **The victim names its own price.** `main.gd` reads `xp_reward` off whatever
  died rather than keeping a per-enemy table here, so a new enemy type carries
  its value with it and nothing in this folder is edited to introduce one. A
  victim without the property is worth nothing rather than an error, which is
  what keeps this from becoming a third member of the hero↔enemy contract.
- **The hero does not award himself**, which is why `Hero.killed` finally has a
  consumer after being emitted and dropped since issue #11. `scenes/hero/` knows
  what it killed; how much a kill is worth in this level is a scene question.
- **Where the XP lives is `scenes/hero/`'s answer, not this one.** It is an
  `Experience` child on the hero (`scenes/components/`), so a restart discards it
  with the scene and a *death* does not — which is the same asymmetry
  `_restart_run` already draws for everything else. The comment there used to
  name issue #8's XP as a piece of run state that did not exist yet; it exists
  now, and it needed no line in `_restart_run` for exactly the reason that
  comment gave.
- The HUD is fed the same way everything else here is: `Experience.xp_changed`
  and `leveled_up` go straight to `HUD` methods, and the skill line is redrawn by
  `_refresh_skills()` from two signals — `Experience.points_changed` and
  `Hero.skill_ranked_up` — because the points total and the ranks are drawn
  together and move separately. `emit_current()` is called once at startup for
  the reason the health bar is pushed by hand: nothing re-sends those signals.
- **Issue #62's skill panel hangs off that same method**, which is the whole
  reason it needed no new plumbing: the panel draws the same two moving numbers,
  so it is fed from `_refresh_skills()` alongside the crib line, from the fuller
  `Hero.skill_catalogue()` report.

## The skill panel's two wires (issue #62)

`scenes/ui/` draws the tree and owns neither what it costs nor what it costs the
run, so both answers are given here — the same split the victory screen already
had.

- **`skill_rank_up_requested` buys through `Hero.spend_skill_point()`**, the very
  method the `1` and `2` keys use, refusals and all. The panel's buttons are
  already disabled on exactly the nodes that method would refuse, so a click
  arriving anyway is a race with a level-up and should lose the same way a
  keypress would. Nothing is redrawn from the handler: a purchase emits
  `skill_ranked_up`, which is already wired.
- **`skill_panel_toggled` freezes the run**, and **this script owns the pause
  flag** for the reason it already owns it at the victory screen: `paused` lives
  on the `SceneTree` rather than the scene, so it survives anything the scene
  does and exactly one script may set it. Choosing a build is a considered
  decision and the zombies do not wait; a tree readable only when nothing is
  chasing you would be unusable at the exact moment a level is banked.
- **Both carry the `_run_over` guard**, and it matters in opposite directions —
  here, unpausing a won run would take the win back.
- **The guard alone was not enough, and the gap is worth knowing.** `_run_over` is
  set the instant the boss falls; the victory screen waits `VICTORY_DELAY` (1.2 s)
  for the corpse to finish toppling. In between, this script refuses to touch the
  pause flag while `scenes/ui/` had not yet retired the panel — so opening it in
  that beat gave a panel over a live level, freezing nothing, against an invariant
  that folder states unconditionally. `_on_boss_died()` now retires the panel
  *before* the wait rather than with the screen. Cross-review of PR #62 found it,
  and it is the second time a `_run_over` window has needed closing on both sides
  of a wait — `_on_hero_died()` tests it twice for the same reason.

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
- `snap_to_target()` moves and **restores the authored angle** from a basis
  captured in `_ready()`. It used to re-aim with `look_at(target)`, which was
  the same thing while the camera sat at exactly `target + offset` — the
  direction is `-offset` either way. Bounds (below) break that identity on
  purpose, and aiming at the target from a held-back camera would tilt the
  fixed perspective by however much it is being held.
- The offset is `(0, 22.1, 14)` → a ~57° pitch. The old `(0, 16, 24)` (~33°)
  was authored for the small arena; on the 60×72 maze that shallow angle showed
  the map from the outside rather than the hero's surroundings. The level is now
  176×152, which does not change the offset.

### Level bounds (issue #43)

`main.gd` hands the camera `LevelMap.bounds()` **before the first snap**, and
the camera then stops following once its view would run off the level. Passed
in rather than read off the map, so the camera never learns what a level is —
the same seam that keeps the map from knowing what stands on its spawn markers.

Two things about it are worth knowing before touching it.

- **It measures the frame rather than assuming one.** The ground the camera
  covers is found by casting the four screen corners and intersecting them with
  the plane the target stands on, so the clamp is right at any window size. A
  hand-tuned margin would have reproduced the original bug, which got worse as
  the window got wider.
- **The clamp yields to the hero, and this is the part that is easy to get
  wrong.** Fitting the frame inside the level *exactly* is what the issue
  proposed, and on this map it is unusable: the level is 176 across against a
  ~140-wide frame, so squaring the view with the west edge slides the camera
  far enough sideways to carry the hero off the screen — measured at 158 px
  past the left edge at 1152×648. So a correction is capped at
  `MAX_TARGET_DRIFT` (0.15) of the frame, priced in pixels, per axis
  independently — the level has depth to spare and no width to spare, and a
  shared budget would let the west edge, which cannot be fixed, throttle the
  south edge, which costs about a metre.

What that buys, at 1152×648: the void band under the start clearing is gone,
the boss room frames without one, and what is left at spawn is a small dark
wedge in the far corner. **It does not promise the void is never on screen** —
near a corner the map cannot fill the frame and the camera will not pay the
hero's visibility for it. If that ever needs to be true, the fix is a wider
rock margin in the layout, not a bigger drift budget: past ~0.25 the camera
buys blank rock with the hero pinned to the edge, which looks worse than the
wedge.

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
  `scenes/enemies/zombie.tscn`, `scenes/enemies/boss.tscn` and
  `scenes/map/checkpoint.tscn` at runtime. Two exports are wired here as
  `NodePath`s and both point at the hero: the camera's `target` and
  `UnitSelection.hero`.
- **Input actions** are defined in `project.godot`. What each *means* belongs to
  the folder that consumes it; this is only the inventory:
  `move_command` (right mouse), `select_command` (left mouse),
  `attack_move` (`A`), `cancel_command` (`Escape`),
  `hold_position` (`H`), `stop_command` (`S`),
  `skill_strength` (`1`), `skill_health` (`2`), `toggle_skills` (`K`).
  Every letter-key action is bound to a *physical* keycode, so they land on the
  same keys whatever the keyboard layout.
  **All but one are consumed by `scenes/hero/`**, and the exceptions are worth
  naming because the list has stopped being uniform twice:
  - `skill_strength` / `skill_health` are consumed there but are **not
    commands** — they spend a skill point and leave the hero's orders alone.
  - `toggle_skills` is consumed by **`scenes/ui/`** (issue #62), the only action
    read outside `scenes/hero/`. Opening a panel issues no order, so routing it
    through the command scheme would put a screen toggle in the file that owns
    attack-move. `cancel_command` is now read in *both* folders — the panel
    closes on `Escape` and consumes the event, so it never also disarms an attack
    in the game behind it.
- `LevelMap` emits `built`; nothing consumes it yet.
- `main.gd` consumes `Checkpoint.reached` and calls `Checkpoint.set_armed()`
  back on every pad, so exactly one is lit. It calls `Hero.respawn_at()` and, on
  the way, `HUD.show_death()` / `hide_death()` / `flash_checkpoint()` —
  plus `HUD.show_victory()` when the boss falls. It consumes
  `HUD.restart_requested` in return.
- **Not every hero signal `scenes/ui/` uses comes through here**, and issue #65
  added the second one. That folder subscribes directly to whatever unit is
  *selected* — its `Health.health_changed` and `died` since #36, and its
  `stats_changed` now — because this script does not know what is selected and
  a wire through it would need a second record of that. The rule this folder
  keeps is narrower than it looks: what `main.gd` owns is the wiring of the
  **hero as the hero**, and a widget reading the unit it is currently drawing is
  not that.
- `main.gd` consumes `Hero.died`, `Hero.health.health_changed`,
  `Hero.attack_move_armed_changed` and `Hero.select_clicked`, forwarding each to
  `scenes/ui/`. Issue #67 added three more of the same shape —
  `Hero.move_ordered` and `Hero.attack_move_ordered` to the `OrderMarker`, and
  `Hero.holding_position_changed` to the `HUD`. The first two had been emitted
  and unconsumed since issue #11, and **which of them fires is the whole of what
  decides the marker's colour**: this script does not look at `current_order()`
  to choose, because the hero already reports which order a click became and a
  second reading of it here would be a second record that can disagree.
  Since issue #8 it also consumes `Hero.killed` and
  `Hero.skill_ranked_up`, plus `xp_changed`, `leveled_up` and `points_changed`
  from the hero's `Experience` child — see "Progression" above. Issue #62 added
  `HUD.skill_rank_up_requested` and `HUD.skill_panel_toggled`, the second and
  third signals to run from `scenes/ui/` back into the game. **`Hero.attack_ordered`
  is the last one still unconsumed**, and its two companions stopped being so in
  issue #67: this doc earmarked all three "for the selection UI, issue #36",
  which turned out to be wrong — selection is deliberately inert and reads
  nothing about what the hero is doing — and then sat calling them unconsumed for
  four issues until the order marker turned out to be what they were for after
  all. `attack_ordered` still has no consumer, because a marker that tracks a
  moving unit is a different feature from a ping on the ground. **All four of the
  hero's acquiring paths emit it anyway**, which cross-review of PR #70 is what
  made true. `Zombie.died` is consumed **on the
  boss and nowhere else** (issue #39) — every trash zombie's is still dropped.
  It was the other candidate XP hook and stayed unused: `Hero.killed` won it,
  because a death anything could have caused is the wrong signal to pay a hero
  for.

## Tooling note

`--headless --check-only --script` cannot resolve `class_name` types across
files (it doesn't load the global class cache), so it reports a false
"Could not find type" on scripts that reference `Hero`, `LevelMap`, or
`RTSCamera`. Run the scene instead to check those.

<!-- verified-against: e9f8a21 -->
