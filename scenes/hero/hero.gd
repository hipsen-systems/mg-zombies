class_name Hero
extends CharacterBody3D
## Click-to-move hero controller (issue #5).
##
## Right-click ("move_command") raycasts from the camera into the world and
## sets the NavigationAgent3D target. Left-click is deliberately left free for
## targeting/attacks (issue #11). The ray only collides with the ground layer,
## so clicking a wall orders a move to the floor behind it (RTS convention).
##
## Every move command supersedes the one before it immediately — see
## command_move_to().

signal move_ordered(world_point: Vector3)

const SPEED := 6.0
const TURN_SPEED := 12.0

## Ground is physics layer 1; walls (layer 2) are excluded so move commands
## always land on walkable floor.
const GROUND_MASK := 1
const RAY_LENGTH := 1000.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("move_command"):
		return
	# Use the position carried by the click itself rather than the live mouse
	# position: the two can differ by the time the event is handled, and it
	# keeps this path deterministic for headless tests.
	var screen_point := (event as InputEventMouseButton).position
	var target = _ground_point_at(screen_point)
	if target != null:
		command_move_to(target)


## Resolve a screen position to a point on the ground.
##
## The raycast alone is not enough: it only collides with the ground layer, so
## a click on the dark background, past the edge of the level, or above a wall
## produces no hit at all. Dropping those clicks is what made a second click
## look like it was ignored — the hero silently kept walking to its previous
## destination. Falling back to the hero's ground plane means every click
## yields a point; command_move_to() then clamps it onto the navmesh.
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


## Public move order — also the entry point for future AI/skills/tests.
##
## Issuing an order cancels the previous one outright: the target is replaced
## (NavigationAgent3D repaths on the next query) and the carried-over horizontal
## velocity is dropped so the hero cannot coast another frame along the
## abandoned heading. Rapid re-clicking therefore reads as an instant redirect.
func command_move_to(world_point: Vector3) -> void:
	# Clamp onto the navigation map so an order is never unreachable — a click
	# on the void outside the level becomes "walk as far that way as you can"
	# instead of a path request that resolves to nothing.
	var map := get_world_3d().navigation_map
	var reachable := NavigationServer3D.map_get_closest_point(map, world_point)
	_nav_agent.target_position = reachable
	velocity.x = 0.0
	velocity.z = 0.0
	move_ordered.emit(reachable)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if _nav_agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var next := _nav_agent.get_next_path_position()
	var direction := next - global_position
	direction.y = 0.0
	direction = direction.normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	move_and_slide()

	# Face the movement direction (-Z is forward, matching Godot's convention
	# so a rigged model can be dropped in later without a compensating rotation).
	if direction.length_squared() > 0.0:
		var target_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)
