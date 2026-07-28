extends Node3D
## Game entry scene (issues #5, #6).
##
## Owns the order the level comes up in: the maze builds itself in its own
## _ready() (children run first), then this script places the hero on the maze's
## start cell and bakes the navmesh over the geometry that now exists.
##
## The bake is synchronous (on_thread = false) because the web export has
## thread support disabled.

## Spawn the hero just above the floor surface and let gravity settle it, rather
## than guessing the exact tile height.
const SPAWN_CLEARANCE := 0.3

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _maze: Maze = $NavigationRegion3D/Maze
@onready var _hero: Hero = $Hero
@onready var _camera: RTSCamera = $RTSCamera


func _ready() -> void:
	_hero.global_position = _maze.start_position() + Vector3(0, SPAWN_CLEARANCE, 0)
	_camera.snap_to_target()
	_nav_region.bake_navigation_mesh(false)
