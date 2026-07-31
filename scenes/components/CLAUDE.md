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

## Convention

**Owners expose their own `take_damage()` that forwards here.** `Hero` and
`Zombie` both do. An attacker calls `victim.take_damage(n)` and never touches
the `Health` child, which leaves each actor free to react to a hit (armour,
stagger, waking an unaware zombie) without every attacker learning about it.

## Why a component

Two actors needed identical HP logic on day one, and the skill tree (issue #9)
will want one place to raise max health or apply damage modifiers. Splitting it
out now costs one node per actor and avoids two drifting copies.

## Dependencies

None — plain `Node`, no scene or autoload requirements. Consumed by
`scenes/hero/` and `scenes/enemies/`. Both signals are also read by `scenes/ui/`
— `health_changed` drives the hero's bar and the selected unit's, and `died`
tells `scenes/ui/` to drop a dying unit's selection rather than show a corpse.
(That folder subscribes at the selection layer, not in the bar itself.) It finds the
component by the `health` property on a unit, so the name is part of its
contract; this doc does not depend on it in return.

<!-- verified-against: 8a4044b -->
