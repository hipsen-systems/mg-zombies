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
| `max_health` (on `Health`) | 30 | 190 | 16 hero swings — a fight with a shape, not a slog |
| `attack_damage` | 9 | 18 | six hits kill a full-health hero |
| `attack_cooldown` | 1.3 | 2.0 | the damage is huge, so it has to be dodgeable |
| `attack_range` | 2.0 | 3.0 | **longer than the hero's 2.2** — see below |
| `chase_speed` | 3.4 | 2.2 | slow enough that kiting is a real option |
| `roam_radius` | 6 | 0 | a guard, not a wanderer |
| `roam_speed` | 1.3 | 1.0 | the walk *back to its post* — see below |
| `detection_radius` | 12 | 18 | notices the hero ~4.5 cells into the room |
| `aggro_radius` | 18 | 24 | above detection, so the hysteresis still exists |
| `leash_radius` | 26 | 22 | under the 24 units from its post to the gate |
| `alert_delay` | 0.5 | 1.0 | a longer, more readable wind-up |
| `regen_delay` / `regen_per_second` | 6 / 3 | 8 / 12 | leaving the fight resets it |
| `xp_reward` | 10 | 100 | ten zombies' worth, for the fight that ends the run |
| `display_name` | `"Zombie"` | `"Zombie Warlord"` | what the info bar calls it |

**`roam_speed` is the one that looks inert and is not**, which is worth stating
because a reader who checks will reach for the wrong conclusion first: with no
roam radius the boss never walks anywhere in `ROAM`, so the obvious reading is
that the value is dead and the override pointless. But `RETURN` also travels at
`roam_speed` — only `CHASE` uses `chase_speed` — so this is the speed the boss
shambles back to its post at after a leash, which is the *only* time it walks
without a target. Cross-review of PR #50 read it as unused; a headless run
measured the boss covering ~1.0 units per second on the way home.

Three of those are the design rather than the tuning, and are the ones to argue
with before touching the rest:

- **The boss out-reaches the hero, where every zombie under-reaches him.** The
  zombie's 2.0 against his 2.2 is what makes trading blows toe-to-toe *not* a
  coin flip; inverting it means the boss cannot be out-traded at all and has to
  be fought by moving. That is the whole encounter, and it is why `chase_speed`
  is low enough for kiting to work.
  **Since issue #9 the hero's reach is buyable, and this 3.0 is what caps it.**
  The tree in `scenes/skills/` stops at +0.6, so a fully invested hero reaches
  2.8 and the inversion survives a maxed build — otherwise the boss's identity
  could be spent away from a `.tres` in a folder that has never heard of it.
  `tests/smoke_skills.gd` asserts the gap rather than trusting either doc, so
  lowering this number is a change that will be caught here.
- **`roam_radius = 0` and a leash shorter than the way out make it a guard.**
  Its post is 6 cells (24 units) from the boss-room gate and it turns back at
  5.5, so it can never follow the hero out of the room, and there is no wander
  that could carry it there either. The leash binds before `aggro_radius` does,
  deliberately.
- **Breaking off the fight resets it.** Regeneration is state-gated (see above),
  so kiting inside the room never heals it — only a genuine disengage does, at
  12 HP/s against the hero's 4, or against 7 for a build that has bought every
  rank of Recovery (issue #9). Retreating to heal is therefore a net loss either
  way and the fight has to be won in one engagement, but the margin is a third
  of what this bullet used to claim, so a skill tree that ever sells regen
  harder is what would turn this from a rule into a coin flip. The 8 s delay is
  what keeps a two-second reposition free.

**Both of those margins stopped being theoretical in issue #62**, and that is the
only thing that change did to this folder — no stat moved. `reach` and `recovery`
are two of the four nodes that had no hotkey and so could not be bought in play
at all; the panel in `scenes/ui/` now sells them. So the 2.8-against-3.0 reach
gap and the 7-against-12 regeneration margin describe builds a player can
actually arrive at, where until now they described builds only
`tests/smoke_skills.gd` ever constructed. The numbers were always checked; what
changed is that they are now *encountered*. If either turns out to be wrong, it
will be wrong in play rather than in a test, which is the first time that has
been true of this table.

## The first pass was unwinnable, and what measuring it settled (issue #66)

The line below used to end this section by saying the stats were a first pass
meant to be argued with. Playtesting made the argument: **no build a player can
reach could kill the boss**, so the run could not be finished, and every check in
the repo stayed green while that was true. What follows is measured against the
real scene rather than reasoned about, which is the only reason it is trustworthy
— the arithmetic done first got the level's XP yield wrong by nearly double.

**What the level actually pays is 3 skill points.** 19 `Z` cells at 10 XP each is
190 XP, which is level 4. Every estimate of this fight has to start there and not
from the 26-point full build, which is level 27 and exists only in
`tests/smoke_skills.gd`.

| Hero, standing and trading | Old (240 hp / 25 dmg) | Now (190 / 18) |
|---|---|---|
| No points spent | dies, boss on 65% | dies, boss on 24% |
| 3 points — the level's whole yield | dies, boss on 48% | **wins with 10/100 hp** |
| Full 26-point build | wins with 50/150 | wins with 96/150 |

**Only `max_health` and `attack_damage` moved.** Reach, cooldown, chase speed,
the radii and the regeneration are all untouched, because each of those is a
design statement and none of them was the fault.

**The regeneration was not the fault, and that is the finding worth keeping.**
It was the obvious suspect — the fight is unwinnable and the boss heals three
times faster than the hero — so it was tested rather than assumed, by chipping it
down and withdrawing to heal, six cycles, at three different regen rates:

| Boss regen | Net progress per cycle |
|---|---|
| 12/s (shipped) | **exactly 0** — 240 → 240 over six cycles |
| 4/s (matched to the hero's own) | ~0 — 240 → 224 over six cycles |
| 0/s | 54 a cycle; the boss dies on the fifth |

So turning it down would not have fixed anything: the walk back is ~14 s each
way and the boss heals through all of it, which swamps the rate. Only removing
regeneration entirely makes chipping work, and that would delete the design rule
outright. **The rule was doing its job perfectly; the fight simply had no other
way to be won.** Worth generalising, because the suspect the symptom names is not
always the cause — "heals too fast" was a true description of the experience and
the wrong diagnosis of it.

**Retreating to the boss-room gate is not a disengage**, which nothing here said
and the measurement found by accident. The boss follows to its leash limit, 22
units from its post, and the gate is 24 — leaving it 2 units from a hero standing
there, well inside his own 9-unit `acquire_radius`, so an idle hero re-acquires
it on the next tick and the fight never breaks off at all. The disengage in the
table above had to withdraw to the *previous* checkpoint, 84 units back. The
"it can never follow the hero out of the room" bullet above is still true and is
a different claim from "there is anywhere in the room to stand and heal", which
is false.

**The room is still the difficulty, and this is what keeps standing-and-trading
from being the answer.** With the boss room's own zombies left alive, the same
3-point hero dies with the boss on 43%. That is not a softer or harder version of
the table above but a different fight: the points there are *paid for* by those
kills, so a hero who has them has already cleared the room. Charging the gate
without doing the level is the row that loses, and it loses for the right reason.

`tests/smoke_boss.gd` holds the top-right cell of that table — it is the only
assertion in the suite that the game can be completed, and it fails on the old
numbers with the exact symptom playtesting reported.

The stats are still meant to be argued with, and one is now weaker than it was:
standing still and trading at full investment is a win by 10 hp, where the reach
inversion says it should be a loss. It is a hair's-breadth win in the worst
possible line of play, so the encounter still rewards moving — but if the fight
ever reads as too forgiving, that cell is the one to push on, and pushing on it
means `max_health` rather than the reach.

**It does not aggro on the frame the hero respawns**, and that is the same
invariant `scenes/map/` states for spawns rather than a second rule: the boss
sits 6 cells from the boss-room checkpoint, outside both its own
`detection_radius` (4.5 cells) and the hero's `acquire_radius`. Moving the
checkpoint closer, or raising either radius, breaks it.

**Its selection ring is a crescent, not a ring** — issue #49. The ring in
`scenes/ui/` is one fixed torus of outer radius 0.7, which is exactly the boss's
body radius, so only the near arc clears the capsule. It still reads; anything
wider than this will not.

## What a crowd of these costs (issue #72)

The outdoor direction asks for encounters of 100+, against a folder built and
tuned at 19. `tests/bench_crowd.gd` measured it rather than arguing about it —
headless, `--fixed-fps 60`, crowds of 50/400 on top of the level's own 20, in
three states. Milliseconds per frame, typical of four runs:

| crowd | roaming | chasing a moving hero | in melee contact |
|-------|---------|-----------------------|------------------|
| +0 (the level as shipped) | 0.8 | 0.7 | 0.7 |
| +50 | 2.0 | 2.8 | 2.1 |
| +100 | 3.4 | 5.0 | 3.5 |
| +200 | 6.3 | 9.1 | 6.7 |
| +400 | 12.0 | 18.0 | 15.4 |

**The answer is yes, with room, and the ceiling is around 200 chasing at once.**
A hundred committed enemies cost 30% of a 16.67 ms frame; two hundred cost 55%;
four hundred cost 108% and do not fit. Nothing broke at any size — every body
stayed on the navmesh, none fell through the floor, and the crowd kept its
members — so the failure mode approaching the ceiling is frame time and not
correctness. Two caveats travel with every number: **there is no renderer in a
headless run**, so this is a floor for the real frame and says nothing about
drawing hundreds of skinned meshes (issue #82); and the enemies are still
capsules, so nothing here has been paid for yet.

**Cost is linear in the crowd — about 27 µs per roaming enemy per frame and
43 µs per chasing one** — which is the finding that should shape whatever gets
built next, because it says the repathing is only part of the problem:

- **Existing and being simulated is ~60% of a chasing enemy's cost.** A
  `CharacterBody3D` stepping, a state machine ticking and a `NavigationAgent3D`
  living in the scene cost 27 µs whether or not the enemy is doing anything
  interesting.
- **Solving a path to a moving hero is the other ~40%** (16 µs). Real, and the
  largest single line item, but a perfect flow field costing nothing would cut a
  400-crowd from 18.0 ms to about 12 — still 72% of the budget. Worth building
  (issue #80), worth not expecting it to be the whole answer.
- **The lever the numbers actually favour is not doing the other 60% for enemies
  nobody can see** (issue #81).
- **A negative result worth keeping: repathing in `ATTACK` is not worth fixing.**
  `_think()` falls through to the same `target_position` assignment in `ATTACK`
  as in `CHASE`, while `_process_attack()` stands still and never reads the
  path — so every enemy in contact pays for a path it throws away, which looks
  like free money. It is not: at +100 and +200 the contact column matches the
  roaming column to within noise, because the wasted path is one hop long. The
  gap at +400 is 400 bodies overlapping inside a 1.8-unit disc, which is the
  benchmark's packing and not a property of combat.
- **The sense-tick stagger below is doing its job.** There is no 5 Hz spike
  pattern at any crowd size; the 95th-percentile frame stays within about 1.5×
  the mean throughout.

## Gotchas

- **Sensing is throttled** to one tick per `SENSE_INTERVAL` (0.2 s), and the
  first tick is randomly offset per zombie in `_ready()`. A shambling zombie
  does not need 60 Hz reflexes, so an enemy's cost is capped per second rather
  than per frame, and the offset stops a room full of them moving in lockstep —
  which is what keeps a crowd's cost smooth rather than arriving in 5 Hz spikes.
  It does **not** make the total flat, as an earlier version of this line could
  be read to claim: the total is linear in the crowd, measured above. Anything
  that needs per-frame precision (the attack cooldown, gravity, movement) is in
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
  run, and every other one is still dropped. **It did not become the XP hook**
  (issue #8) — `Hero.killed`, fired from the swing that lands the blow, did,
  because this signal announces a death without saying who caused it and a hero
  should not be paid for one he had no part in. Nothing here changed for XP
  beyond the export below.
- **A unit says what killing it is worth**, through the `xp_reward` export.
  Per-instance like every other stat here, so the boss is worth ten zombies
  without a second script, and read *off the victim* by `scenes/main.gd` rather
  than looked up in a table there — the same principle as `unit_info()`, and it
  means a new enemy type carries its value with it. It is deliberately **not** a
  third member of the contract with `scenes/hero/`: that folder never reads it,
  and a victim without the property is worth nothing rather than an error.
- **Describes itself to the unit info bar** through `unit_info()` and the
  `display_name` export (per-instance like every stat, so the boss-room guard
  the class docs describe can announce itself without a new scene).
  **It does not emit `stats_changed`**, the optional fourth member issue #65
  added to that contract, and the absence is a decision rather than an omission:
  nothing moves a zombie's numbers after it spawns, so there is never a stale row
  to redraw. The hero has one because a skill point moves his mid-run. Anything
  here that ever gains a buff, an enrage or a scaling stat owes the signal —
  without it the panel silently shows the numbers the thing spawned with, which
  reads as a balance question rather than a UI one. The travel
  speed it reports is `chase_speed`, not `roam_speed`: what a player wants when
  they click a zombie is how fast it closes on them. Selecting a zombie does
  nothing to it — `scenes/ui/` never issues an order. That folder also watches
  the `Health` child's `died` so the bar drops a corpse, which is why it is in
  the frontmatter above.
- **What this folder claims about `scenes/hero/` is the group-and-methods
  contract and the leash, and neither moves when he gains an order.** Stated
  because issue #67 gave him two — hold position and stop — and the `depends-on`
  graph duly flagged this doc, correctly and with nothing to find. A zombie
  reacts to where the hero *is*, never to what he has been told to do, which is
  what makes that whole class of change invisible from here. The one thing a new
  order can reach is encounter *design* rather than this folder's code: a hero
  who can be made to stand still is a hero who can hold a chokepoint, and
  `scenes/map/` is where that is written down.
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

<!-- verified-against: e9f8a21 -->
