# scenes/hero/

The player-controlled hero (issue #5: movement; issue #7: taking damage and
dying; his own attack comes in issue #11).

- `hero.tscn` — `CharacterBody3D` (collision layer 3, mask 1|2) with a
  placeholder capsule + a small "nose" box marking the facing direction, a
  `CollisionShape3D`, a `NavigationAgent3D`, and a `Health` child (100 HP,
  `scenes/components/`). In the `hero` group — that is how zombies find him,
  so don't rename it. The visual gets replaced by
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
  - **Every click produces a move order.** The raycast alone silently dropped
    clicks that hit no ground collider (dark background, past the level edge,
    above a wall) — which read in play as "my second click was ignored", since
    the hero just kept walking to its previous destination. `_ground_point_at`
    therefore falls back to intersecting the camera ray with the hero's ground
    plane, and `command_move_to` clamps the result onto the navigation map
    (`NavigationServer3D.map_get_closest_point`), so an off-level click means
    "walk as far that way as you can". Don't reintroduce an early-out that
    drops a click.
  - The handler uses the *event's* `position`, not
    `get_viewport().get_mouse_position()` — the two can differ by the time the
    event is handled, and it keeps the path drivable from headless tests.
  - `command_move_to(world_point)` is the public move-order API — future AI,
    skills, or tests should call this rather than poking the NavigationAgent.
    It cancels the previous order outright: the agent repaths, and horizontal
    velocity is zeroed so the hero can't coast another frame along the
    abandoned heading. Emits `move_ordered(world_point)` with the clamped
    point.
  - Movement: standard `NavigationAgent3D` loop in `_physics_process` +
    `move_and_slide()`, simple gravity, `lerp_angle` turning toward the
    movement direction.
  - **Damage and death (issue #7).** `take_damage(amount)` forwards to the
    `Health` child — attackers call this and never touch the component, which
    leaves room for armour or hit reactions later. On `Health.died` the hero
    sets `_dead`, stops, and emits `died`; while dead he ignores input and
    holds position (gravity still runs). `is_dead()` is public so a zombie
    stops swinging at a corpse. `scenes/main.gd` listens for `died` and
    restarts the run.

## Dependencies

- Requires a baked navmesh in the scene it's placed in (`scenes/main.gd`
  bakes at runtime) and a current `Camera3D` for the click raycast. The
  navmesh clamp in `command_move_to` reads `get_world_3d().navigation_map`,
  so orders issued before the first bake resolve to the hero's own position.
- Emits `move_ordered(world_point: Vector3)`; nothing consumes it yet (it
  exists for movement/attack-cancel wiring in issue #11). Emits `died`, which
  `scenes/main.gd` consumes. Consumes `Health.died` from its own child; XP
  signals arrive with issue #8.
- Damaged by `scenes/enemies/zombie.gd`, which finds him through the `hero`
  group.
