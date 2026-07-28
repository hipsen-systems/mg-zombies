# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A Godot 4.7 game project ("mg-zombies"). Currently a bare project scaffold: `project.godot` exists but no scenes, scripts, or main scene have been created yet.

Engine configuration (from `project.godot`):
- Renderer: Forward Plus, Direct3D 12 driver on Windows
- 3D physics engine: Jolt Physics
- Display stretch: `canvas_items` mode with `expand` aspect

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
- When creating a PR, write a body that gives the reviewer enough context to review without access to this conversation.

## Per-folder context docs

Every folder that contains code (scripts, scenes) must have its own `CLAUDE.md` describing that part of the project. Claude Code auto-loads nested `CLAUDE.md` files when working in a folder, so these act as living, self-loading documentation.

Rules:
- **Creating a new folder with code in it → create a `CLAUDE.md` in that folder.**
- **Adding or changing code in an existing folder → update that folder's `CLAUDE.md` in the same commit** if the change affects anything the doc describes (or should describe).
- Contents: what this folder's part of the game does, the key scenes/scripts and how they relate, signals emitted/consumed, dependencies on other folders (autoloads, other systems), and any non-obvious decisions or gotchas.
- Keep them short and current — a stale doc is worse than none. Delete statements that no longer hold rather than appending corrections.
- These folder docs are also what PR reviewers use to judge a change, so an out-of-date doc is a valid review finding.

## Running Godot

Godot is not on PATH. The editor binary on this machine is:

```
C:\Users\bruger\Downloads\Godot_v4.7.1-stable_win64.exe
```

Common invocations (from the repo root):

```bash
# Open the project in the editor
"C:\Users\bruger\Downloads\Godot_v4.7.1-stable_win64.exe" --path . --editor

# Run the project (requires a main scene to be set in project.godot)
"C:\Users\bruger\Downloads\Godot_v4.7.1-stable_win64.exe" --path .

# Run a specific scene
"C:\Users\bruger\Downloads\Godot_v4.7.1-stable_win64.exe" --path . res://path/to/scene.tscn

# Headless asset import (regenerates .godot/ cache, e.g. after adding assets)
"C:\Users\bruger\Downloads\Godot_v4.7.1-stable_win64.exe" --headless --path . --import

# Syntax-check a single GDScript file without running the game
"C:\Users\bruger\Downloads\Godot_v4.7.1-stable_win64.exe" --headless --path . --check-only --script res://path/to/script.gd
```

Note: this is the standard Windows GUI binary (no `_console.exe` wrapper is installed), so stdout may not appear in an interactive terminal, though piped/captured output generally works.

There is no test framework (e.g. GUT, gdUnit4) installed.

## Conventions

- Git normalizes all text files to LF line endings (`.gitattributes`); files are UTF-8 (`.editorconfig`).
- `.godot/` is generated editor cache and is gitignored — never edit or commit it.
- Prefer editing `project.godot` settings through the editor UI when possible; if editing directly, keep the existing section format.
