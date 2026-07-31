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
## keeps the cost flat as the level fills up with them.
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

## Damage feedback: the body washes out for a moment, then fades back. Short on
## purpose — long enough to read at a glance, short enough that a zombie taking
## hits on a 0.9 s cooldown is not permanently pink.
const HIT_FLASH_TIME := 0.12
const HIT_FLASH_COLOUR := Color(1.0, 0.88, 0.88)

## What the unit info bar calls it. Per-instance like every stat below, so the
## boss-room guard the class docs describe can announce itself without a new
## scene or a new script.
@export var display_name := "Zombie"

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

@export_group("Regeneration")
## Seconds without taking damage before health starts coming back.
@export var regen_delay := 6.0
@export var regen_per_second := 3.0

var _state: State = State.ROAM
var _home := Vector3.ZERO
var _hero: Hero = null
var _sense_timer := 0.0
var _roam_pause := 0.0
var _alert_timer := 0.0
var _attack_timer := 0.0
var _regen_timer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _body_material: StandardMaterial3D = null
var _base_albedo := Color.WHITE
var _flash_tween: Tween = null

@onready var health: Health = $Health
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: Node3D = $Visual
@onready var _body_mesh: MeshInstance3D = $Visual/BodyMesh


func _ready() -> void:
	# Home is wherever the spawner dropped this zombie, so a map author places
	# an encounter simply by putting a spawn marker on a cell.
	_home = global_position
	health.died.connect(_on_health_died)
	_claim_own_material()
	# Stagger the sense ticks so a room full of zombies does not raycast on the
	# same frame, and so they never move in lockstep.
	_sense_timer = randf() * SENSE_INTERVAL
	_roam_pause = randf_range(roam_pause_min, roam_pause_max)

	# NavigationServer3D syncs its maps at the end of a physics frame, and
	# scenes/main.gd bakes the navmesh in its own _ready(). Querying before that
	# sync returns the map origin, which would send every zombie walking to the
	# middle of the level. Wait one frame before the first path request.
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_nav_agent.target_position = global_position


func is_dead() -> bool:
	return _state == State.DEAD


## Headline stats for the unit info bar (scenes/ui/, issue #36).
##
## The travel speed reported is [member chase_speed], not [member roam_speed]:
## the number a player wants when they click a zombie is how fast it closes on
## them, not how fast it shambles when it has not seen them. Read-only and
## display-only — selecting a zombie does nothing to it.
func unit_info() -> Dictionary:
	return {
		"name": display_name,
		"damage": attack_damage,
		"attack_cooldown": attack_cooldown,
		"move_speed": chase_speed,
	}


## Damage entry point. Attackers call this rather than reaching into the Health
## child, so the zombie stays free to react to being hit later (stagger, or
## waking up an unaware zombie that was shot from behind).
func take_damage(amount: float) -> void:
	if is_dead():
		return
	_regen_timer = regen_delay
	# Flash before applying the damage, not after: a killing blow runs
	# _on_health_died() synchronously inside take_damage(), and a flash started
	# after that would be repainting a corpse.
	_flash_hit()
	health.take_damage(amount)
	# Being hit aggroes regardless of range, sight or leash — otherwise the
	# hero could whittle a zombie down from outside its detection radius.
	if not health.is_dead() and _state in [State.ROAM, State.ALERT, State.RETURN]:
		_enter_chase()


func _physics_process(delta: float) -> void:
	# A dead body is not simulated at all: the death tween owns every remaining
	# motion, and _on_health_died() has cleared the collision mask, so there is
	# nothing left for it to stand on. This return must stay *above* the gravity
	# block. Below it, is_on_floor() is false from the frame of death onward and
	# never recovers, velocity.y accumulates unbounded, and _stand_still() —
	# which zeroes x and z but never y — drives the corpse through the floor.
	# Measured before this fix: 1.1 units under the map after 0.5 s, 36 after
	# 2.75 s, so the death animation was never once seen.
	if _state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_tick_regen(delta)

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


## Out-of-combat regeneration.
##
## Two conditions, and they cover different escapes. The timer stops a zombie
## healing between the hero's swings. The state check stops one healing while it
## is chasing him — a fight the player is slowly winning must not turn into one
## they cannot win at all, and a zombie that heals mid-chase does exactly that.
## Together they mean the only way to undo damage is to actually break away,
## which is what closes the chip-and-retreat exploit the leash would otherwise
## hand the hero.
func _tick_regen(delta: float) -> void:
	_regen_timer = maxf(_regen_timer - delta, 0.0)
	if _regen_timer > 0.0:
		return
	if not (_state == State.ROAM or _state == State.RETURN):
		return
	if health.current >= health.max_health:
		return
	health.heal(regen_per_second * delta)


## Give this zombie its own copy of the body material.
##
## The material is a sub-resource of zombie.tscn, and Godot shares a scene's
## sub-resources across every instance of it — so tinting one zombie would tint
## the entire horde. Duplicating in code rather than ticking
## resource_local_to_scene on the resource: an editor round-trip can quietly
## clear a flag, and nothing would fail until someone noticed the whole map
## flashing at once.
func _claim_own_material() -> void:
	var material := _body_mesh.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		return
	_body_material = material.duplicate()
	_body_mesh.set_surface_override_material(0, _body_material)
	_base_albedo = _body_material.albedo_color


func _flash_hit() -> void:
	if _body_material == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_body_material.albedo_color = HIT_FLASH_COLOUR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_body_material, "albedo_color", _base_albedo, HIT_FLASH_TIME)


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
	# Go inert. Note what this does *not* do, because the original comment here
	# claimed it and cross-review disproved it: clearing the layer does not stop
	# the corpse blocking a corridor, because nothing masks the enemy layer in
	# the first place (see the table in scenes/CLAUDE.md) — the hero and other
	# zombies could always walk through it, alive or dead. Clearing the mask is
	# the half that changes behaviour, and _physics_process must return early
	# for the dead precisely because it does.
	collision_layer = 0
	collision_mask = 0
	died.emit(self)

	var tween := create_tween()
	tween.tween_property(_visual, "rotation:x", -PI * 0.5, 0.35)
	tween.tween_interval(CORPSE_LINGER)
	tween.tween_property(_visual, "position:y", -2.0, 0.6)
	tween.tween_callback(queue_free)
