class_name RTSCamera
extends Camera3D
## Fixed-angle RTS-style follow camera (issue #5).
##
## The angle is defined entirely by where the camera node is placed in the
## scene relative to its target: _ready() captures that offset and aims at the
## target once, then only translates — never rotates — so the view keeps the
## classic StarCraft/Warcraft fixed perspective.

@export var target: Node3D
@export var follow_speed := 8.0

var _offset := Vector3.ZERO


func _ready() -> void:
	_offset = global_position - target.global_position
	look_at(target.global_position)


## Jump straight to the target instead of gliding to it. Call this after
## teleporting the target — the hero is spawned at the map's start cell in
## main.gd, which happens after this _ready(), and without a snap the camera
## would visibly sail across the map on the first frames.
##
## Re-aims as well as moves: _ready() aimed at wherever the target was sitting
## in the .tscn, which is the wrong point once it has been teleported. The
## offset is unchanged, so the fixed viewing angle is preserved.
func snap_to_target() -> void:
	global_position = target.global_position + _offset
	look_at(target.global_position)


func _physics_process(delta: float) -> void:
	var desired := target.global_position + _offset
	# Exponential smoothing that is stable regardless of frame rate.
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
