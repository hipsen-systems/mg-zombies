class_name Hero
extends CharacterBody3D
## The player-controlled hero: click-to-move (issue #5), takes damage and dies
## (issue #7), and now fights back (issue #11).
##
## Commands follow the StarCraft/Warcraft [b]smart command[/b] model, because
## that is the control scheme the whole game is styled after:
##
## - [b]Right-click[/b] is the smart command: on the ground it is a move order,
##   on an enemy it is an attack order.
## - [b]Left-click[/b] is selection, and never an attack. Nothing consumes a
##   bare left-click yet — the unit info bar is issue #36 — but the binding is
##   reserved now so the two never end up fighting over the button.
## - [b]A, then left-click[/b] is the attack command: on an enemy it attacks
##   that enemy, on the ground it is an attack-move — walk there, but stop to
##   kill anything that comes within [member acquire_radius] on the way, then
##   carry on to where you pointed.
##
## Which orders pick up targets by themselves is the part worth keeping
## straight, and each answer is a decision rather than a side effect:
##
## - [b]MOVE does not.[/b] A move order runs the gauntlet untouched. This is
##   what makes "sprint past the encounter" a real choice instead of a bug.
## - [b]ATTACK_MOVE does.[/b] That is the entire difference between it and MOVE.
## - [b]IDLE does.[/b] A hero standing still defends himself, so a player who
##   is reading the rest of the screen is not chewed on for free. It also makes
##   a separate retaliate-when-hit rule unnecessary: nothing can reach the hero
##   from outside [member acquire_radius] anyway.
##
## [b]This script never names an enemy class.[/b] Targets are found through the
## "enemies" group and used through take_damage()/is_dead(), so scenes/hero/
## does not depend on scenes/enemies/ — the dependency runs one way, enemies to
## hero. A second enemy type needs no change in here.

## Emitted with the clamped destination of a move or attack-move order.
signal move_ordered(world_point: Vector3)

## Emitted when the hero is told to attack something — by right-click, by
## A+click, or by acquiring a target on his own.
signal attack_ordered(target: Node3D)

## Emitted when a target dies from this hero's damage. The XP hook for issue #8;
## nothing consumes it yet. Attribution is exact — it fires from the swing that
## landed the killing blow, not from the victim's own death signal, which any
## source of damage would trigger.
signal killed(victim: Node3D)

## Emitted when the attack command is armed or disarmed, so the HUD can show
## the player that the next left-click means "attack" rather than "select".
signal attack_move_armed_changed(armed: bool)

## Emitted once when the hero's health hits zero. scenes/main.gd listens.
signal died

## What the hero is currently under orders to do.
enum Order {
	## No orders. Holds position, but will defend itself.
	IDLE,
	## Walking somewhere, ignoring everything on the way.
	MOVE,
	## Closing on a specific enemy and swinging once in range.
	ATTACK_TARGET,
	## Walking somewhere, engaging whatever it meets and then resuming.
	ATTACK_MOVE,
}

## Ground is physics layer 1, enemies are layer 4 — see the table in
## scenes/CLAUDE.md. A click fires two rays rather than one, because the two
## questions want opposite tie-breaks. The ground ray must ignore walls, so
## clicking a wall means the floor behind it (issue #5). The enemy ray must
## respect them, so clicking a wall never means the zombie behind it. One
## combined query cannot do both, and the floor under a zombie's feet would
## sometimes win it anyway.
const GROUND_MASK := 1
const ENEMY_MASK := 8
const RAY_LENGTH := 1000.0

## Walls and static obstacles (physics layer 2) — the same blocker mask
## scenes/enemies/ tests its own line of sight against.
const SIGHT_BLOCKER_MASK := 2

## Roughly chest height on the 1.8-unit capsule. Matches the zombie's so both
## sight rays agree about what "can see" means; a mismatch would let one side
## see through cover the other treats as solid.
const EYE_HEIGHT := 1.2

const ENEMY_GROUP := "enemies"

## How far from the clicked ground point an enemy still counts as clicked.
##
## A 0.4-radius capsule seen down a ~57° camera is a small thing to hit, and an
## attack order that silently becomes a move order into a pack is the worst
## possible way to miss. If the enemy ray misses, the nearest living enemy
## within this distance of the ground point is taken instead. Keep it under half
## a cell (2.0) or clicking the floor beside a zombie stops meaning the floor.
const CLICK_SLACK := 1.6

## Target reassessment runs on a fixed tick rather than every frame, matching
## the sensing budget scenes/enemies/ already uses. Retargeting is a group scan
## and a repath; neither needs 60 Hz.
const RETARGET_INTERVAL := 0.2

## How far the visual jabs forward on a swing, in metres.
const SWING_LUNGE := 0.45

@export_group("Movement")
@export var move_speed := 6.0
@export var turn_speed := 12.0

@export_group("Combat")
## Reach of the basic attack. Slightly longer than the zombie's, so trading
## blows toe-to-toe is not purely a coin flip.
@export var attack_range := 2.2
@export var attack_damage := 12.0
## Seconds between swings — attack speed, expressed the same way the zombie's is.
@export var attack_cooldown := 0.9
## Radius the hero picks up his own targets in, while idle or attack-moving.
## Well under the zombie's detection radius (12): the hero should be noticed
## before he notices, so a fight starts because the player walked into it.
@export var acquire_radius := 9.0

@export_group("Regeneration")
## Seconds out of combat — neither taking damage nor swinging — before health
## starts coming back. Without this, clearing a fight at low health makes the
## next one unwinnable and the only move is to die on purpose, which is a
## miserable way to use a checkpoint (issue #38).
@export var regen_delay := 5.0
@export var regen_per_second := 4.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _dead := false

var _order: Order = Order.IDLE
var _target: Node3D = null
## Where an interrupted attack-move resumes once its fight is over. Guarded by
## a flag rather than a null sentinel so the type stays Vector3.
var _resume_point := Vector3.ZERO
var _has_resume_point := false
var _attack_move_armed := false

var _attack_timer := 0.0
var _retarget_timer := 0.0
var _regen_timer := 0.0
var _swing_tween: Tween = null

@onready var health: Health = $Health
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: Node3D = $Visual


func _ready() -> void:
	health.died.connect(_on_health_died)


func is_dead() -> bool:
	return _dead


## Damage entry point — attackers call this rather than reaching into the
## Health child, so the hero stays free to react to a hit later (armour,
## interrupted casts, hit reactions).
func take_damage(amount: float) -> void:
	if _dead:
		return
	_mark_in_combat()
	health.take_damage(amount)


## What the hero is currently doing, for the HUD and for tests.
func current_order() -> Order:
	return _order


## The enemy the hero is currently attacking, or null.
func current_target() -> Node3D:
	return _target if _is_valid_target(_target) else null


# --- Commands ----------------------------------------------------------------

## Public move order — also the entry point for future AI/skills/tests.
##
## Issuing an order cancels the previous one outright: the target is replaced
## (NavigationAgent3D repaths on the next query) and the carried-over horizontal
## velocity is dropped so the hero cannot coast another frame along the
## abandoned heading. Rapid re-clicking therefore reads as an instant redirect.
func command_move_to(world_point: Vector3) -> void:
	var reachable := _on_navmesh(world_point)
	_clear_orders()
	_order = Order.MOVE
	_nav_agent.target_position = reachable
	move_ordered.emit(reachable)


## Attack a specific enemy: close on it, then swing on cooldown until it dies.
## Ignored for anything that is not a living enemy, so a stale click cannot
## leave the hero attacking a corpse.
func command_attack(target: Node3D) -> void:
	if not _is_valid_target(target):
		return
	_clear_orders()
	_order = Order.ATTACK_TARGET
	_target = target
	_nav_agent.target_position = _on_navmesh(target.global_position)
	attack_ordered.emit(target)


## Attack-move: walk to a point, engaging anything that comes within
## [member acquire_radius] and resuming afterwards.
func command_attack_move(world_point: Vector3) -> void:
	var reachable := _on_navmesh(world_point)
	_clear_orders()
	_order = Order.ATTACK_MOVE
	_resume_point = reachable
	_has_resume_point = true
	_nav_agent.target_position = reachable
	move_ordered.emit(reachable)


## Drop every order and hold position.
func command_stop() -> void:
	_clear_orders()


func _clear_orders() -> void:
	_order = Order.IDLE
	_target = null
	_has_resume_point = false
	# Drop the carried-over heading so a new order never coasts a frame along
	# the old one.
	velocity.x = 0.0
	velocity.z = 0.0


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return

	if event.is_action_pressed("attack_move"):
		_set_attack_move_armed(not _attack_move_armed)
		return

	if event.is_action_pressed("cancel_command"):
		_set_attack_move_armed(false)
		return

	# Use the position carried by the click itself rather than the live mouse
	# position: the two can differ by the time the event is handled, and it
	# keeps this path deterministic for headless tests.
	if event.is_action_pressed("select_command"):
		if not _attack_move_armed:
			# A bare left-click is selection (issue #36), which this script does
			# not own. Deliberately not an attack: an RTS where inspecting a unit
			# also swings at it is unusable.
			return
		_set_attack_move_armed(false)
		_issue_attack_click((event as InputEventMouseButton).position)
		return

	if event.is_action_pressed("move_command"):
		# Any world command cancels an armed attack — otherwise the arming
		# survives the click that was meant to replace it.
		_set_attack_move_armed(false)
		_issue_smart_click((event as InputEventMouseButton).position)


## Right-click: attack what is under the cursor, or move to the ground.
func _issue_smart_click(screen_point: Vector2) -> void:
	var ground = _ground_point_at(screen_point)
	var enemy := _target_at(screen_point, ground)
	if enemy != null:
		command_attack(enemy)
	elif ground != null:
		command_move_to(ground)


## A + left-click: attack what is under the cursor, or attack-move to the ground.
func _issue_attack_click(screen_point: Vector2) -> void:
	var ground = _ground_point_at(screen_point)
	var enemy := _target_at(screen_point, ground)
	if enemy != null:
		command_attack(enemy)
	elif ground != null:
		command_attack_move(ground)


func _set_attack_move_armed(armed: bool) -> void:
	if _attack_move_armed == armed:
		return
	_attack_move_armed = armed
	attack_move_armed_changed.emit(armed)


# --- Per-frame ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if _dead:
		_halt()
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_tick_regen(delta)

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		_reassess()

	match _order:
		Order.IDLE:
			_halt()
		Order.MOVE, Order.ATTACK_MOVE:
			_process_travel(delta)
		Order.ATTACK_TARGET:
			_process_attack(delta)


## Order bookkeeping and target acquisition. Runs on the retarget tick, not
## every frame — everything that needs per-frame precision (the cooldown,
## gravity, movement) lives in _physics_process instead.
func _reassess() -> void:
	match _order:
		# The two acquiring orders, sharing one branch because they acquire
		# identically. What differs is what happens after the kill, and that is
		# _finish_engagement()'s job: an attack-move keeps its destination and
		# carries on, an idle hero simply stands down again.
		Order.IDLE, Order.ATTACK_MOVE:
			var found := _nearest_enemy_to(global_position, acquire_radius, true)
			if found != null:
				_engage(found)

		Order.ATTACK_TARGET:
			if not _is_valid_target(_target):
				_finish_engagement()
				return
			# Repath only while out of reach. Repathing inside attack range
			# would fight the "stand still and swing" branch every tick.
			if _horizontal_distance_to(_target.global_position) > attack_range:
				_nav_agent.target_position = _on_navmesh(_target.global_position)

		Order.MOVE:
			pass


## Take a target without disturbing a pending attack-move destination.
func _engage(target: Node3D) -> void:
	_order = Order.ATTACK_TARGET
	_target = target
	_nav_agent.target_position = _on_navmesh(target.global_position)
	attack_ordered.emit(target)


## The target is gone: resume the attack-move that was interrupted, or stand down.
func _finish_engagement() -> void:
	_target = null
	if _has_resume_point:
		_order = Order.ATTACK_MOVE
		_nav_agent.target_position = _resume_point
	else:
		_order = Order.IDLE


func _process_travel(delta: float) -> void:
	if _nav_agent.is_navigation_finished():
		_order = Order.IDLE
		_has_resume_point = false
		_halt()
		return
	_travel(delta, move_speed)


func _process_attack(delta: float) -> void:
	if not _is_valid_target(_target):
		# _reassess() cleans this up on the next tick; until then, stand.
		_halt()
		return

	# `to_target` is the facing direction only. The range test goes through the
	# shared helper, so this check and the repath check in _reassess() are one
	# code path rather than two that happen to agree today.
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	if _horizontal_distance_to(_target.global_position) > attack_range:
		if _nav_agent.is_navigation_finished():
			# The path says we arrived and the target is still out of reach, so
			# it is not reachable from here — the navmesh clamp put its goal
			# somewhere we cannot close on. Stand and face rather than jitter.
			# Deliberately not "give up": dropping the target would re-acquire
			# the same one on the next tick and flap. The player can always
			# issue another order.
			_face(to_target, delta)
			_halt()
			return
		_travel(delta, move_speed)
		return

	_halt()
	_face(to_target, delta)
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	_swing(_target)


## Land a hit. There is no wind-up: the blow arrives the instant the cooldown
## expires, matching the zombie. Add a telegraph on both when there are attack
## animations to hang one on.
func _swing(target: Node3D) -> void:
	_mark_in_combat()
	_play_swing()
	target.take_damage(attack_damage)
	# Health.died fires synchronously inside take_damage(), so the victim
	# already knows it is dead by the time this returns.
	if target.has_method("is_dead") and target.is_dead():
		killed.emit(target)
		_finish_engagement()


func _play_swing() -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_visual.position.z = 0.0
	# Forward is -Z, matching the node's facing convention.
	_swing_tween = create_tween()
	_swing_tween.tween_property(_visual, "position:z", -SWING_LUNGE, 0.08)
	_swing_tween.tween_property(_visual, "position:z", 0.0, 0.16)


func _tick_regen(delta: float) -> void:
	_regen_timer = maxf(_regen_timer - delta, 0.0)
	if _regen_timer > 0.0:
		return
	if health.current >= health.max_health:
		return
	health.heal(regen_per_second * delta)


## Both taking a hit and landing one count as combat, so a hero trading blows
## never regenerates mid-fight.
func _mark_in_combat() -> void:
	_regen_timer = regen_delay


# --- Movement helpers --------------------------------------------------------

func _travel(delta: float, speed: float) -> void:
	var next := _nav_agent.get_next_path_position()
	var direction := next - global_position
	direction.y = 0.0
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()
	_face(direction, delta)


## Every range test in this script measures horizontally, and they must all
## agree. `_reassess()` decides whether to repath and `_process_attack()`
## decides whether to swing, both against `attack_range`; if one of them counted
## the height difference and the other did not, they would disagree at the
## boundary and the hero would repath and swing in alternate ticks. Flat floors
## hide that today — the first ramp or ledge would not.
func _horizontal_distance_to(point: Vector3) -> float:
	var offset := point - global_position
	offset.y = 0.0
	return offset.length()


## Hold position but keep stepping the body, so gravity still settles it.
func _halt() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()


## Turn toward a horizontal direction. Forward is -Z (Godot's convention), so a
## rigged model drops in later without a compensating rotation.
func _face(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return
	direction = direction.normalized()
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


## Clamp a world point onto the navigation map, so an order is never
## unreachable — a click on the void outside the level becomes "walk as far
## that way as you can" instead of a path request that resolves to nothing.
func _on_navmesh(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, point)


# --- Picking things out of the world -----------------------------------------

## Resolve a screen position to a point on the ground.
##
## The raycast alone is not enough: it only collides with the ground layer, so
## a click on the dark background, past the edge of the level, or above a wall
## produces no hit at all. Dropping those clicks is what made a second click
## look like it was ignored — the hero silently kept walking to its previous
## destination. Falling back to the hero's ground plane means every click
## yields a point; the order it turns into then clamps it onto the navmesh.
##
## Returns a Vector3, or null if there is no camera to project from.
func _ground_point_at(screen_point: Vector2):
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_point)
	var direction := camera.project_ray_normal(screen_point)
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * RAY_LENGTH, GROUND_MASK
	)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		return result.position
	var ground := Plane(Vector3.UP, global_position.y)
	return ground.intersects_ray(origin, direction)


## The enemy a click means, if any.
##
## **Walls are in this ray's mask, and that is the whole point of it.** With
## enemies alone the ray tunnelled: clicking a wall with a zombie behind it
## resolved to an attack order on a zombie the player could not see, and the
## hero walked off to fight it. Including layer 2 makes the nearer surface win,
## which is what the renderer decides too, so a click can only name an enemy
## that is actually drawn.
##
## Not a general occlusion solve, and the reason is worth knowing: rock caps
## carry no collider on purpose (see scenes/map/CLAUDE.md), so a ray into a rock
## mass is stopped by the wall pieces bounding it rather than by the rock
## itself. Those sit on every rock/floor boundary at full wall height, so a
## descending click ray meets one on its way out — everything except a ray
## threading the corner gap where two of them meet.
func _target_at(screen_point: Vector2, ground_point) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_point)
	var direction := camera.project_ray_normal(screen_point)
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * RAY_LENGTH, ENEMY_MASK | SIGHT_BLOCKER_MASK
	)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		if _is_valid_target(result.collider):
			return result.collider
		# A wall got there first, so whatever is past it is off screen. The
		# click stays a ground order rather than becoming an attack.
		return null
	# The ray met neither enemy nor wall, so the click landed on open floor or
	# past the edge of the level. Only here is the slack radius safe to apply —
	# there is nothing between the camera and that ground to hide a zombie.
	if ground_point == null:
		return null
	return _nearest_enemy_to(ground_point, CLICK_SLACK)


## Nearest living enemy to a point, measured horizontally so a unit's height
## never decides which of two is closer. Returns null if none is within range.
##
## `require_sight` is true only for automatic acquisition, and it is measured
## from the hero rather than from `point` — the two are the same thing there.
## The click paths pass false on purpose: the player can only click something
## already drawn on screen, so demanding a second opinion from a raycast would
## only reject clicks the player could plainly see were valid.
func _nearest_enemy_to(point: Vector3, radius: float, require_sight := false) -> Node3D:
	var best: Node3D = null
	var best_distance := radius
	for candidate in get_tree().get_nodes_in_group(ENEMY_GROUP):
		if not _is_valid_target(candidate):
			continue
		var enemy := candidate as Node3D
		var offset := enemy.global_position - point
		offset.y = 0.0
		var distance := offset.length()
		if distance > best_distance:
			continue
		# Sight last: it is a raycast, and the cheap distance test has already
		# thrown out most of the group by the time we get here.
		if require_sight and not _can_see(enemy):
			continue
		best = enemy
		best_distance = distance
	return best


## Chest-to-chest ray against walls only, mirroring the zombie's.
##
## Without it the hero picks up targets through solid rock and walks off to
## fight something the player never saw — the same complaint scenes/enemies/
## records in reverse ("zombies detect the hero through solid rock, then appear
## round a corner for no visible reason"), and worse here, because this is the
## unit the player is supposed to be commanding.
func _can_see(target: Node3D) -> bool:
	var from := global_position + Vector3.UP * EYE_HEIGHT
	var to := target.global_position + Vector3.UP * EYE_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to, SIGHT_BLOCKER_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Everything this script assumes about an enemy, in one place: it is a live
## node in the tree, it is in the enemies group, and it is not already dead.
## Deliberately duck-typed — see the note at the top about the dependency
## direction between scenes/hero/ and scenes/enemies/.
func _is_valid_target(candidate) -> bool:
	if not is_instance_valid(candidate):
		return false
	var node := candidate as Node3D
	if node == null or not node.is_inside_tree():
		return false
	if not node.is_in_group(ENEMY_GROUP):
		return false
	if node.has_method("is_dead") and node.is_dead():
		return false
	return true


func _on_health_died() -> void:
	_dead = true
	_clear_orders()
	_set_attack_move_armed(false)
	velocity = Vector3.ZERO
	died.emit()
