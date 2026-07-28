extends Node3D
## Game entry scene (issue #5).
##
## Bakes the navmesh at runtime so the hand-authored level geometry in the
## scene stays the single source of truth (no stale baked data in the .tscn).
## The bake is synchronous (on_thread = false) because the web export has
## thread support disabled.

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	_nav_region.bake_navigation_mesh(false)
