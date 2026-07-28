# scenes/components/

Small reusable pieces that get added as child nodes of an actor, rather than
inherited or copy-pasted. Nothing in here knows about a specific actor.

- `health.gd` (`class_name Health`) — hit points. Added as a `Node` child of
  `hero.tscn` (100 HP) and `zombie.tscn` (30 HP).
  - `@export var max_health`; `current` is set from it in `_ready()`.
  - `take_damage(amount)` / `heal(amount)` / `is_dead()`.
  - Signals: `health_changed(current, maximum)` — emitted on damage *and*
    healing, carrying both numbers so a HUD never has to reach back into the
    node — and `died`, emitted exactly once when health first reaches zero.
  - Damage and healing on a dead component are ignored. Healing a corpse would
    silently revive it; resurrection should be an explicit decision, not a side
    effect of a heal.

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
`scenes/hero/` and `scenes/enemies/`; `scenes/main.gd` connects to the hero's
`health_changed` to drive the HUD bar.
