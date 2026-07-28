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


func _physics_process(delta: float) -> void:
	var desired := target.global_position + _offset
	# Exponential smoothing that is stable regardless of frame rate.
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
