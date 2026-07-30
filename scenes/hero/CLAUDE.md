---
depends-on: [scenes, scenes/components, scenes/enemies, assets]
---

# scenes/hero/

The player-controlled hero (issue #5: movement; issue #7: taking damage and
dying; issue #11: his own attack).

- `hero.tscn` — `CharacterBody3D` (collision layer 3, mask 1|2 — see the
  layer table in `scenes/CLAUDE.md`) with a placeholder capsule + a small
  "nose" box marking the facing direction **under a `Visual` node**, a
  `CollisionShape3D`, a `NavigationAgent3D`, and a `Health` child (100 HP,
  `scenes/components/`). In the `hero` group — that is how zombies find him,
  so don't rename it. The KayKit Knight is already in the repo
  (`assets/characters/hero/Knight.glb`, imported in issue #12) — swapping the
  capsule for it is outstanding work, not a pending dependency. The node
  forward direction is -Z (Godot convention) so the rigged model drops in
  without a compensating rotation.
  - The meshes sit under `Visual` (matching `zombie.tscn`) so the swing
    animation can move the art without moving the collider or the nav agent.
- `hero.gd` (`class_name Hero`) — command controller and basic attack.

## Commands

The scheme is StarCraft/Warcraft's **smart command**, chosen because that is
the control model the whole game is styled after. Actions are in
`project.godot`; `scenes/CLAUDE.md` lists them.

| Input | On an enemy | On the ground |
|-------|-------------|---------------|
| Right-click (`move_command`) | attack it | move there |
| `A` then left-click (`attack_move` + `select_command`) | attack it | attack-move there |
| Left-click alone (`select_command`) | *selection — issue #36* | *selection — issue #36* |
| `Escape` (`cancel_command`) | disarms `A` | disarms `A` |

**Left-click is deliberately never an attack.** An RTS where inspecting a unit
also swings at it is unusable, so the button is reserved for selection even
though nothing consumes a bare left-click yet. `A` borrows it for exactly one
click and hands it straight back.

Public order API — future AI, skills and tests should call these rather than
poking the `NavigationAgent3D`: `command_move_to(point)`,
`command_attack(target)`, `command_attack_move(point)`, `command_stop()`.
Each cancels the previous order outright: the agent repaths and horizontal
velocity is zeroed so the hero can't coast a frame along the abandoned heading.

## Which orders acquire targets

Four orders (`IDLE`, `MOVE`, `ATTACK_TARGET`, `ATTACK_MOVE`), and the only
interesting question is which of them pick up a target on their own. Every
answer is a decision:

- **`MOVE` does not.** A move order runs the gauntlet untouched. This is what
  makes "sprint past the encounter" a real choice rather than a bug — worth
  protecting, because the hero outruns every zombie (6.0 against a 3.4 chase)
  and gating that would need a design answer, not a speed tweak.
- **`ATTACK_MOVE` does.** That is the entire difference between it and `MOVE`.
  The destination survives the fight: `_finish_engagement()` resumes it once
  the target dies.
- **`IDLE` does.** A hero standing still defends himself. This also removes the
  need for a separate retaliate-when-hit rule — nothing can reach him from
  outside `acquire_radius` in the first place.

Acquisition and repathing run on a 0.2 s tick (`RETARGET_INTERVAL`), matching
the sensing budget in `scenes/enemies/`. Only the cooldown, gravity and
movement need per-frame precision.

## Stats

All exports, not constants, because the skill tree (issue #9) will want to
modify them and a `const` is not a seam. There is deliberately **no stat or
modifier system yet** — that is issue #9's job, and inventing one here would
prejudge it.

| Export | Default | Note |
|--------|---------|------|
| `move_speed` | 6.0 | Faster than any zombie, on purpose |
| `attack_range` | 2.2 | Slightly out-reaches the zombie's 2.0 |
| `attack_damage` | 12.0 | 3 swings kill a 30 HP zombie |
| `attack_cooldown` | 0.9 | Attack speed, expressed as the zombie's is |
| `acquire_radius` | 9.0 | Under the zombie's 12 detection: he is noticed first |
| `regen_delay` / `regen_per_second` | 5.0 / 4.0 | See below |

Measured 1v1 against one zombie: ~18 HP lost per kill, ~6 s of fighting.

**Out-of-combat regeneration** starts `regen_delay` after the last combat
event, where *both* taking a hit and landing one count — a hero trading blows
never regenerates mid-fight. It exists for issue #38: without it, clearing a
fight at low health makes the next one unwinnable and the only remaining move
is to die on purpose, which is a miserable way to use a checkpoint.

## Picking things out of the world

- The ground ray collides only with physics layer 1, so clicking a wall moves
  the hero to the floor at/behind that point instead of trying to climb it.
- **Every click produces an order.** The raycast alone silently dropped clicks
  that hit no ground collider (dark background, past the level edge, above a
  wall) — which read in play as "my second click was ignored", since the hero
  just kept walking to its previous destination. `_ground_point_at` therefore
  falls back to intersecting the camera ray with the hero's ground plane, and
  the order clamps the result onto the navigation map
  (`NavigationServer3D.map_get_closest_point`), so an off-level click means
  "walk as far that way as you can". Don't reintroduce an early-out that drops
  a click.
- **Enemies and ground are two separate ray queries, not one 1|8 mask.** A
  single ray returns whichever surface is nearer, and the floor under a
  zombie's feet sometimes wins.
- **`CLICK_SLACK` (1.6) is a click-target grace radius.** A 0.4-radius capsule
  seen down a ~57° camera is small, and an attack order that quietly becomes a
  move order *into* a pack is the worst way to miss. If the enemy ray misses,
  the nearest living enemy within 1.6 units of the clicked ground point is
  taken instead. Keep it under half a cell (2.0) or clicking the floor beside a
  zombie stops meaning the floor.
- The handler uses the *event's* `position`, not
  `get_viewport().get_mouse_position()` — the two can differ by the time the
  event is handled, and it keeps the path drivable from headless tests.

## Gotchas

- **`hero.gd` never names an enemy class.** Targets are found through the
  `enemies` group and used through `take_damage()` / `is_dead()`. There is no
  compile-time dependency on `scenes/enemies/`, so a second enemy type needs no
  change here — but the group name and those two methods are a real runtime
  contract, which is why `scenes/enemies` is declared in the frontmatter above.
  A missing edge would be invisible; renaming the group would break the hero
  with nothing to catch it.
- **Every range test measures horizontally**, through one helper, so the repath
  check and the swing check cannot disagree at the boundary — a hero that
  counted the height difference in one and not the other would repath and swing
  on alternate ticks. The floor is flat today, so nothing would show it; the
  first ramp would.
- **The attack-targeting ray is a new consumer of physics layer 4**, which no
  *body* masks. See the table in `scenes/CLAUDE.md`: a query mask and a body's
  `collision_mask` answer different questions, and only the first one applies
  here.
- **A target that finishes its path while still out of reach is not dropped.**
  The hero stands and faces it instead. Giving up would re-acquire the same
  target on the next tick and flap; the player can always issue another order.
  Only reachable through a navmesh clamp that lands the goal somewhere
  unreachable, so it is rare rather than fixed.
- **Damage and death (issue #7).** `take_damage(amount)` forwards to the
  `Health` child — attackers call this and never touch the component, which
  leaves room for armour or hit reactions later. On `Health.died` the hero sets
  `_dead`, drops every order, and emits `died`; while dead he ignores input and
  holds position (gravity still runs). `is_dead()` is public so a zombie stops
  swinging at a corpse.

## Dependencies

- Requires a baked navmesh in the scene it's placed in (`scenes/main.gd`
  bakes at runtime) and a current `Camera3D` for the click raycast. The
  navmesh clamp reads `get_world_3d().navigation_map`, so orders issued before
  the first bake resolve to the hero's own position.
- Emits `move_ordered(world_point)` (move *and* attack-move) and
  `attack_ordered(target)` — neither is consumed yet; they exist for the
  selection UI in issue #36. Emits `killed(victim)`, the XP hook for issue #8,
  fired from the swing that lands the killing blow so attribution is exact
  rather than "something died". Emits `attack_move_armed_changed(armed)`, which
  `scenes/main.gd` consumes to show the armed-attack indicator, and `died`,
  which `scenes/main.gd` consumes to restart the run. Consumes `Health.died`
  from its own child.
- Damages and is damaged by `scenes/enemies/zombie.gd`, which finds him through
  the `hero` group.

<!-- verified-against: 46564b4 -->
