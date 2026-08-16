---
depends-on: [scenes/hero]
---

# scenes/skills/

The skill tree's data model (issue #9), and nothing that spends from it. Pure
`Resource`s: no node, no scene, no autoload, and no mention of a hero anywhere
in the folder's code.

| File | What it is |
|------|------------|
| `skill_tree.gd` (`class_name SkillTree`) | A whole tree: the nodes, the rules about them, and `validate()` |
| `skill_node.gd` (`class_name SkillNode`) | One buyable node — id, cost, ranks, prerequisites, effects |
| `skill_effect.gd` (`class_name SkillEffect`) | What a node *does*. Base class; see below |
| `stat_modifier.gd` (`class_name StatModifier`) | The only effect kind there is: move one of an actor's numbers |
| `default_tree.tres` | The tree the hero ships with — six nodes, 26 points for a full build |

**This folder is content; the ranks are not here.** A `SkillTree` holds no
ranks and no points, so one instance is shared by every actor that uses it and
every method takes the ranks it should reason about as an argument. The
`{id: rank}` ledger lives on whoever is spending — today `scenes/hero/`.

## The four decisions issue #9 was opened to make

**Cost, prerequisites and effects are authored per node** in a `.tres`, edited
in the inspector. `requires` is a plain `{skill id: minimum rank}` dictionary
rather than a resource per edge, because every prerequisite so far is "at least
this many ranks of that" and three files to express one number is not a model,
it is furniture. `cost_per_rank` is flat across a node's ranks: a rising cost is
a balance decision, and there is still nothing to balance against.

**Effects apply themselves to an actor; the actor does not interpret them.**
`SkillEffect.apply(actor, rank)` calls a tiny duck-typed surface —
`add_stat()`, `scale_stat()` — in the same spirit as the
`take_damage()`/`is_dead()` contract `scenes/hero/` already uses on enemies, and
for the same reason: this folder must not name the classes that consume it. The
alternative, an actor that switched on effect *kind*, grows a branch per
subclass in the one file that should not have to care.

So a behaviour grant — an ability, a passive that changes how an order resolves
— is a second `SkillEffect` subclass and changes nothing in the tree, the
ledger, or the fold. **That seam is the whole reason the base class exists**,
and it is worth being honest that it currently has exactly one implementation:
if behaviour grants never materialise, this collapses to one class and loses
nothing.

**The tree is validated, not trusted.** `SkillTree.validate()` returns one line
per structural fault: an id typed twice, a prerequisite naming a node that was
renamed, a required rank above what that node can reach, an effect that does
nothing, a prerequisite cycle. A `.tres` mistake otherwise produces a skill that
is quietly unbuyable, which reads in play as a balance problem and is not one.
`scenes/hero/` calls it at `_ready()` and pushes each fault as an error; `tests/`
asserts the shipped tree is clean **and that a deliberately broken one is not**.
Both halves are needed: a clean result on a good tree is also exactly what a
`validate()` that always returned nothing would produce, and cross-review of
PR #61 reported the cycle check as dead code precisely because nothing in the
suite could tell those apart. It was not dead — but the gap that made the claim
unfalsifiable was real, and it is closed by feeding it a cycle.

**What `validate()` structurally cannot check is a stat name**, because only the
actor owning the stats knows whether `attack_damge` is one. `stats_used()` is
the hook for that, and `scenes/hero/` answers it — see the constraint below.

**Saves and respec both reduce to the ledger.** `{id: rank}` is the entire
payload a save would need: the tree is content and reloads itself, and nothing
else about a build can be reconstructed. **Node ids are therefore a save-format
contract** — rename a `display_name` freely, retire an id rather than reuse it.
Respec is clearing the ledger and re-applying, which works because the fold
below recomputes from the authored values rather than accumulating onto live
ones. It is deliberately **not built**: what a respec costs and where it is
allowed is a game-design decision nobody has made, and shipping a free instant
one would make it by accident.

## The one stacking rule

Adds are summed against the actor's authored base, and only then are scales
multiplied in: `(base + Σadd) × Πscale`. That single sentence is the whole of
it, and it is what a modifier system with sources, priorities and stacking
categories would otherwise exist to answer.

Two things fall out of it. The order ranks are bought in cannot change the
result, so no purchase sequence is a better build than another by accident. And
`SCALE` is linear rather than compounding — three ranks of −8% is −24%, not
−22.1% — because a rank should be worth exactly what the rank before it was.

The fold itself lives with the actor, in `scenes/hero/`, because it is the only
thing that knows what a stat name means.

## What this folder asks of the rest of the project

- **An actor that uses a tree must provide `add_stat(stat, amount)` and
  `scale_stat(stat, factor)`**, and must recompute from authored bases rather
  than accumulating — `apply()` runs on every recompute, not once per purchase.
- **It must check `stats_used()` against the stats it accepts.** Stat names are
  strings; this is what makes a typo a load-time complaint rather than a point
  spent on nothing.
- **A tree must not sell away another actor's deliberate advantage.** The
  worked example is reach: the hero's 2.2 out-reaches every zombie's 2.0, and
  the end boss's 3.0 inverts that on purpose (`scenes/enemies/`). `reach` caps
  at +0.6, so a fully invested hero reaches 2.8 and the boss keeps its
  identity. `tests/smoke_skills.gd` asserts it rather than trusting this
  paragraph.
- **`acquire_radius` is deliberately not sellable at all**, and this is the
  sharper case because breaking it would break a rule stated in a different
  folder's file. `scenes/map/` guarantees 4 cells (16 units) between where a
  respawn puts the hero and anything it restores, and that clearance is measured
  against his 9-unit acquisition radius. A skill growing it past 16 would land
  him back in a fight on the frame he returns. If it should ever be buyable, the
  clearance is the thing to change first. Also asserted.

## Gotchas

- **`default_tree.tres` was generated by a throwaway script, not typed by
  hand**, because Godot's text form for a script-typed array is
  `Array[ExtResource("…")](…)` and guessing it wrong is a resource that loads as
  garbage rather than an error. It is authored in the inspector from here; if a
  wholesale rewrite is ever wanted again, build it with `ResourceSaver.save()`
  rather than editing the text.
- **`describe()` reports what a rank *has* bought, so it is empty at rank 0.**
  A panel that wants to advertise what the *next* rank would buy should ask for
  rank + 1 rather than expecting this to guess which it meant.
- **The tree is larger than the keyboard**, and `scenes/hero/` holds the two
  temporary key bindings. The other four nodes became buyable in issue #62, from
  a panel in `scenes/ui/` rather than from more hotkeys.
- Nodes carry no position and no hotkey. Where one is drawn belongs to the panel
  drawing it; which key buys it belongs to whoever owns the control scheme. A
  tree that knew either could not be shared with a second actor.
- **`depth(id)` is the one concession to a panel, and it is not a position.** It
  reports how deep in the prerequisite chain a node sits — 0 for one that is open
  from the start — which is a fact about this graph and stays true however it is
  drawn. Whether a panel turns depths into rows, columns or rings is entirely its
  business, and two panels may disagree; what neither should do is re-derive the
  structure from `requires` itself. It is cycle-safe rather than trusting
  `validate()`, because it runs on every redraw and a malformed `.tres` must not
  take the screen down with it.

## Dependencies

Nothing here loads or names anything else in the project — the code is four
plain `Resource` scripts. The declared edge on `scenes/hero/` is about the
*content*: `default_tree.tres` names that hero's stats (`attack_damage`,
`attack_range`, `attack_cooldown`, `move_speed`, `regen_per_second`,
`max_health`), so renaming one there is what would make this folder wrong.

`scenes/hero/` is the only consumer today: it owns the ledger, the fold, and the
key bindings. `tests/smoke_skills.gd` drives the tree through him.

<!-- verified-against: d5fb938 -->
