class_name Hero
extends CharacterBody3D
## Click-to-move hero controller (issue #5).
##
## Right-click ("move_command") raycasts from the camera into the world and
## sets the NavigationAgent3D target. Left-click is deliberately left free for
## targeting/attacks (issue #11). The ray only collides with the ground layer,
## so clicking a wall orders a move to the floor behind it (RTS convention).

const SPEED := 6.0
const TURN_SPEED := 12.0

## Ground is physics layer 1; walls (layer 2) are excluded so move commands
## always land on walkable floor.
const GROUND_MASK := 1
const RAY_LENGTH := 1000.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_command"):
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		var mouse_pos := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mouse_pos)
		var target := origin + camera.project_ray_normal(mouse_pos) * RAY_LENGTH
		var query := PhysicsRayQueryParameters3D.create(origin, target, GROUND_MASK)
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if result:
			command_move_to(result.position)


## Public move order — also the entry point for future AI/skills/tests.
func command_move_to(world_point: Vector3) -> void:
	_nav_agent.target_position = world_point


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
