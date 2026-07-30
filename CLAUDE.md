# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A Godot 4.7 game project ("mg-zombies") — see **Game design** below for what it is.

This file holds what does not change when the code changes: design intent, team
workflow, tooling, and conventions. **Current implementation state belongs in the
per-folder docs, never here.** A description of the code written into this file
has nothing anchoring it to the code, so nothing ever flags it when it stops
being true — which is exactly how this section came to claim for weeks that the
project had no scripts.

Engine configuration (from `project.godot`):
- Renderer: Forward Plus, Direct3D 12 driver on Windows
- 3D physics engine: Jolt Physics
- Display stretch: `canvas_items` mode with `expand` aspect

### Code map

Every folder holding code, and the doc that describes it. This is the one
inventory the root keeps, and it is checked against the repo — a new code folder
fails CI until it is listed here.

| Folder | What lives there |
|--------|------------------|
| [`scenes/`](scenes/CLAUDE.md) | Top-level scenes, game startup order, RTS camera |
| [`scenes/hero/`](scenes/hero/CLAUDE.md) | The player-controlled hero and its move controller |
| [`scenes/map/`](scenes/map/CLAUDE.md) | The maze map and its generation |
| [`assets/`](assets/CLAUDE.md) | Third-party CC0 art and the licence record |

## Game design

Top-down single-hero action game with the visual style of classic RTS games (StarCraft/Warcraft camera and look), but you control only one unit: your hero.

- **Core loop:** fight through a maze-like map filled with zombies; win by killing the boss at the end of the map.
- **Progression:** level up by killing zombies, completing objectives along the way, and defeating minibosses.
- **Skill tree:** every hero starts identical; a large skill tree lets each run/player build a unique hero. The skill tree is the central customization system — design decisions should protect its depth and build variety.

When making gameplay or architecture decisions, favor what serves this loop (hero movement/combat feel, readable top-down visuals, map/encounter design, skill-tree extensibility).

## Team workflow

Two developers collaborate via feature branches and pull requests.

- **Starting any new piece of work:** first sync with the remote (`git fetch origin`), then create a fresh branch from `origin/main` — e.g. `git switch -c feature/skill-tree origin/main`. Never start new work from a stale local `main` or from another feature branch.
- Branch naming: `feature/<topic>`, `fix/<topic>`, or `test/<topic>`.
- **Resuming existing work:** switch back to that feature branch; don't merge `main` into it unless the PR is blocked by the "branch up to date" requirement or a conflict.
- Never commit directly to `main`. All work happens on branches and lands through PRs (branch protection rejects direct pushes anyway).
- One topic per branch/PR — keep PRs small and reviewable; flag unrelated changes for a separate branch.
- Every PR is reviewed by the *other* developer's Claude before merging (cross-review). When the user asks you to review their partner's PR, do a genuine critical review: check it against this file's conventions, the game design goals, and the per-folder context docs — don't rubber-stamp.
- **Solo review, when the other developer is away.** `main` requires zero approving reviews, so the author can merge their own PR. This is deliberate: GitHub blocks authors from approving their own PRs, so an approval gate would deadlock a one-person week. The *review* is not waived, it moves to the author's side:
  - The `claude-review` workflow runs on every PR and is a required check. Read its comment and address the findings before merging.
  - Have your own Claude review the diff too, held to the same bar as a cross-review. An author-side reviewer that softens its findings makes the whole gate worthless.
  - Everything else still applies: one topic per PR, no direct commits to `main`, all checks green, threads resolved. Merging your own PR is the exception — when both developers are around, wait for the cross-review.
  - Restoring the two-person gate: `gh api --method PATCH repos/hipsen-systems/mg-zombies/branches/main/protection/required_pull_request_reviews -F required_approving_review_count=1`
- When creating a PR, write a body that gives the reviewer enough context to review without access to this conversation.

## Per-folder context docs

Every folder that contains code (scripts, scenes) must have its own `CLAUDE.md` describing that part of the project. Claude Code auto-loads nested `CLAUDE.md` files when working in a folder, so these act as living, self-loading documentation.

Rules:
- **Creating a new folder with code in it → create a `CLAUDE.md` in that folder**, and add it to the code map above.
- **Adding or changing code in an existing folder → update that folder's `CLAUDE.md` in the same commit** if the change affects anything the doc describes (or should describe).
- Contents: what this folder's part of the game does, the key scenes/scripts and how they relate, signals emitted/consumed, dependencies on other folders (autoloads, other systems), and any non-obvious decisions or gotchas.
- Keep them short and current — a stale doc is worse than none. Delete statements that no longer hold rather than appending corrections.
- These folder docs are also what PR reviewers use to judge a change, so an out-of-date doc is a valid review finding.

### The `verified-against` stamp

Every folder doc ends with a marker naming the commit it was last checked against:

```markdown
<!-- verified-against: 4a272d6 -->
```

It is a claim that a person or agent read the doc against the folder's code at
that commit and found it true. It is the only such claim in the repo, so do not
bump it casually — a stamp you did not earn is worse than an old one, because it
converts "unknown" into "verified".

You rarely need to touch it. A commit that changes both a folder's files and its
doc satisfies the check on its own, so ordinary well-formed work never moves the
stamp. Bump it when you have *audited* a doc: read it end to end against the
code and corrected what drifted.

### What is enforced, and what is not

`.claude/hooks/check-folder-docs.sh` runs as a Stop hook locally and in CI on
every PR (`docs-check` workflow). It runs three checks:

| Check | Catches |
|-------|---------|
| same-change | Code changed in a folder without its doc changing; `project.godot` changed without the root doc changing |
| code map | A code folder missing from the root's code map, or a map entry pointing at a doc that does not exist |
| verification | A folder whose files changed since its `verified-against` stamp without the doc being touched — including history that predates these hooks, merge-conflict resolutions, and commits from anyone running without hooks |

`bash .claude/hooks/check-folder-docs.sh --audit` runs the history checks alone,
against any checkout.

Know the limit: these verify that a doc was *edited*, never that it is *true*.
Nothing mechanical can check the latter. The stamp exists to make the human
judgement explicit and attributable rather than assumed — treat a stale stamp as
a real finding in cross-review.
## Knowledge base (Flowdex)

The team keeps a shared, AI-readable wiki in Flowdex, project slug **`mg-zombies`**. It is the long-term memory the folder docs can't hold: architecture decisions and *why* they were made, gotchas, conventions, and the state of the project. Both developers' Claude sessions read and write it.

**Connecting (once per developer).** Flowdex reaches Claude Code as an MCP connector on your own Claude account, authenticated with your personal `nx_live_` token. Add it in your Claude account's connector settings. The token is a secret: it belongs in that connector config only — never in this repo, a PR, or an issue. Ask the other developer for a Flowdex org invite if you don't have an account yet. Until you connect it, the hooks below no-op and everything else here still works.

**What belongs here, and what belongs in a `CLAUDE.md`.** The two must never describe the same thing. A fact written in two places gets corrected in one, and the survivor is a confident lie — this is the single largest source of doc rot, and it has already happened here. The test is ownership, and it runs against *both* in-repo doc layers, not just the folder ones:

- **A folder owns a fact → that folder's `CLAUDE.md` owns it.** Everything listed under `Contents:` in "Per-folder context docs" below — *including what the folder imposes on everyone else*. The folder that creates a constraint owns the statement of what it constrains, because that is where the constraint stops being true if the code changes: `scenes/map/` owns "corridors are single-file, so encounter design must assume units queue", since the map is what makes it so.
- **This root file owns a fact → it owns it.** The list in `## Project` at the top of this file, and the sections built on it — game design, builds and releases, the asset policy.
- **Nothing in the repo *can* own it → Flowdex owns it.** Project state (what is merged, what is in flight, what comes next), the history behind a decision including what was tried and rejected, and an index of which systems exist and what depends on what — read *before* you know which folder to open. None of these describe a folder, which is why no folder can hold them. Note the third is an *index*, not rationale: why a given constraint binds is owned by the folder that creates it, per the first bullet.

**The trap, and it is the whole difficulty of this rule: "several folders depend on it" is not "no folder owns it."** Ownership is assigned, not discovered, so almost any fact *can* be given a home — which means the test only works if you default to the repo and move something to the wiki reluctantly. Physics layers is the worked example of getting this right: `scenes/` owns the table because the convention was established there, and `scenes/map/` and `scenes/hero/` link to it rather than restating it. A contract half the codebase depends on still gets exactly one owner, in the repo.

A Flowdex page about something the repo already owns is therefore a *stub*: what the thing is, what constraint it imposes on everyone else, where the detail lives, and its links. Nothing more.

**The concrete test: a page may point at a file, never restate what is inside it.** For game code that collapses to a plain ban — name the folder (`scenes/map/`), never `maze.gd`, `command_move_to()`, or `agent_radius = 1.0`. Pages about repo infrastructure may name the specific workflow or hook file, since "the build check" is unusable without it, but they still record what it *guarantees*, never how it is written. Issue and PR numbers are project state, not code facts, and stay welcome.

The rule scales in the right direction: as the codebase grows, more concerns become cross-cutting, so the wiki grows where it is uniquely useful instead of mirroring the source tree.

**Using it — the two halves.**
- **Read before you act.** At the start of substantive work (gameplay features, architecture decisions, asset or infra changes), invoke the `nexus-knowledge-base` skill: `get_project_structure`, then `read_index` the pages relevant to the task. Reading one page is not enough. Skip it for trivial one-liners.
- **Write durable knowledge back.** Save what outlives the chat as a small single-topic page under the right category folder, and record the change with `append_changelog`. Loading context and writing nothing back is the failure this system exists to prevent.

**The wiki tracks merged `main`, not the working tree.** Unmerged work may be documented, but only under an explicit `## In flight — PR #N <branch> (not merged)` heading. A reader must never have to check out a branch to learn whether a page is true. When in doubt read `git show main:<path>`, not the working copy — both developers' sessions share one checkout.

**Merging a PR is a wiki event.** Whenever a PR is accepted — yours or your partner's — update Flowdex in the same session, before moving on: fold that PR's "In flight" block into the page body, correct whatever else it changed, add pages for new concepts, and `append_changelog` with the PR number and title.

**Layout:** root `overview.md` hub plus category folders `game-design/`, `engine/`, `workflow/`, `build-release/`, `assets/`. Pages use the sections Overview / Key information / Relations / Last updated, stay single-topic, and link with `[[wiki-links]]`. Prefer correcting a page over appending to it — a stale statement left in place is worse than a missing one. Because both developers can read the wiki, citing pages in PR bodies and issues is encouraged.

**Enforcement.** Two hooks in `.claude/settings.json` close the gap between invoking the skill and actually using it: `SessionStart` injects a reminder, and `Stop` runs `.claude/hooks/check-flowdex.sh`, which blocks the session from ending when it never wrote anything back but either edited `.gd`/`.tscn`/`CLAUDE.md`/config files or merged a PR. It never blocks a developer without the connector, a read-only session, a scratchpad-only session, or twice in a row.

## Running Godot

The project uses Godot 4.7.1. Godot is not on PATH and the binary location is machine-specific, so it is deliberately not recorded here. Each developer keeps their local path in `CLAUDE.local.md` in the repo root (gitignored; Claude Code auto-loads it alongside this file). If that file doesn't exist yet, locate the install (try `Downloads` for `Godot_v4.7.1*`) and offer to create it with the path you found.

Windows gotchas when locating the binary:
- The extracted download may be a *folder* that is itself named `...win64.exe`, with the actual executables inside it.
- If a `Godot_v*_console.exe` wrapper exists, prefer it for terminal/automation work — its stdout is reliably capturable, unlike the GUI binary's.

Common invocations (from the repo root), abbreviating the binary as `$GODOT`:

```bash
# Open the project in the editor
"$GODOT" --path . --editor

# Run the project (main scene: res://scenes/main.tscn)
"$GODOT" --path .

# Run a specific scene
"$GODOT" --path . res://path/to/scene.tscn

# Headless asset import (regenerates .godot/ cache, e.g. after adding assets)
"$GODOT" --headless --path . --import

# Syntax-check a single GDScript file without running the game
"$GODOT" --headless --path . --check-only --script res://path/to/script.gd
```

There is no test framework (e.g. GUT, gdUnit4) installed.

## Backlog & issues

GitHub Issues is the project backlog. Claude sessions should actively use it:

- **Before starting work**, check whether an open issue covers the task; reference it in the PR body with `Fixes #N` (auto-closes on merge) or `Part of #N`.
- **When the user describes a new feature idea or bug** that isn't being worked on right now, offer to file an issue for it so it isn't lost.
- **When you discover an out-of-scope problem mid-task** (a bug, missing coverage, a design question), file an issue instead of fixing it inline — keep PRs on-topic.
- Labels: `skill-tree`, `hero`, `combat`, `map`, `ui`, `art`, `infra`, plus GitHub's default `bug`/`enhancement`/`documentation`. Apply what fits.
- Milestones group issues toward a playable goal (first one: "First playable").

## Builds & releases

- **Web build / playable link:** every merge to `main` exports the Web preset and deploys it to GitHub Pages: https://hipsen-systems.github.io/mg-zombies/ — the always-current playable state of the game.
- **Releases:** pushing a tag like `v0.1.0` builds the Windows exe and attaches it to an auto-created GitHub Release. Tag from an up-to-date `main` only.
- **PR build check:** every PR must export successfully (`build-check` workflow) before it can merge.
- Export presets live in `export_presets.cfg` (Web has thread support disabled on purpose — required for GitHub Pages; Windows embeds the pck into a single exe). `build/` output is gitignored.

## GitHub API access

Tooling differs per machine: prefer the `gh` CLI where it is installed (check with `gh --version`; record its presence or absence in your `CLAUDE.local.md`). Where `gh` is missing (`python` and `jq` may be too), call the GitHub API (issues, PRs, checks) by reusing git's stored credential — never print the token itself:

```bash
cred=$(printf 'protocol=https\nhost=github.com\n' | git credential fill 2>/dev/null)
token=$(printf '%s' "$cred" | sed -n 's/^password=//p')
curl -s -H "Authorization: token $token" https://api.github.com/repos/hipsen-systems/mg-zombies/issues
```

## Assets

Third-party assets live in `assets/` and are governed by an anti-bloat policy (this repo is public and every asset ships in the web deploy):

- **Only CC0** (or another explicitly redistribution-safe license). No "free for personal use" assets.
- **Commit only files a scene/script actually uses** — never whole asset packs, and never `.zip` archives (gitignored). Trim first, commit second.
- **Every asset addition updates `assets/LICENSES.md`** (source, license, date, committed subset) in the same commit. Re-download instructions live there too.
- Reviewers: an asset PR that violates any of these is a valid blocking finding.

## Conventions

- Git normalizes all text files to LF line endings (`.gitattributes`); files are UTF-8 (`.editorconfig`).
- `.godot/` is generated editor cache and is gitignored — never edit or commit it.
- Prefer editing `project.godot` settings through the editor UI when possible; if editing directly, keep the existing section format.
