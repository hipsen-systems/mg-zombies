# Asset provenance & licenses

All third-party assets in this folder are **CC0 1.0** (public domain — no attribution required, commercial use allowed). This file records where each asset came from so future work can re-download the full packs for more pieces.

| Pack | Author | Source | License | Downloaded | Committed subset |
|---|---|---|---|---|---|
| KayKit — Character Pack: Adventurers (Free 2.0) | Kay Lousberg | https://kaylousberg.itch.io/kaykit-adventurers | CC0 | 2026-07-28 | `characters/hero/Knight.glb`, `characters/animations/Rig_Medium_*.glb` (2 of 5 characters' shared animation libraries) |
| KayKit — Dungeon Pack (Free 1.1) | Kay Lousberg | https://kaylousberg.itch.io/kaykit-dungeon-pack | CC0 | 2026-07-28 | 19 of 200+ pieces in `dungeon/` (walls, floor tiles, stairs, props) + shared `dungeon_texture.png` |
| Animated Zombie Pack | Quaternius | https://quaternius.com/packs/animatedzombie.html | CC0 | 2026-07-28 | `characters/zombies/Zombie.fbx`, `ZombieSmooth.fbx` (complete pack: 2 models, FBX only — no glTF published) |

Rules for adding assets (see also root `CLAUDE.md` → Assets):

- Only CC0 or another explicitly redistribution-safe license (this is a public repo with a public web deploy).
- Commit only the files a scene/script actually uses — never whole packs or `.zip` archives.
- Every addition gets a row in this table (or extends an existing row's subset description).
