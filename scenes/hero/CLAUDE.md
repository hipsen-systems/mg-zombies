---
depends-on: [scenes, scenes/components, scenes/enemies, scenes/map, scenes/ui, assets]
---

# scenes/hero/

The player-controlled hero (issue #5: movement; issue #7: taking damage and
dying; issue #11: his own attack; issue #38: coming back from a death; issue #8:
levelling up and spending what a level pays).

- `hero.tscn` — `CharacterBody3D` (collision layer 3, mask 1|2 — see the
  layer table in `scenes/CLAUDE.md`) with a placeholder capsule + a small
  "nose" box marking the facing direction **under a `Visual` node**, a
  `CollisionShape3D`, a `NavigationAgent3D`, a `Health` child (100 HP,
  `scenes/components/`) and an `Experience` child from the same folder. In the
  `hero` group — that is how zombies find him,
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
| Left-click alone (`select_command`) | select it | select the hero back |
| `A` again, or `Escape` (`cancel_command`) | disarms `A` | disarms `A` |
| `1` / `2` (`skill_strength` / `skill_health`) | buys a rank — see Skills | buys a rank — see Skills |

**`1` and `2` are the only inputs here that are not commands**, which is why the
last row reads the same on both sides: they spend a point and touch nothing
about what the hero is doing. In particular they do **not** disarm `A` and do
not cancel an order — a player banking a level mid-fight keeps the fight.

`A` toggles rather than latching, and a right-click also disarms it, so there
are three ways out of the armed state and none of them requires knowing which.

**Left-click is deliberately never an attack.** An RTS where inspecting a unit
also swings at it is unusable, so the button is reserved for selection. `A`
borrows it for exactly one click and hands it straight back.

**This script owns the button, but not what a bare click means.** It emits
`select_clicked(screen_point)` for every left-click the armed attack command did
*not* take, and `scenes/ui/` turns that into a selection. Handing the click on
rather than letting the selection code read the mouse itself keeps one owner on
the button: two nodes both watching `select_command` would have to agree about
the armed state *mid-event* — this script disarms `A` while handling the very
click that used it — so an armed click would land as both an attack and a
selection, or as neither, depending on which node `_unhandled_input` reached
first.

Public order API — future AI, skills and tests should call these rather than
poking the `NavigationAgent3D`: `command_move_to(point)`,
`command_attack(target)`, `command_attack_move(point)`, `command_stop()`.
Each cancels the previous order outright: the agent repaths and horizontal
velocity is zeroed so the hero can't coast a frame along the abandoned heading.

`respawn_at(point)` is the one method outside that set that moves him, and it is
not an order — see below.

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

**Automatic acquisition requires line of sight; clicking does not.** Both are
deliberate and they are not the same question. A raycast against walls stops the
hero picking up a target through solid rock and walking off to fight something
the player never saw — the complaint `scenes/enemies/` records in reverse, and
worse here, because this is the unit the player is meant to be commanding. The
click paths skip the check because the player can only click what is already
drawn on screen; a second opinion from a raycast could only reject clicks that
were visibly valid. Note the consequence that *is* kept: once a target is
acquired in sight, the hero will pursue it around a corner. That is ordinary RTS
behaviour and the player can always issue another order.

Acquisition and repathing run on a 0.2 s tick (`RETARGET_INTERVAL`), matching
the sensing budget in `scenes/enemies/`. Only the cooldown, gravity and
movement need per-frame precision.

## Stats

All exports, not constants, because the skill tree (issue #9) will want to
modify them and a `const` is not a seam. **There is still deliberately no stat
or modifier system** — no modifier objects, no sources, no stacking rules. Issue
#8 needed exactly two stats to move and does it by recomputing each from a base
value plus a rank (see Skills below), which is small enough to delete. That was
the whole reason this section said "none yet" for so long: issue #9 owns the
model, and a placeholder that could survive it would prejudge it.

| Export | Default | Note |
|--------|---------|------|
| `move_speed` | 6.0 | Faster than any zombie, on purpose |
| `attack_range` | 2.2 | Slightly out-reaches the zombie's 2.0 |
| `attack_damage` | 12.0 | 3 swings kill a 30 HP zombie |
| `attack_cooldown` | 0.9 | Attack speed, expressed as the zombie's is |
| `acquire_radius` | 9.0 | Under the zombie's 12 detection: he is noticed first |
| `regen_delay` / `regen_per_second` | 5.0 / 4.0 | See below |
| `display_name` | `"Hero"` | What the unit info bar calls him |
| `strength_damage_per_rank` / `health_per_rank` | 2.0 / 10.0 | What one rank of each skill buys |
| `skill_max_rank` | 5 | Ranks available in each skill |

`unit_info()` reports the name plus damage, cooldown and move speed for that
bar. Display-only, and the hero picks *which* of his numbers is the interesting
one — see the contract in `scenes/ui/CLAUDE.md`.

Measured 1v1 against one zombie: ~18 HP lost per kill, ~6 s of fighting.

**The end boss inverts the reach advantage deliberately** (issue #39): its 3.0
beats his 2.2, where every zombie's 2.0 loses to it. So the row above is a
baseline meant to be broken by one encounter rather than a rule about all of
them — standing and trading is a fair fight against a zombie and a lost one
against the boss, which is the entire difference between the two.
`scenes/enemies/` holds those numbers and the reasoning.

**Out-of-combat regeneration** starts `regen_delay` after the last combat
event, where *both* taking a hit and landing one count — a hero trading blows
never regenerates mid-fight. It was written for issue #38, and #38 has now
landed: without it, clearing a fight at low health makes the next one unwinnable
and the only remaining move is to die on purpose, which is a miserable way to
use a checkpoint. It is what stops the respawn below being the healing mechanic.

**The gate is time only, where the zombie's is time *and* state.** That
asymmetry is deliberate, not an oversight — cross-review raised it. A chasing
zombie is in an ongoing fight it is losing, so healing mid-chase would undo
damage the player already landed. A hero walking toward a target that has not
noticed him is not in a fight at all, and the clock runs on him exactly as it
would if he stood still for the same seconds. Note this is reachable today, not
just in theory: an attack order has no range limit, so a long approach across
the map easily outlasts `regen_delay`.

What would change the answer is a stat that makes the *approach* part of the
fight — a ranged attacker, or anything that lets an enemy hurt him on the way
in. Issue #9 should re-read this paragraph before it starts moving these
numbers.

## Skills (issue #8)

Two skills, bought with the points an `Experience` level pays out. `1` buys a
rank of Strength (`+2` damage), `2` buys a rank of Health (`+10` max HP), five
ranks each.

**This is the smallest thing that proves the level-up hook has a consumer, and
it is not the skill tree.** Two entries in a `const SKILLS` table, a rank
counter, and `_apply_skills()` recomputing two stats from base + rank. **Issue
#9 should delete it, not extend it** — the whole reason this folder carried no
stat system until now was to avoid prejudging that issue, and a placeholder
worth keeping would prejudge it just as effectively as a real one.

Three things about it are decisions rather than defaults:

- **Stats are recomputed, never accumulated.** `_apply_skills()` sets
  `attack_damage` to base + ranks every time, so it is idempotent and cannot
  drift; adding the bonus to the live value on each purchase would go wrong the
  first time anything else ever wrote to that stat. The bases are captured in
  `_ready()`, which is what makes the export values still mean "the hero as
  authored".
- **The ledger is here and the arithmetic is not.** `Experience`
  (`scenes/components/`) counts XP, levels and points and never touches a stat;
  this folder decides what a point buys. That split is what keeps the component
  actor-agnostic, and it is the same seam issue #9 will need.
- **`spend_skill_point()` refuses silently** — for an unknown skill, a maxed
  rank, or an empty pool — and returns whether it bought anything. The HUD
  already shows `0 points`, and there is nothing a player can do about it but go
  and kill something. Note the ordering inside it: the rank cap is checked
  *before* `Experience.spend()`, because spending first would mean handing a
  point back.

`skill_summary()` reports the skills, ranks and effect text for the HUD, for the
same reason `unit_info()` reports the stats: what a rank *does* is a fact about
this actor, and a panel that formatted it would have to be edited for every new
skill. See the contract in `scenes/ui/CLAUDE.md`.

**A level pays points and raises nothing by itself.** That rule is the game's,
not this folder's — it lives in the root `CLAUDE.md` — and this is the folder
that could break it silently, since it owns every stat a level might be tempted
to touch. `tests/smoke_progression.gd` asserts it directly.

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
- **A click fires two rays, and they disagree about walls on purpose.** The
  ground ray ignores them, so clicking a wall means the floor behind it (issue
  #5). The enemy ray includes them, so clicking a wall never means the zombie
  behind it. One combined query cannot hold both rules, and the floor under a
  zombie's feet would sometimes win it anyway.
- **The enemy ray was not always occlusion-aware, and the bug it caused is the
  one to remember.** Masked on enemies alone it tunnelled straight through
  rock: clicking a wall with a zombie behind it issued an *attack order* on a
  zombie the player had never seen, and the hero walked off to fight it. Note
  this is the mirror image of the click-slack rationale below — that one worries
  about rejecting a visible enemy, this one silently accepted an invisible one,
  and the doc claimed the first covered the second. Cross-review caught it.
  It is not a general occlusion solve: rock caps carry no collider by design
  (`scenes/map/CLAUDE.md`), so what stops the ray is the wall pieces bounding
  the rock, which sit on every rock/floor boundary at full height. A ray
  threading the corner gap where two meet would still get through.
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
  change here — **issue #39's boss proved that rather than assumed it**: a whole
  new scene, ten different stats, and not a line in this folder — but the group
  name and those two methods are a real runtime contract, which is why
  `scenes/enemies` is declared in the frontmatter above.
  A missing edge would be invisible; renaming the group would break the hero
  with nothing to catch it.
- **Every range test measures horizontally, through `_horizontal_distance_to`.**
  Both the repath check and the swing check call it, so they are one code path
  and cannot disagree at the boundary — a hero counting the height difference in
  one and not the other would repath and swing on alternate ticks. The floor is
  flat today, so nothing would show it; the first ramp would. Cross-review
  caught the first attempt at this: the two computations *matched* but were
  written twice, so the guarantee this doc claimed did not actually exist. If
  you add a third range test, route it through the helper too.
- **The hero uses two ray masks of his own**, and both are new consumers of
  layers no *body* of his masks: layer 4 for attack targeting and layer 2 for
  line of sight. See the table in `scenes/CLAUDE.md` — a query mask and a body's
  `collision_mask` answer different questions, and only the first applies here.
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
- **Death is no longer terminal (issue #38).** `respawn_at(point)` revives him
  in place rather than reloading the scene, because the run around him survives:
  everything cleared behind the armed checkpoint stays cleared. So `died` now
  fires once per *death*, not once per run, and every piece of state a death
  leaves behind has to be undone in one place — the death flag, the orders, the
  armed attack command, the carried velocity, and the three timers.
  `Health.revive()` is called last, so `health_changed` reaches the HUD with the
  hero already alive and standing where he belongs.

  **A death costs no progression**, and `respawn_at()` needed no line to make
  that true: XP, level, points and ranks live on the `Experience` child and in
  the rank ledger, neither of which a respawn touches. `Health.revive()` fills
  him to whatever ceiling his Health ranks have bought, because
  `set_max_health()` moved the ceiling itself rather than adding a bonus on top
  of it. Discarding a run's progression is a *restart*, and that is a scene
  reload owned by `scenes/main.gd` — see the asymmetry it documents.

  Two pieces of that are easy to miss. **The nav agent's target**, which nothing
  else clears — leave it and the first order of the new life is judged finished
  or not against a destination from the previous one. And **the timers**, which
  are frozen rather than running while he is dead, because `_physics_process`
  returns above the line that decrements them. They count *down*, so a residual
  is a *delay*: dying mid-cooldown and keeping the value would make his first
  swing of the new life wait out the remainder of his last one. Clearing them
  stops that leak; it does not hold him back, it does the reverse.

  **`died` is not a promise of a `respawn_at()`.** Since issue #39 a run can be
  won, and `scenes/main.gd` ignores a death arriving after the boss has fallen —
  the hero stays down where he lies while the victory screen comes up and the
  tree freezes. Nothing in here needs to know that and nothing in here should:
  this folder reports the death, and the scene decides what it costs.

  **What stops him swinging the instant he arrives is not in this folder**, and
  that is the second claim here resting on `scenes/map/` — the rock caps above
  are the first, which is why it is in the frontmatter. It
  is `scenes/map/`'s rule that nothing a respawn *restores* stands within 4 cells
  of the cell it puts him on — 16 units, well outside `acquire_radius` (9) — so
  there is nothing to acquire on the frame he comes back. That is the invariant
  to re-check if a checkpoint is ever placed with less clearance, or if issue #9
  grows these radii. Cross-review caught this stated backwards: the code was
  right and the reason attached to it was inverted, which is the same failure the
  doc lesson on #36 records.

  **Restored is the load-bearing word, and it was missing here until issue
  #54.** The rule reads as covering every placement on the map, and that version
  is false: one zombie stands 3 cells from the boss gate. It is behind the gate,
  in an earlier segment, so a respawn there does not put it back — which is why
  the invariant above survives unchanged. What it does not promise is the frame
  *after*: a zombie the player walked past is still standing wherever it was
  left, and at 12 units it is exactly on its own detection radius while he
  cannot answer until 9. Being charged a second later is a fight; being swung at
  on arrival is what this rule prevents.

## Dependencies

- Requires a baked navmesh in the scene it's placed in (`scenes/main.gd`
  bakes at runtime) and a current `Camera3D` for the click raycast. The
  navmesh clamp reads `get_world_3d().navigation_map`, so orders issued before
  the first bake resolve to the hero's own position.
- Emits `select_clicked(screen_point)` for a bare left-click, consumed by
  `scenes/ui/` (via `scenes/main.gd`) as a selection.
- Emits `move_ordered(world_point)` (move *and* attack-move) and
  `attack_ordered(target)` — still unconsumed. This doc used to say they existed
  for the selection UI in issue #36; that turned out to be wrong, because
  selection is deliberately inert and reads nothing about what the hero is
  doing. They now have no planned consumer.
  Emits `killed(victim)`, **consumed by `scenes/main.gd` since issue #8** after
  being emitted and dropped since #11. It fires from the swing that lands the
  killing blow, so attribution is exact rather than "something died" — which is
  why it won the XP hook over `Zombie.died`, a signal any source of damage would
  trigger. Emits `attack_move_armed_changed(armed)`, which
  `scenes/main.gd` consumes to show the armed-attack indicator, and `died`,
  which `scenes/main.gd` answers with `respawn_at()` at the armed checkpoint.
  Emits `skill_ranked_up(skill, rank)` **after** the stat it bought has been
  applied, so a listener reads the new numbers rather than the old ones.
  Consumes `Health.died` from its own child, and calls `Health.revive()` on the
  way back.
- **`gain_experience(amount)` is the XP entry point**, and it exists so that
  `scenes/main.gd` never reaches into the `Experience` child — the same
  convention `take_damage()` follows for `Health`, and the same seam that lets
  the hero react to a level later without every caller learning about it. It
  deliberately has *no* `_dead` guard where `take_damage()` does: refusing damage
  to a corpse is the rule, but refusing credit to one would swallow a kill that
  lands after he falls. Nothing produces one today; the first damage-over-time
  effect can, and losing XP is the worse direction to be wrong in.
  `spend_skill_point()` calls `Experience.spend()` the same way.
- Damages and is damaged by `scenes/enemies/zombie.gd`, which finds him through
  the `hero` group.

<!-- verified-against: 4a0d146 -->
