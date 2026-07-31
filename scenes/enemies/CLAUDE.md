---
depends-on: [scenes, scenes/hero, scenes/map, scenes/components, scenes/ui, assets]
---

# scenes/enemies/

Hostile actors: the basic zombie (issue #7) and the end boss (issue #39). They
are **one script and two scenes**.

- `zombie.tscn` — `CharacterBody3D`, collision layer 4 (enemies), mask 1|2|3.
  Placeholder green capsule + facing "nose" under a `Visual` node, a
  `CollisionShape3D`, a `NavigationAgent3D`, and a `Health` child (30 HP). In
  the `enemies` group — that is how the hero finds and targets it, so don't
  rename it: `scenes/hero/` looks enemies up by group, never by class.
- `boss.tscn` — the end boss. Structurally identical to the above, down to the
  layer, the mask and the group: the same script, a capsule scaled ~1.75×, and
  different export values. See "The boss" below.
- `zombie.gd` (`class_name Zombie`) — roam / notice / chase / melee AI, and the
  script on both scenes. Nothing in it knows which of the two it is running.

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
whole level by staying just inside aggro range, and encounters would drift away
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
  radius at the edge of the leash. It exits on `from_home <= roam_radius` **or**
  on the walk home finishing, and the second half is not belt-and-braces: the
  nav agent stops within `target_desired_distance` (1.0) of its goal, so a guard
  with `roam_radius = 0` never satisfies the first and would stand at its post
  in RETURN for the rest of the run — the one state that cannot acquire a
  target. Added with the boss, which is the first instance to have no patch at
  all; for any wider radius the distance test still wins and nothing changed.
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

`regen_delay` (6 s) with no damage taken, then `regen_per_second` (3.0) until
full. A 30 HP zombie is therefore whole again about ten seconds after a single
hero swing, but nearer sixteen if it was left on the brink — the delay dominates
only for light damage.

Two conditions gate it, and they close different escapes:

- The **timer** stops a zombie healing between the hero's swings.
- The **state check** — only `ROAM` and `RETURN` — stops one healing while it
  is chasing. A fight the player is slowly winning must not turn into one they
  cannot win at all, and a zombie that heals mid-chase does exactly that.

Together they mean the only way to undo damage is to actually break away. That
is what closes the chip-and-retreat exploit `leash_radius` would otherwise hand
the hero, now that he can deal damage at all (issue #11).

## The boss (issue #39)

`boss.tscn` is `zombie.gd` with different numbers, which is what this folder was
built for — every stat has been a per-instance export since #7 precisely so the
boss would not need a second AI. It did not: no new script, no new state, and no
change in `scenes/ui/`, because a unit describes itself to the info bar through
`unit_info()` and `display_name` and the boss simply reports bigger numbers.

| Export | Zombie | Boss | Why the boss's value |
|--------|--------|------|----------------------|
| `max_health` (on `Health`) | 30 | 240 | 20 hero swings — a fight with a shape, not a slog |
| `attack_damage` | 9 | 25 | four hits kill a full-health hero |
| `attack_cooldown` | 1.3 | 2.0 | the damage is huge, so it has to be dodgeable |
| `attack_range` | 2.0 | 3.0 | **longer than the hero's 2.2** — see below |
| `chase_speed` | 3.4 | 2.2 | slow enough that kiting is a real option |
| `roam_radius` | 6 | 0 | a guard, not a wanderer |
| `detection_radius` | 12 | 18 | notices the hero ~4.5 cells into the room |
| `aggro_radius` | 18 | 24 | above detection, so the hysteresis still exists |
| `leash_radius` | 26 | 22 | under the 24 units from its post to the gate |
| `alert_delay` | 0.5 | 1.0 | a longer, more readable wind-up |
| `regen_delay` / `regen_per_second` | 6 / 3 | 8 / 12 | leaving the fight resets it |
| `display_name` | `"Zombie"` | `"Zombie Warlord"` | what the info bar calls it |

Three of those are the design rather than the tuning, and are the ones to argue
with before touching the rest:

- **The boss out-reaches the hero, where every zombie under-reaches him.** The
  zombie's 2.0 against his 2.2 is what makes trading blows toe-to-toe *not* a
  coin flip; inverting it means the boss cannot be out-traded at all and has to
  be fought by moving. That is the whole encounter, and it is why `chase_speed`
  is low enough for kiting to work.
- **`roam_radius = 0` and a leash shorter than the way out make it a guard.**
  Its post is 6 cells (24 units) from the boss-room gate and it turns back at
  5.5, so it can never follow the hero out of the room, and there is no wander
  that could carry it there either. The leash binds before `aggro_radius` does,
  deliberately.
- **Breaking off the fight resets it.** Regeneration is state-gated (see above),
  so kiting inside the room never heals it — only a genuine disengage does, at
  12 HP/s against the hero's 4. Retreating to heal is therefore a net loss and
  the fight has to be won in one engagement. The 8 s delay is what keeps a
  two-second reposition free.

The stats are a first pass and are meant to be argued with: nothing in the game
was balanced against an end boss before there was one.

**It does not aggro on the frame the hero respawns**, and that is the same
invariant `scenes/map/` states for spawns rather than a second rule: the boss
sits 6 cells from the boss-room checkpoint, outside both its own
`detection_radius` (4.5 cells) and the hero's `acquire_radius`. Moving the
checkpoint closer, or raising either radius, breaks it.

**Its selection ring is a crescent, not a ring** — issue #49. The ring in
`scenes/ui/` is one fixed torus of outer radius 0.7, which is exactly the boss's
body radius, so only the near arc clears the capsule. It still reads; anything
wider than this will not.

## Gotchas

- **Sensing is throttled** to one tick per `SENSE_INTERVAL` (0.2 s), and the
  first tick is randomly offset per zombie in `_ready()`. A shambling zombie
  does not need 60 Hz reflexes, the cost stays flat as the level fills up, and
  the offset stops a room full of them moving in lockstep. Anything that needs
  per-frame precision (the attack cooldown, gravity, movement) is in
  `_physics_process`, not `_think()`.
- **`_ready()` awaits one `physics_frame` before its first path request.**
  `NavigationServer3D` syncs its maps at the end of a physics frame and
  `scenes/main.gd` bakes the navmesh in its own `_ready()`; querying before that
  sync returns the map origin, which would send every zombie walking to the
  middle of the level. Don't remove the await.
- **Line of sight is a chest-to-chest ray against layer 2 only** (walls). Drop
  it and zombies detect the hero through solid rock, then appear round a corner
  for no visible reason. `scenes/hero/` now casts the mirror image of this ray
  for his own automatic acquisition, at the same eye height on purpose — if the
  two heights ever diverge, one side sees through cover the other treats as
  solid, and a fight starts that only one participant can explain.
- **The open level (issue #37) made the sight gate do much less work.** In the
  maze, walls broke sight constantly and delivered zombies one or two at a time
  whatever the layout said. In a clearing nothing blocks the ray, so every
  zombie within `detection_radius` notices the hero in the same tick and arrives
  together. None of the radii changed — the geometry did. Group size is now a
  property of where the map author puts a `Z`, which is the tuning knob to reach
  for first; see `scenes/map/CLAUDE.md`.
- **Wander targets are clamped with `NavigationServer3D.map_get_closest_point`**,
  the same way every `Hero` order clamps its destination — a random point that lands
  inside rock becomes the nearest reachable spot instead of a path request that
  resolves to nothing.
- **The hit flash needs its own material, and `_ready()` duplicates one.** The
  body material is a sub-resource of the scene — of either scene — and Godot
  shares a scene's sub-resources across every instance of it, so tinting one
  zombie would tint the whole horde. `_claim_own_material()` duplicates it per instance. Done in code
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
  The trade is that a pack overlaps visually — and the open level made that
  worse, because a group converging across a clearing has room to bunch where a
  corridor used to string it out. Revisit with agent avoidance when it starts to
  look wrong.

## Dependencies / signals

- Finds the hero via `get_tree().get_first_node_in_group("hero")` — no scene
  path, so a zombie works in any scene that has a hero and a baked navmesh.
- Calls `Hero.take_damage()`; reads `Hero.is_dead()` to stop hitting a corpse.
  **Since issue #38 a corpse can stop being one** — the hero respawns rather
  than reloading the scene — and nothing here needed changing for it, because
  every state reads `is_dead()` fresh on its own sense tick rather than latching
  a death. A zombie left in `ATTACK` when he died finds him alive again but far
  away on the next tick, so it leashes home the ordinary way.
- **Is damaged by the hero through the same two methods, in reverse.**
  `scenes/hero/` calls `take_damage()` and reads `is_dead()` on whatever is in
  the `enemies` group, without ever naming `Zombie`. So the pair of methods and
  the group name are a two-way contract; changing either signature breaks a
  folder that does not mention this one.
- Emits `died(zombie)`. **`scenes/main.gd` connects it on the boss and on
  nothing else** (issue #39): one enemy in the level has a death that ends the
  run, and every other one is still dropped. It remains the hook XP will hang
  off (issue #8), and the hero still emits his own `killed(victim)` from the
  swing that lands the blow, which is the *attributed* version of the same
  moment.
- **Describes itself to the unit info bar** through `unit_info()` and the
  `display_name` export (per-instance like every stat, so the boss-room guard
  the class docs describe can announce itself without a new scene). The travel
  speed it reports is `chase_speed`, not `roam_speed`: what a player wants when
  they click a zombie is how fast it closes on them. Selecting a zombie does
  nothing to it — `scenes/ui/` never issues an order. That folder also watches
  the `Health` child's `died` so the bar drops a corpse, which is why it is in
  the frontmatter above.
- Spawned by `scenes/main.gd` from `LevelMap.zombie_spawns()` — the `Z` cells of
  `scenes/map/level_map.gd`, each carrying the checkpoint segment it belongs to.
  The spawner sets `position` *before* `add_child`, because `_ready()` captures
  `global_position` as home. **The boss is placed from `boss_position()` and
  `boss_segment()` instead**, being one authored instance rather than a list
  entry — but it lands under the same parent carrying the same segment metadata,
  which is what lets everything below apply to it unchanged.
- **It also removes them** (issue #38): on respawn, every enemy in the restored
  segment is freed and re-instanced, living, chasing or already a corpse. That
  is why "restored zombies are home in `ROAM`" needs no reset method here — a
  fresh instance is the reset. Two consequences worth knowing: a zombie can
  leave the tree without `died` ever firing, which is what anything holding a
  reference to one must survive (`scenes/ui/` does, and says so); and the
  segment lives on the instance as node metadata rather than as anything this
  script knows about, so nothing in here needs to learn about checkpoints.
- Still placeholder capsules, both of them. The Quaternius zombie models in
  `assets/characters/zombies/` are imported but unused, matching the hero — and
  the boss has no model of its own at all, so whatever it eventually wears is a
  separate question from what the horde does.

<!-- verified-against: a29d8c3 -->
