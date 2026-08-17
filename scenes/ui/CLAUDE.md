---
depends-on: [scenes, scenes/hero, scenes/enemies, scenes/components, scenes/map, scenes/skills]
---

# scenes/ui/

Everything drawn over the game, plus unit selection (issue #36). Split out of
`scenes/main.gd`, which drove four Labels inline until the info bar made that
five elements and one of them non-trivial.

- `hud.tscn` / `hud.gd` (`class_name HUD`) — the `CanvasLayer`. Holds the hero's
  health bar (bottom-left), the XP bar and skill line stacked above it (issue
  #8), the armed-attack indicator, the controls crib sheet (top-left), the death
  screen, the checkpoint and level-up banners, the victory panel (issue #39), and
  an instance of the info bar.
- `unit_info_bar.tscn` / `unit_info_bar.gd` (`class_name UnitInfoBar`) — the
  bottom-centre panel: name, live HP as `current / max`, and damage / attack
  speed / move speed.
- `unit_selection.tscn` / `unit_selection.gd` (`class_name UnitSelection`) — a
  `Node3D` in `main.tscn` holding the selection ring. Owns *what* is selected;
  the HUD only draws it.
- `skill_panel.tscn` / `skill_panel.gd` (`class_name SkillPanel`) — the skill
  tree as something clickable (issue #62), instanced inside `hud.tscn`. See
  below.

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
| `stats_changed` *(optional)* | redrawing the stats row when a number moves |

No class is named here, so a boss or a second enemy type needs no change in this
folder — but the three above are a real runtime contract, which is why
`scenes/hero` and `scenes/enemies` are in the frontmatter.

**`scenes/skills` is in it for a weaker reason, and the difference is worth
knowing.** No script here loads, names or imports anything from that folder — the
skill panel reads plain dictionaries. What rests on it is a *claim* in this doc:
that the panel's rows are prerequisite depth and that its refusal text is the
tree's own words. Change what `SkillTree.depth()` means and no code here breaks
while this doc quietly stops being true, which is precisely the drift the edge
exists to flag.

**A unit reports its own numbers rather than the panel reaching in for named
properties**, because the property that matters differs per actor: the hero's
travel speed is his `move_speed`, a zombie's is its *chase* speed, and only they
know which of theirs is worth showing. Missing keys render as a dash rather than
failing, so a partial reporter is safe.

**The fourth member is optional, and the reason it exists is worth keeping**
(issue #65). `unit_info()` is a *snapshot*, and this folder had no way to notice
one going stale: the row was drawn once when a unit was selected, so buying a
rank of Strength left the old damage on screen until the player selected
something else and came back. The HP bar never had the bug, because it was
subscribed to `Health.health_changed` all along — `stats_changed` is that same
arrangement for the rest of the row, subscribed to while a unit is shown and
dropped when the selection moves on.

Optional rather than required, on the folder's existing habit of degrading:
nothing about a zombie's numbers moves today, and a unit that never emits is one
whose row never needs redrawing — which is exactly the old behaviour, so a unit
without it is no worse off than every unit was before. **What the option costs is
that a future actor whose stats move and which forgets to emit is silently
wrong**, and it looks like a balance bug rather than a UI one. That is the same
trade the missing-keys dash makes, and it is why the constant naming the signal
is written once in `unit_info_bar.gd` rather than three times.

## The hero owns the left mouse button, not this folder

`scenes/hero/` owns the command scheme the button belongs to, decides whether
the armed attack command borrowed a click, and emits `select_clicked` for the
ones it did not take. `UnitSelection.select_at()` consumes that.

**Do not add a second `select_command` listener here.** Two nodes on one button
would have to agree about the armed state *mid-event* — the hero disarms `A`
while handling the very click that used it — so an armed click would land as
both an attack and a selection, or as neither, depending on which node
`_unhandled_input` reached first.

## Progression readout (issue #8)

Three elements, all in the bottom-left stack under the health bar's rules —
fed by method call, never reached into:

- **`set_experience(current, needed, level)`** draws the XP bar and the `Lv N`
  beside it. Both numbers are measured toward the *next* level rather than
  cumulatively over the run, which is what a bar can actually draw; that is the
  same contract `health_changed` has, and it is the component's decision, not
  this folder's.
- **`set_skills(points, skills)`** draws the one-line skill list. It **formats
  and never interprets**: `skills` is what the unit reports about itself through
  `Hero.skill_summary()`, effect strings included, for the same reason
  `unit_info()` exists — what a rank buys is a fact about the hero, and a panel
  that knew it would need editing for every new skill. The line turns gold while
  points are unspent, because the count is the only part that changes what a
  keypress does.
  **It is a crib sheet for the keys, not a view of the skill tree**, and issue
  #9 is where those stopped being the same list: the hero has an authored tree
  larger than the two keys bound to it, and `skill_summary()` reports the bound
  ones. Issue #62 drew the rest, and did it as **a new element rather than a
  longer line** — six entries do not fit on one. The two are fed from different
  reports (`skill_summary()` and `skill_catalogue()`) and refreshed together,
  because both move on the same two events.
- **`flash_level_up(level, points)`** is the transient half, and it exists for
  the same reason `flash_checkpoint()` does: the bar below already says it, and
  a bar does not *reach* a player mid-fight — which is exactly when the kill that
  levelled them happened.

**The two banners share one implementation and not one tween.** `_flash()` and
`_clear_flash()` keep a tween per label in a dictionary, because arming a
checkpoint and levelling on the same kill is ordinary rather than a corner case;
a single shared tween would leave one banner half-faded. They sit on separate
lines so both are legible at once. `_clear_flashes()` takes both down, and the
death and victory screens call it for the reason recorded below — with the
level-up banner the more likely of the two to be up, since the kill that levels
the hero is often the one that leaves him low, and the boss is worth enough XP
that the winning blow frequently levels him outright.

## The skill panel (issue #62)

`K` opens the tree, `K` or `Escape` closes it, and every node is a card with a
button. Issue #9 shipped the tree with no UI, which left four of its six nodes
with **no way to be bought in play at all** — `1` and `2` reach two of them.
Four more hotkeys would have been a worse answer than none.

**It formats and never interprets**, which is the same rule the skill line keeps
and is worth restating because this panel is much more tempting to break. Every
number and sentence on a card arrives ready to print from
`Hero.skill_catalogue()`: the cost, the rank, the description, what the next rank
would buy, and *why* a node cannot be bought — that last one is
`SkillTree.refusal()`'s own words, so "Reach needs Strength 3" is game content
rather than a string built here. Nothing in this folder knows what a rank does.
**A new skill in the `.tres` therefore appears here with no edit to this folder**,
which is the test of whether the split is real.

**The layout is derived, not authored.** Cards are grouped into rows by
`SkillTree.depth()` — prerequisite depth, not a position. A node still carries no
coordinates, so the alternative was a position per node stored *here* and edited
every time game content gained a skill. Two things follow: an empty tier draws no
row (the depths present are read off the data, not assumed to run 0..n), and a
`depth()` that returned a constant would silently collapse the tree into one row,
which is why `tests/` asserts more than one tier exists.

**It rebuilds outright on every redraw** rather than patching cards in place.
Redraws happen when a point is earned or spent — never per frame — and a rebuilt
panel cannot show a rank that was refunded or a refusal that has since been met.
Note `queue_free()` alone is not enough: it frees at the end of the frame, so the
rows are also `remove_child`ed immediately or a redraw in the same frame stacks
the new rows under the old.

**Three things it does not own**, all for reasons this folder already records
elsewhere:

- **It does not buy anything.** `rank_up_requested` goes out through
  `HUD.skill_rank_up_requested` to `scenes/main.gd`, which calls the hero. Same
  arrangement as `restart_requested`: this folder does not own the points, the
  ledger or the rules, and a widget that spent them would be a second owner of
  all three.
- **It does not pause the game**, though the game *is* paused while it is up.
  `skill_panel_toggled(open)` reports; `scenes/main.gd` sets `get_tree().paused`,
  because that flag lives on the `SceneTree` rather than the scene and needs
  exactly one owner — the same argument the victory panel makes.
- **It does not decide when it is unavailable.** Two callers retire it, and they
  fire at different moments on purpose. `show_victory()` does, which is this
  folder keeping "the victory panel owns the screen" true from the inside — a
  skill panel openable behind a won run would also *unpause* it on the way out.
  And `retire_skill_panel()` does, called by `scenes/main.gd` the instant the boss
  falls, **~1.2 s before the screen appears**. That gap is why the second exists:
  the run is decided when the boss dies, and from that moment that script stops
  touching the pause flag, so a panel opened during the beat would come up over a
  level still running and freeze nothing. Cross-review of PR #62 found it. The
  freeze below is stated without an exception, and this is what keeps that honest
  rather than nearly true.

**It carries `PROCESS_MODE_ALWAYS` for the reason the victory panel does**, and
needs it twice over: a paused node receives neither input nor GUI dispatch, so
without it the panel could neither close itself nor answer a click on its own
buttons.

**This folder reads exactly one input action, and it is the first one anywhere
outside `scenes/hero/`.** That folder owns every other action because every other
action is a command to a unit; opening a panel issues no order and changes
nothing about what the hero is doing. It does not break the left-mouse-button
rule above either — a keyboard action nothing else claims is not a second
listener on `select_command`. `Escape` is deliberately shared with the hero's
`cancel_command`: the panel consumes the event when it is open, so closing it
does not also disarm an attack in the game behind it.

**Banners come down when it opens.** The death and victory screens already do
this, and the skill panel is the likeliest collision of the three rather than a
corner case: "LEVEL 7 — 1 skill point" is the banner that *tells* the player to
open this panel, so a player who acts on it immediately reads it straight across
the panel's own title. Found by screenshotting the panel, not by reasoning about
it.

## The victory panel (issue #39)

The boss dies, `scenes/main.gd` calls `show_victory()`, and a "VICTORY" heading,
a line of text and a **New run** button come up. Three things about it are worth
knowing before touching it.

**It is the only thing in this folder that sends something back into the game.**
Everything else here is fed inward by method call; `restart_requested` is a
signal going the other way, and it carries no argument and no opinion. What
starting a run *means* is `scenes/main.gd`'s — this folder must not learn.

**The whole tree is paused while it is up, and the panel alone keeps running.**
Freezing is what makes the run over rather than merely won: the hero stops
taking orders and the zombies stop chewing on him. But a paused `Control` is
skipped by GUI input dispatch, so the button would be dead under the cursor.
`hud.gd` sets `PROCESS_MODE_ALWAYS` on the panel in `_ready()` rather than in
the scene file, so the reason travels with the line; its children inherit it.
Anything else that has to work while the game is frozen goes inside that panel
or gets the same treatment.

**The button is this folder's first interactive `Control`, and it does not
break the rule above about the left mouse button.** A `Control` consumes a click
in GUI dispatch, which runs *before* `_unhandled_input`, so `scenes/hero/` never
sees it and there is no second listener on `select_command` — the arrangement
that section forbids. A `Button` is not another owner of the button; it is a
region of the screen the event never leaves. The game being paused makes it
doubly true here, and neither fact should be relied on alone if a widget is ever
added that is live during play.

**It takes the screen when it comes up**, cancelling the checkpoint flash and
hiding the death screen — and the two are not the same case. The flash is
genuinely reachable: arming a checkpoint and winning seconds later is what a
boss-room gate produces. The death screen is not, because `scenes/main.gd` stops
answering a death once the run is won. It is hidden anyway so that *this panel
owns the screen* is a rule of this folder, rather than something true only while
a guard in another folder keeps it true.

There is deliberately **no `hide_victory()`**: the only way off that screen is a
fresh scene, so a path taking it back down would be one no caller could reach.
The death screen's `hide_death()` is the counter-example that makes the
difference worth stating rather than assuming.

## Gotchas

- **The ring is cyan and orange, not the RTS-classic green and red**, and that
  is a constraint from `scenes/map/`: it paints the start cell green and the
  boss cell red as floor markers. A green ring is invisible on the green start
  marker — where the hero stands for the first seconds of every run, exactly
  when the player is working out that the ring means something — and a red ring
  would vanish the same way on the boss cell. If those markers are recoloured,
  re-check these. **#39 has now put the boss on the red marker and the colour
  choice held**; what did not is the ring's *size*, which nobody had reason to
  question while every selectable unit was a 0.4-radius capsule. The torus has
  an outer radius of 0.7, exactly the boss's body radius, so what a player sees
  is a crescent at its feet rather than a circle around it — issue #49. It
  reads; the next unit wider than this one will not.
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
  of a checkpoint on respawn, so a `Health` this folder is watching can be freed
  rather than merely dead — a reference that is non-null and unusable at once.
  **Both** `UnitSelection._stop_watching()` and `UnitInfoBar._unsubscribe()`
  therefore test `is_instance_valid`, not `!= null`. Only the first is reachable
  today; the panel is spared by `scenes/main.gd` redirecting it before it clears
  anything. That protection lives in another folder, which is exactly why the
  two are not allowed to differ here — a reader finding one guarded and one not
  would reasonably conclude the difference meant something.
- **Every banner is cancelled when the death screen goes up.** Arming a
  checkpoint and dying seconds later is not a corner case — a zombie chasing the
  hero across a threshold produces it — and a "CHECKPOINT" still fading behind
  "YOU DIED" reads as congratulating the player on the death. "LEVEL 3" does it
  twice over. Killing the tween is the load-bearing half: it drives `modulate:a`,
  so hiding the label without it leaves the fade running and re-hiding it a
  second later, over whatever came next.
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
  whatever is selected — plus `stats_changed` on the same unit since issue #65,
  which is the first signal this folder takes from a *unit* rather than from a
  component of one. Subscribed and dropped with the selection, exactly as the
  other two are, and not wired through `scenes/main.gd` for the reason that
  folder's doc gives: it does not know what is selected, so a wire through it
  would be a second record of something this folder already holds.
- `scenes/main.gd` also calls `set_hero_health()`,
  `set_attack_move_armed()`, `show_death()` / `hide_death()`,
  `flash_checkpoint()` and `show_victory()` — the last two from
  `Checkpoint.reached` and the boss's `Zombie.died`, the only HUD calls that do
  not originate with the hero. Issue #8 added `set_experience()`,
  `set_skills()` and `flash_level_up()`, driven from the hero's `Experience`
  child (`scenes/components/`) and from `Hero.skill_ranked_up`. Nothing here
  reads that component: `scenes/main.gd` connects its signals and calls these,
  which is the same inward-only arrangement everything else in this folder has.
- Emits `HUD.restart_requested`, consumed by `scenes/main.gd`, and since issue
  #62 `HUD.skill_rank_up_requested(skill)` and `HUD.skill_panel_toggled(open)` on
  the same terms — the three signals this folder sends into the game rather than
  draws from it, all re-emitted straight from a child panel. Two of them pair
  with the pause: that script sets `get_tree().paused`, so it is the one that has
  to clear it, whether the run was won or the tree was merely opened.
  Issue #8's `set_skills()` gained `set_skill_catalogue(points, catalogue)`
  beside it, fed from `Hero.skill_catalogue()`.
- **`scenes/main.gd` re-selects the hero on every respawn**, before it clears
  the restored segment. That ordering is its concern, not this folder's, but it
  is the reason a freed selection is rare rather than routine — the
  `is_instance_valid` guard above is what makes it merely rare and not fatal.
- Emits `UnitSelection.selection_changed(unit)`, consumed by `HUD` only.
- **Order matters at startup:** `scenes/main.gd` connects `selection_changed`
  *before* calling `select_unit(hero)`, because the info bar learns the initial
  selection from that signal and nothing re-sends it.

<!-- verified-against: f285e52 -->
