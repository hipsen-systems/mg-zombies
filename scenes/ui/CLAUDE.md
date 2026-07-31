---
depends-on: [scenes, scenes/hero, scenes/enemies, scenes/components, scenes/map]
---

# scenes/ui/

Everything drawn over the game, plus unit selection (issue #36). Split out of
`scenes/main.gd`, which drove four Labels inline until the info bar made that
five elements and one of them non-trivial.

- `hud.tscn` / `hud.gd` (`class_name HUD`) — the `CanvasLayer`. Holds the hero's
  health bar (bottom-left), the armed-attack indicator, the controls crib sheet
  (top-left), the death screen, the checkpoint confirmation, and an instance of
  the info bar.
- `unit_info_bar.tscn` / `unit_info_bar.gd` (`class_name UnitInfoBar`) — the
  bottom-centre panel: name, live HP as `current / max`, and damage / attack
  speed / move speed.
- `unit_selection.tscn` / `unit_selection.gd` (`class_name UnitSelection`) — a
  `Node3D` in `main.tscn` holding the selection ring. Owns *what* is selected;
  the HUD only draws it.

**Every element is fed by a method call.** `scenes/main.gd` wires the hero's
signals to `HUD` methods and never touches a Label, so this folder can re-lay
out the screen without a gameplay script changing with it. Keep that direction:
nothing here should be reachable by node path from outside.

## Selection is inert, and that is the feature

It issues no orders, deals no damage, and **no gameplay script reads it** —
`scenes/hero/` never learns what is selected. An RTS where inspecting a unit
also swings at it is unusable, so a player can read an enemy's numbers with a
fight already under way and nothing about the fight changes.

The hero is selected at startup and selection falls back to him from everything
else: a click on ground, sky, a wall or a corpse, and the death of whatever was
selected. There is deliberately no "nothing selected" state — an empty panel is
dead screen space.

The hero's *own* death is the exception, and it stays that way: the panel holds
on him, reads 0 through the death screen, and fills again when `scenes/main.gd`
revives him. It used to be an exception because there was nothing to fall back
to and the run was about to reload; it is now also the right answer.

## The unit contract

Duck-typed, exactly as `scenes/hero/` treats enemies. Anything selectable
provides:

| Member | Used for |
|--------|----------|
| `unit_info() -> Dictionary` | `name`, `damage`, `attack_cooldown`, `move_speed` |
| a `Health` child (`scenes/components/`) | the HP bar, and the death fallback |
| `is_dead()` | refusing to select a corpse |

No class is named here, so a boss or a second enemy type needs no change in this
folder — but the three above are a real runtime contract, which is why
`scenes/hero` and `scenes/enemies` are in the frontmatter.

**A unit reports its own numbers rather than the panel reaching in for named
properties**, because the property that matters differs per actor: the hero's
travel speed is his `move_speed`, a zombie's is its *chase* speed, and only they
know which of theirs is worth showing. Missing keys render as a dash rather than
failing, so a partial reporter is safe.

## The hero owns the left mouse button, not this folder

`scenes/hero/` owns the command scheme the button belongs to, decides whether
the armed attack command borrowed a click, and emits `select_clicked` for the
ones it did not take. `UnitSelection.select_at()` consumes that.

**Do not add a second `select_command` listener here.** Two nodes on one button
would have to agree about the armed state *mid-event* — the hero disarms `A`
while handling the very click that used it — so an armed click would land as
both an attack and a selection, or as neither, depending on which node
`_unhandled_input` reached first.

## Gotchas

- **The ring is cyan and orange, not the RTS-classic green and red**, and that
  is a constraint from `scenes/map/`: it paints the start cell green and the
  boss cell red as floor markers. A green ring is invisible on the green start
  marker — where the hero stands for the first seconds of every run, exactly
  when the player is working out that the ring means something — and a red ring
  would vanish the same way once issue #39 puts something selectable on the boss
  cell. If those markers are recoloured, re-check these.
- **The ring's material is duplicated in `_ready()`**, for the reason
  `scenes/enemies/` records: a scene's sub-resources are shared between
  instances and this one is recoloured at runtime. One ring exists today; the
  failure mode if that stops being true is silent.
- **The ring is repositioned on selection *and* every frame.** Leaving it to the
  next `_process` spends one frame drawn around the previous unit — which is the
  frame the player is looking at it.
- **The selection ray has no grace radius**, unlike the attack click's
  `CLICK_SLACK` in `scenes/hero/`. Missing an attack is expensive (the order
  silently becomes a walk into a pack); missing a selection just falls back to
  the hero, one click to undo. Slack here would instead break that escape hatch:
  clicking the floor beside a zombie to get back to the hero would keep
  selecting the zombie.
- **The ray masks walls along with units**, so a unit behind rock cannot be
  clicked through it — the same rule and the same reason as the hero's
  attack-targeting ray.
- **The hero's own health bar stays even though the info bar shows his HP when
  he is selected.** It is not a duplicate but the case the panel cannot cover:
  while an enemy is selected the panel shows the *enemy's* health, and a player
  who cannot see their own mid-fight is worse off than one looking at a
  redundant bar.
- **The death screen has to come back off** now that a death is a respawn rather
  than a scene reload (issue #38), which is what `hide_death()` is for. Nothing
  else here survived being permanent.
- **A unit can now leave the level without dying**, and that broke an assumption
  this folder had held since #36. `scenes/main.gd` *removes* the zombies ahead
  of a checkpoint on respawn, so `UnitSelection` can be watching a `Health` that
  is freed rather than merely dead — a reference that is non-null and unusable
  at once. `_stop_watching()` therefore tests `is_instance_valid`, not `!= null`.
  Anything else here that holds a unit between frames has the same problem.
- **`flash_checkpoint()` is the second half of the checkpoint feedback, not the
  whole of it.** The lit pad in the world is the lasting signal and this is the
  transient one, for a player watching the fight rather than the floor they just
  crossed. Both exist because either alone is missable: pads sit at the edge of
  a one-cell tunnel where the camera barely sees them.
- `%g` does not exist in GDScript format strings, hence the by-hand trim of a
  trailing `.0` in the stat numbers.

## Dependencies / signals

- Instanced by `scenes/main.tscn`; `UnitSelection.hero` is wired from there as a
  `NodePath`, the way the camera's `target` is.
- Consumes `Hero.select_clicked`, and `Health.health_changed` / `Health.died` on
  whatever is selected. `scenes/main.gd` also calls `set_hero_health()`,
  `set_attack_move_armed()`, `show_death()` / `hide_death()` and
  `flash_checkpoint()` — the last from `Checkpoint.reached`, the only HUD call
  that does not originate with the hero.
- **`scenes/main.gd` re-selects the hero on every respawn**, before it clears
  the restored segment. That ordering is its concern, not this folder's, but it
  is the reason a freed selection is rare rather than routine — the
  `is_instance_valid` guard above is what makes it merely rare and not fatal.
- Emits `UnitSelection.selection_changed(unit)`, consumed by `HUD` only.
- **Order matters at startup:** `scenes/main.gd` connects `selection_changed`
  *before* calling `select_unit(hero)`, because the info bar learns the initial
  selection from that signal and nothing re-sends it.

<!-- verified-against: a5a431e -->
