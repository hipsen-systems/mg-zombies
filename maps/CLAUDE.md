---
depends-on: [scenes/map]
---

# maps/

The maps the game ships, one JSON file each (issue #73). This folder is
content, not code: nothing here runs, and adding a map is adding a file.

**The format — what a file may say and every rule it must obey — belongs to
[`scenes/map/`](../scenes/map/CLAUDE.md)**, because the reader there is what
makes it true. This doc is about the maps themselves. If a file here and that
doc disagree, the validator has already refused the file: `tests/smoke_map.gd`
holds every `*.json` in this folder to it on every PR.

| File | Map |
|------|-----|
| `dungeon.json` | The open single-path level (issues #37, #38, #39), ported unchanged from the layout that used to live in `scenes/map/level_map.gd` |

## Adding or editing a map

- Copy the shape of `dungeon.json`. The grid carries only `#` and `.`; the
  spawn, boss, checkpoints and enemies are entries in `markers` and `actors`,
  positioned by `[column, row]` against the grid.
- **Every cell has to be read against the rows by eye**, which is the whole
  reason positions are cells and not world units. Count columns from 0 at the
  first character and rows from 0 at the first string.
- `actors` name what stands there by id — `"zombie"`, `"boss"` — never a
  file. What an id resolves to is `scenes/main.gd`'s table until the registry
  (issue #74) exists; a new id needs an entry there first, and a map naming
  one that has none gets an error at startup and an empty cell.
- Run `bash tests/run.sh "$GODOT"` before pushing. A map with anything wrong
  is not built at all, and the reasons are printed one per line; the same
  reasons an author sees, the test asserts.
- **Editing a map means re-reading this doc.** The `verified-against` check
  reads every file directly in this folder, so a map edit that leaves the
  description below untrue is flagged like a code change would be.

## The shape of the dungeon level

44 × 38 cells, 620 of them open. One route runs from the spawn (bottom left)
to the boss (top right) and back is the only way out of anywhere else:
**every** path from spawn to boss passes through both chokepoints, and there
is no loop.

- **Two clearings** 10–13 cells across, joined by a passage 3 cells thick.
- **Two one-cell chokepoints** — a throat out of the start clearing, and a
  tunnel between the clearings that is one cell *tall* and three long. (This
  said five until #38 counted it: the cells at either mouth are single-cell
  *cuts*, so every route still crosses all five, but they have open floor
  above and below them and are not part of the enclosed tunnel.)
- **A two-cell door** into the boss arena. Narrow enough to read as a gate,
  wide enough that two units are not forced to queue.
- **Two dead-end spurs** — a chamber north of the first clearing (21 cells)
  and a vault south of the second (24 cells), each holding two zombies. Both
  hang off a two-cell neck, so neither shows up as a single-cell cut.
- **Two checkpoints** past the implicit one on the spawn: the three enclosed
  tunnel cells (24 from the start by path) and a six-cell gate across the
  boss-room threshold (46). Between them the run splits 7 / 9 / 3 zombies,
  and the boss is in segment 2.
- **19 zombies and the boss**, at 10 XP each: 190 XP, which is level 4 and 3
  skill points. `scenes/enemies/` owns what that buys against the boss.

**The clearance rule is met exactly, twice** — 4.00 cells at both the tunnel
and the boss gate, and the spawn has 6 — so there is no slack to spend. Moving
either checkpoint one cell toward the fight it guards is refused by the
validator, which is now the thing that says so rather than a doc to remember.

**Why the second checkpoint is the boss-room threshold and not the two-cell
door one row below it**, which is the spot that looks right: the south vault
runs to path distance 47; the door is at 44, the threshold at 46. At the door,
the vault's far zombie files into the wrong segment and the validator refuses
the map for it. Moving the checkpoint two rows on is the whole fix, and it
costs nothing — no spawn sits between 45 and 47, so the split is identical
either way.

**Chokepoints must be deliberate.** #44's own review pass found two
*accidental* one-cell pinches in a passage meant to be several cells wide, and
widened them. Worth re-running that check when reshaping the route: the
validator proves the map connects, never that it connects the way you meant.

**Count a feature before describing it.** The tunnel was "five cells long"
from #37 until #38 measured it, and a clearance figure three docs cited as a
contract turned out to be off by a cell (#54). Every number above was
measured; re-measure rather than adjust when the map changes.

