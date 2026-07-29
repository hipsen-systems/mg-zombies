# assets/

Third-party CC0 3D assets, trimmed to what the game actually uses. Provenance and licensing for every file: `LICENSES.md` (update it with every addition — reviewers should reject asset PRs that don't).

## Layout

- `characters/hero/Knight.glb` — the hero model (KayKit Adventurers). Self-contained GLB, textures embedded, rigged for KayKit's `Rig_Medium` skeleton. We use one character only — every hero starts identical by design (see root CLAUDE.md, skill tree).
- `characters/animations/Rig_Medium_General.glb`, `Rig_Medium_MovementBasic.glb` — shared KayKit animation libraries (idle/walk/run/attacks etc.) targeting the same `Rig_Medium` skeleton as the Knight. Import these and retarget/reuse their `AnimationLibrary` on the hero rather than authoring locomotion animations by hand.
- `characters/zombies/Zombie.fbx`, `ZombieSmooth.fbx` — the two Quaternius zombie models, animations included in the FBX. Flat/atlas materials, no external texture files (the two are shading variants of the same zombie; sizes differ slightly).
- `dungeon/` — KayKit Dungeon Pack pieces for maze building: `wall*`, `floor_tile*`/`floor_dirt_large`, `stairs`, and props (`torch*`, `barrel_large`, `crates_stacked`, `chest`, `column`). Each piece is a `.gltf` + same-named `.bin` pair; **all pieces reference the shared `dungeon_texture.png`** — keep the pair together and never delete/rename the texture without checking every `.gltf`.

## Gotchas

- The dungeon pieces are text `.gltf` (JSON) referencing external `.bin` buffers — copying a piece means copying both files.
- Zombies are FBX (Quaternius publishes no glTF for this pack); Godot 4.7 imports FBX natively via ufbx. If materials come in white, the FBX embedded material needs re-linking in the import dock — flag it, don't silently reimport to other formats.
- Need more dungeon pieces or another Adventurers character? Re-download the packs (URLs in `LICENSES.md`) and copy only the new files you use, updating `LICENSES.md`.

<!-- verified-against: 4a272d6 -->
