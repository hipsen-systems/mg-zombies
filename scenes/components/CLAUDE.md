---
depends-on: []
---

# scenes/components/

Small reusable pieces that get added as child nodes of an actor, rather than
inherited or copy-pasted. Nothing in here knows about a specific actor.

- `health.gd` (`class_name Health`) — hit points. Added as a `Node` child of
  `hero.tscn` (100 HP) and `zombie.tscn` (30 HP).
  - `@export var max_health`; `current` is set from it in `_ready()`.
  - `take_damage(amount)` / `heal(amount)` / `revive()` / `is_dead()`.
  - Signals: `health_changed(current, maximum)` — emitted on damage *and*
    healing, carrying both numbers so a HUD never has to reach back into the
    node — and `died`, emitted when health reaches zero.
  - Damage and healing on a dead component are ignored. Healing a corpse would
    silently revive it; resurrection should be an explicit decision, not a side
    effect of a heal.
  - **`revive()` is that explicit decision** (issue #38's checkpoint respawn):
    full health, whatever the current value. Because it exists, `died` is
    once-per-*life* rather than once ever — repeated damage on a corpse still
    cannot re-fire it, but a revived owner killed again will. It deliberately
    emits nothing of its own beyond `health_changed`: whoever revives an owner
    is also moving it and clearing its death state, so a signal here would
    announce a half-finished resurrection.
  - **`set_max_health(value)` moves the ceiling** — the seam this doc predicted
    the skill tree would pull on, first pulled by issue #8's Health skill. **A
    raise heals by the same amount rather than diluting the bar**: buying +10 at
    40/100 leaves 50/110, not 40/110, because a point that visibly does nothing
    the moment it is spent reads as a point wasted. A lowering takes the ceiling
    with it and clamps. Like `heal()` it will not resurrect — a corpse keeps its
    zero however far the ceiling moves — and it emits `health_changed` even for
    one, since the maximum a bar is drawn from really did change.
- `experience.gd` (`class_name Experience`) — XP, levels, and the skill points a
  level pays out (issue #8). A `Node` child of `hero.tscn` and of nothing else
  so far.
  - `grant(amount)` / `spend(amount) -> bool` / `xp_to_next()` /
    `emit_current()`; `level`, `xp` and `skill_points` are readable state.
  - Signals: `xp_changed(current, needed, level)` — both numbers measured
    toward the *next* level rather than cumulatively, so a bar can be drawn
    without reaching back in, the same contract `health_changed` has —
    `leveled_up(level, points_awarded)`, and `points_changed(points)`.
  - **`leveled_up` is the hook the skill tree hangs off** (issue #9). It fires
    once per level *inside* the loop that awards them, so a listener sees each
    level it is being told about rather than the last of a batch — and the loop
    is not defensive coding: one kill crosses two thresholds as soon as a boss
    or an objective is worth more than a level.
  - **This node hands out points and never touches a stat.** That is its half of
    the game rule in the root `CLAUDE.md` — a level pays points and nothing else
    — and it is also what keeps the component actor-agnostic: deciding what a
    point *buys* needs to know which actor is spending it, so it belongs to
    whoever owns the stats. Today `scenes/hero/`; issue #9's data model after
    that.
  - **`spend()` refuses rather than reporting**, and returning the answer is the
    point of routing purchases through it: a caller that read `skill_points`,
    decided for itself and then decremented would work right up until two skills
    were bought in the same frame.
  - **There is deliberately no reset.** A run's progression is discarded by
    `scenes/main.gd` reloading the scene, and a death is explicitly *not* allowed
    to cost it — so the two callers a reset would have both want the opposite of
    one. Compare `revive()` above, which exists because `Health` genuinely has a
    caller that needs it.

## Convention

**Owners expose their own method that forwards here, and callers use that.**
`Hero` and `Zombie` both forward `take_damage()`; `Hero` forwards
`gain_experience()` in exactly the same shape. An attacker calls
`victim.take_damage(n)` and never touches the `Health` child, which leaves each
actor free to react to a hit (armour, stagger, waking an unaware zombie) without
every attacker learning about it — and the same seam is what lets a hero react
to a level later without `scenes/main.gd` being told.

**Reading is not writing, and only writing goes through the owner.** Both
`scenes/main.gd` and `scenes/ui/` connect to these components' signals directly,
which is fine: a signal is already the component announcing itself, and routing
it through the owner would only add a forwarding hop with nothing to decide. It
is the *mutation* that needs an owner in the path.

## Why a component

Two actors needed identical HP logic on day one, and the skill tree (issue #9)
will want one place to raise max health or apply damage modifiers. Splitting it
out now costs one node per actor and avoids two drifting copies.

**`Experience` is here on the weaker version of that argument, and it is worth
being honest about which.** Only the hero levels today, so it is not sharing
anything with a second actor the way `Health` was on day one. What it does share
is the shape: per-actor state with no opinion about which actor, reachable as a
named child, with the same signal-carries-both-numbers contract — so a levelling
ally or a rival that grows over a run needs no second copy of the arithmetic.
The test that kept it here rather than folding it into `scenes/hero/` is the one
this folder's opening line states: nothing in the file knows about a hero.

## Dependencies

None — both are plain `Node`s, with no scene or autoload requirements. `Health`
is consumed by `scenes/hero/` and `scenes/enemies/`; `Experience` by
`scenes/hero/` alone, with `scenes/main.gd` granting and the HUD drawing from its
signals. `Health`'s two signals are also read by `scenes/ui/` — `health_changed`
drives the hero's bar and the selected unit's, and `died` tells `scenes/ui/` to
drop a dying unit's selection rather than show a corpse. (That folder subscribes
at the selection layer, not in the bar itself.) Both components are found by a
named property on the unit — `health` and `experience` — so those names are part
of the contract; this doc does not depend on the folders using them in return.

<!-- verified-against: 8a4044b -->
