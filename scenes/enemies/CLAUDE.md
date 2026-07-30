---
depends-on: [scenes, scenes/hero, scenes/map, scenes/components, assets]
---

# scenes/enemies/

Hostile actors. Currently just the basic zombie (issue #7).

- `zombie.tscn` — `CharacterBody3D`, collision layer 4 (enemies), mask 1|2|3.
  Placeholder green capsule + facing "nose" under a `Visual` node, a
  `CollisionShape3D`, a `NavigationAgent3D`, and a `Health` child (30 HP). In
  the `enemies` group — that is how the hero finds and targets it, so don't
  rename it: `scenes/hero/` looks enemies up by group, never by class.
- `zombie.gd` (`class_name Zombie`) — roam / notice / chase / melee AI.

## The four radii

They are deliberately four different things, and reviewers should not collapse
them:

| Export | Default | Meaning |
|--------|---------|---------|
| `roam_radius` | 6 | The patch it wanders while idle, centred on **home** — where it spawned. |
| `detection_radius` | 12 | How far it can *notice* the hero. **Requires line of sight.** |
| `aggro_radius` | 18 | How far it will *keep* chasing once committed. |
| `leash_radius` | 26 | Hard tether to home, whatever the hero does. |

`aggro_radius > detection_radius` on purpose — that gap is hysteresis. With one
shared radius the zombie flickers in and out of aggro whenever the hero stands
near the boundary, and you could shake it by stepping back one metre.

`leash_radius` is home-relative where `aggro_radius` is hero-relative, so they
are not redundant: without the leash the hero could tow a zombie across the
whole maze by staying just inside aggro range, and encounters would drift away
from where the map author placed them.

## States

`ROAM → ALERT → CHASE ⇄ ATTACK`, plus `RETURN` and `DEAD`.

- **ROAM** — picks a random point in the home disc (`sqrt(randf())` so
  destinations spread evenly instead of bunching at the centre), walks there at
  `roam_speed`, pauses `roam_pause_min..max`, repeats. The only state that
  acquires a target.
- **ALERT** — noticed the hero: stops and turns to face him for `alert_delay`
  (0.5 s) before charging. A readable beat, not an instant snap into a sprint —
  it matters in a top-down view where the player reads the whole screen. Drops
  back to ROAM if the hero leaves `detection_radius` during the beat.
- **CHASE** — repaths to the hero on every sense tick.
- **ATTACK** — inside `attack_range` (2.0): stands, faces, and calls
  `hero.take_damage(attack_damage)` every `attack_cooldown`. There is no
  wind-up; the swing lands the instant the cooldown expires. Add a telegraph
  when there are attack animations to hang it on.
- **RETURN** — leashed or lost him. **Ignores the hero until home is reached**,
  so he cannot chain-pull a zombie across the map by re-entering its detection
  radius at the edge of the leash.
- **DEAD** — goes inert (layer and mask both zeroed), emits `died(zombie)`, then
  a tween falls it over, lingers, sinks it and frees it. **`_physics_process`
  returns immediately for a dead body, above the gravity block**, and that
  ordering is load-bearing rather than tidy: clearing the mask leaves nothing to
  stand on, so below the gravity block `is_on_floor()` is false from the frame
  of death onward and never recovers, velocity accumulates, and the corpse
  drives through the floor — measured at 40 units in under 3 s before this was
  fixed. The death tween owns every remaining motion; the body itself must not
  be simulated at all.

  Note what zeroing the *layer* does not buy you: nothing masks layer 4 (see
  the table in `scenes/CLAUDE.md`), so a zombie was never an obstacle to
  anything, alive or dead. An earlier version of this doc and of the code
  claimed the clear was what stopped a corpse plugging a corridor. It is not —
  the mask is the half that changes behaviour.

`take_damage()` aggroes regardless of range, sight or leash — otherwise the
hero could whittle a zombie down from outside its detection radius. It also
flashes the body (see the gotcha below) and resets the regen timer.

## Regeneration

`regen_delay` (6 s) then `regen_per_second` (3.0) — a 30 HP zombie is whole
again ten seconds after the last hit lands.

Two conditions gate it, and they close different escapes:

- The **timer** stops a zombie healing between the hero's swings.
- The **state check** — only `ROAM` and `RETURN` — stops one healing while it
  is chasing. A fight the player is slowly winning must not turn into one they
  cannot win at all, and a zombie that heals mid-chase does exactly that.

Together they mean the only way to undo damage is to actually break away. That
is what closes the chip-and-retreat exploit `leash_radius` would otherwise hand
the hero, now that he can deal damage at all (issue #11).

## Gotchas

- **Sensing is throttled** to one tick per `SENSE_INTERVAL` (0.2 s), and the
  first tick is randomly offset per zombie in `_ready()`. A shambling zombie
  does not need 60 Hz reflexes, the cost stays flat as the maze fills up, and
  the offset stops a room full of them moving in lockstep. Anything that needs
  per-frame precision (the attack cooldown, gravity, movement) is in
  `_physics_process`, not `_think()`.
- **`_ready()` awaits one `physics_frame` before its first path request.**
  `NavigationServer3D` syncs its maps at the end of a physics frame and
  `scenes/main.gd` bakes the navmesh in its own `_ready()`; querying before that
  sync returns the map origin, which would send every zombie walking to the
  middle of the maze. Don't remove the await.
- **Line of sight is a chest-to-chest ray against layer 2 only** (walls). Drop
  it and zombies detect the hero through solid rock, then appear round a corner
  for no visible reason.
- **Wander targets are clamped with `NavigationServer3D.map_get_closest_point`**,
  the same way every `Hero` order clamps its destination — a random point that lands
  inside rock becomes the nearest reachable spot instead of a path request that
  resolves to nothing.
- **The hit flash needs its own material, and `_ready()` duplicates one.** The
  body material is a sub-resource of `zombie.tscn`, and Godot shares a scene's
  sub-resources across every instance of it — tinting one zombie would tint the
  whole horde. `_claim_own_material()` duplicates it per instance. Done in code
  rather than by ticking `resource_local_to_scene` on the resource: an editor
  round-trip can quietly clear a flag, and nothing would fail until someone
  noticed the entire map flashing at once. Anything else that animates a
  material on this scene has the same problem.
- **The flash fires *before* the damage is applied.** A killing blow runs
  `_on_health_died()` synchronously inside `Health.take_damage()`, so a flash
  started afterwards would be repainting a corpse.
- **Zombies don't collide with each other** (mask omits layer 4). They *are*
  blocked by the world and by the hero, but the hero (mask 1|2) is never blocked
  by them. Zombies that collide jam solid in a one-cell corridor, and a hero who
  can be body-blocked wedges exactly the way `scenes/map/CLAUDE.md` describes.
  The trade is that a pack overlaps visually; revisit with agent avoidance when
  it starts to look wrong.

## Dependencies / signals

- Finds the hero via `get_tree().get_first_node_in_group("hero")` — no scene
  path, so a zombie works in any scene that has a hero and a baked navmesh.
- Calls `Hero.take_damage()`; reads `Hero.is_dead()` to stop hitting a corpse.
- **Is damaged by the hero through the same two methods, in reverse.**
  `scenes/hero/` calls `take_damage()` and reads `is_dead()` on whatever is in
  the `enemies` group, without ever naming `Zombie`. So the pair of methods and
  the group name are a two-way contract; changing either signature breaks a
  folder that does not mention this one.
- Emits `died(zombie)`. Nothing consumes it yet — it is the hook for XP
  (issue #8). Note the hero emits its own `killed(victim)` from the swing that
  lands the blow, which is the *attributed* version of the same moment.
- Spawned by `scenes/main.gd` at the `Z` cells of `scenes/map/maze.gd`; the
  spawner sets `position` *before* `add_child`, because `_ready()` captures
  `global_position` as home.
- Still a placeholder capsule. The Quaternius zombie models in
  `assets/characters/zombies/` are imported but unused, matching the hero.

<!-- verified-against: 8a4044b -->
