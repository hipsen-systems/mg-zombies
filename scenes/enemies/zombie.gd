class_name Zombie
extends CharacterBody3D
## The basic zombie enemy (issue #7): roams its home area, notices the hero,
## chases him down and swings in melee — then gives up and shambles home if he
## runs far enough.
##
## Four radii shape the behaviour, and they are deliberately different things:
##
## - [member roam_radius]   — the patch it wanders while idle, around the spot
##                            it spawned on ("home").
## - [member detection_radius] — how far it can *notice* the hero. Requires line
##                            of sight, so rock walls hide him.
## - [member aggro_radius]  — how far it will *keep* chasing once it has
##                            committed. Larger than detection on purpose: you
##                            cannot shake a zombie by stepping one metre back
##                            out of its notice range.
## - [member leash_radius]  — the hard tether to home. Whatever the hero does,
##                            a zombie can never be dragged further than this
##                            from where it spawned, so encounters stay where
##                            the map author put them.
##
## All of them are per-instance exports: a corridor shambler and a boss-room
## guard are the same scene with different numbers.

## Emitted once when this zombie's health hits zero, before the corpse fades.
## The hook issue #8 will use to award XP.
signal died(zombie: Zombie)

enum State {
	## Wandering the home patch. The only state that can acquire a target.
	ROAM,
	## Noticed the hero, standing up and turning to face him — a readable beat
	## before the charge rather than an instant snap into a sprint.
	ALERT,
	## Committed. Repaths to the hero until he leaves aggro or leash range.
	CHASE,
	## In melee range, swinging on cooldown.
	ATTACK,
	## Leashed or lost the hero; walking home and ignoring him on the way.
	RETURN,
	## Dead. No movement, no collision, corpse fading out.
	DEAD,
}

## Senses (distance checks and the line-of-sight ray) run on a fixed tick rather
## than every frame — a shambling zombie does not need 60 Hz reflexes, and this
## keeps the cost flat as the maze fills up with them.
const SENSE_INTERVAL := 0.2

## Roughly chest height on the 1.8-unit capsule; the line-of-sight ray is cast
## between chest points so it clears the floor tiles.
const EYE_HEIGHT := 1.2

## Walls and static obstacles (physics layer 2 — see scenes/CLAUDE.md).
const SIGHT_BLOCKER_MASK := 2

const TURN_SPEED := 6.0

const HERO_GROUP := "hero"

## How long the corpse lies there before it sinks and frees itself.
const CORPSE_LINGER := 2.0

@export_group("Roaming")
## Radius of the patch this zombie wanders while idle, centred on its spawn.
@export var roam_radius := 6.0
## Idle pause between wander destinations, so a group does not move as one.
@export var roam_pause_min := 1.5
@export var roam_pause_max := 4.5
@export var roam_speed := 1.3

@export_group("Aggro")
## Range at which the hero is noticed. Needs line of sight.
@export var detection_radius := 12.0
## Range at which an already-committed chase is abandoned. Keep it above
## [member detection_radius] or the zombie will flicker in and out of aggro at
## the boundary.
@export var aggro_radius := 18.0
## Hard tether from the spawn point, regardless of where the hero is.
@export var leash_radius := 26.0
## Beat between noticing the hero and charging him.
@export var alert_delay := 0.5
@export var chase_speed := 3.4

@export_group("Combat")
@export var attack_range := 2.0
@export var attack_damage := 9.0
@export var attack_cooldown := 1.3

var _state: State = State.ROAM
var _home := Vector3.ZERO
var _hero: Hero = null
var _sense_timer := 0.0
var _roam_pause := 0.0
var _alert_timer := 0.0
var _attack_timer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var health: Health = $Health
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: Node3D = $Visual


func _ready() -> void:
	# Home is wherever the spawner dropped this zombie, so a map author places
	# an encounter simply by putting a spawn marker on a cell.
	_home = global_position
	health.died.connect(_on_health_died)
	# Stagger the sense ticks so a room full of zombies does not raycast on the
	# same frame, and so they never move in lockstep.
	_sense_timer = randf() * SENSE_INTERVAL
	_roam_pause = randf_range(roam_pause_min, roam_pause_max)

	# NavigationServer3D syncs its maps at the end of a physics frame, and
	# scenes/main.gd bakes the navmesh in its own _ready(). Querying before that
	# sync returns the map origin, which would send every zombie walking to the
	# middle of the maze. Wait one frame before the first path request.
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_nav_agent.target_position = global_position


func is_dead() -> bool:
	return _state == State.DEAD


## Damage entry point. Attackers call this rather than reaching into the Health
## child, so the zombie stays free to react to being hit later (stagger, or
## waking up an unaware zombie that was shot from behind).
func take_damage(amount: float) -> void:
	if is_dead():
		return
	health.take_damage(amount)
	# Being hit aggroes regardless of range, sight or leash — otherwise the
	# hero could whittle a zombie down from outside its detection radius.
	if not health.is_dead() and _state in [State.ROAM, State.ALERT, State.RETURN]:
		_enter_chase()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if _state == State.DEAD:
		_stand_still()
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)

	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = SENSE_INTERVAL
		_think()

	match _state:
		State.ROAM:
			_process_roam(delta)
		State.ALERT:
			_process_alert(delta)
		State.CHASE, State.RETURN:
			_move_along_path(delta, chase_speed if _state == State.CHASE else roam_speed)
		State.ATTACK:
			_process_attack(delta)


## Transitions and path targets. Runs on the sense tick, not every frame.
func _think() -> void:
	var hero := _find_hero()
	var hero_alive := hero != null and not hero.is_dead()
	var to_hero := INF
	if hero_alive:
		to_hero = global_position.distance_to(hero.global_position)
	var from_home := global_position.distance_to(_home)

	match _state:
		State.ROAM:
			if hero_alive and to_hero <= detection_radius and _can_see(hero):
				_enter_alert()

		State.ALERT:
			if not hero_alive or to_hero > detection_radius:
				_enter_roam()

		State.CHASE, State.ATTACK:
			if not hero_alive or to_hero > aggro_radius or from_home > leash_radius:
				_enter_return()
			elif _state == State.CHASE and to_hero <= attack_range:
				_state = State.ATTACK
			elif _state == State.ATTACK and to_hero > attack_range:
				_enter_chase()
			else:
				_nav_agent.target_position = _on_navmesh(hero.global_position)

		State.RETURN:
			# The hero is deliberately ignored until home is reached, so he
			# cannot chain-pull a zombie across the map by re-entering its
			# detection radius at the edge of the leash.
			if from_home <= roam_radius:
				_enter_roam()


func _process_roam(delta: float) -> void:
	if not _nav_agent.is_navigation_finished():
		_move_along_path(delta, roam_speed)
		return
	_stand_still()
	_roam_pause -= delta
	if _roam_pause <= 0.0:
		_roam_pause = randf_range(roam_pause_min, roam_pause_max)
		_pick_roam_target()


func _process_alert(delta: float) -> void:
	_stand_still()
	var hero := _find_hero()
	if hero != null:
		_face(hero.global_position - global_position, delta)
	_alert_timer -= delta
	if _alert_timer <= 0.0:
		_enter_chase()


func _process_attack(delta: float) -> void:
	_stand_still()
	var hero := _find_hero()
	if hero == null or hero.is_dead():
		return
	_face(hero.global_position - global_position, delta)
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	hero.take_damage(attack_damage)


func _enter_roam() -> void:
	_state = State.ROAM
	_roam_pause = randf_range(roam_pause_min, roam_pause_max)
	_nav_agent.target_position = global_position


func _enter_alert() -> void:
	_state = State.ALERT
	_alert_timer = alert_delay


func _enter_chase() -> void:
	_state = State.CHASE
	var hero := _find_hero()
	if hero != null:
		_nav_agent.target_position = _on_navmesh(hero.global_position)


func _enter_return() -> void:
	_state = State.RETURN
	_nav_agent.target_position = _on_navmesh(_home)


func _pick_roam_target() -> void:
	# sqrt() spreads destinations evenly over the disc instead of bunching them
	# around home.
	var angle := randf() * TAU
	var distance := sqrt(randf()) * roam_radius
	var point := _home + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	_nav_agent.target_position = _on_navmesh(point)


## Clamp a world point onto the navigation map, the same way Hero.command_move_to
## does: a wander target inside solid rock becomes the nearest reachable spot
## instead of a path request that resolves to nothing.
func _on_navmesh(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, point)


func _move_along_path(delta: float, speed: float) -> void:
	if _nav_agent.is_navigation_finished():
		_stand_still()
		return
	var next := _nav_agent.get_next_path_position()
	var direction := next - global_position
	direction.y = 0.0
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()
	_face(direction, delta)


## Hold position but keep stepping the body, so gravity still settles it.
func _stand_still() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()


## Turn toward a horizontal direction. Forward is -Z, matching the hero and
## Godot's convention, so a rigged model drops in without a fix-up rotation.
func _face(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return
	direction = direction.normalized()
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)


func _find_hero() -> Hero:
	if is_instance_valid(_hero) and _hero.is_inside_tree():
		return _hero
	_hero = get_tree().get_first_node_in_group(HERO_GROUP) as Hero
	return _hero


## Chest-to-chest ray against walls only. Without this a zombie two cells away
## through solid rock would come round the corner at you for no visible reason.
func _can_see(hero: Hero) -> bool:
	var from := global_position + Vector3.UP * EYE_HEIGHT
	var to := hero.global_position + Vector3.UP * EYE_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to, SIGHT_BLOCKER_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_health_died() -> void:
	_state = State.DEAD
	velocity = Vector3.ZERO
	# Stop being an obstacle at once: a corpse the hero cannot walk past would
	# plug a one-cell corridor for the whole fade.
	collision_layer = 0
	collision_mask = 0
	died.emit(self)

	var tween := create_tween()
	tween.tween_property(_visual, "rotation:x", -PI * 0.5, 0.35)
	tween.tween_interval(CORPSE_LINGER)
	tween.tween_property(_visual, "position:y", -2.0, 0.6)
	tween.tween_callback(queue_free)
