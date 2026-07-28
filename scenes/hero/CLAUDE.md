# scenes/hero/

The player-controlled hero (issue #5: movement; combat comes in issue #11).

- `hero.tscn` — `CharacterBody3D` (collision layer 3, mask 1|2) with a
  placeholder capsule + a small "nose" box marking the facing direction, a
  `CollisionShape3D`, and a `NavigationAgent3D`. The visual gets replaced by
  the KayKit Knight once the asset PR lands; the node forward direction is -Z
  (Godot convention) so a rigged model drops in without a compensating
  rotation.
- `hero.gd` (`class_name Hero`) — click-to-move controller.
  - **Input decision (documented per issue #5):** *right*-click issues the
    move command (RTS convention); left-click is reserved for
    targeting/attacks (issue #11). The action is `move_command` in
    `project.godot`.
  - The click ray collides only with physics layer 1 (ground), so clicking a
    wall moves the hero to the floor at/behind that point instead of trying
    to climb it.
  - `command_move_to(world_point)` is the public move-order API — future AI,
    skills, or tests should call this rather than poking the NavigationAgent.
  - Movement: standard `NavigationAgent3D` loop in `_physics_process` +
    `move_and_slide()`, simple gravity, `lerp_angle` turning toward the
    movement direction.

## Dependencies

- Requires a baked navmesh in the scene it's placed in (`scenes/main.gd`
  bakes at runtime) and a current `Camera3D` for the click raycast.
- No signals emitted or consumed yet — HP/XP/attack signals arrive with
  issues #7, #8, #11.
