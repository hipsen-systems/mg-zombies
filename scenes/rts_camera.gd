class_name RTSCamera
extends Camera3D
## Fixed-angle RTS-style follow camera (issues #5, #43).
##
## The angle is defined entirely by where the camera node is placed in the
## scene relative to its target: _ready() captures that offset and aims at the
## target once, then only translates — never rotates — so the view keeps the
## classic StarCraft/Warcraft fixed perspective.
##
## Given the level's bounds it also stops following once the frame would run
## off the edge of the map, the way an RTS camera does. Without that the hero
## can stand near an edge with the void filling a large part of the screen —
## which is what he does at spawn, since the start cell sits near the south
## edge and the camera stands further south still (issue #43).

@export var target: Node3D
@export var follow_speed := 8.0

## How far the bounds may push the target off centre, as a fraction of the
## frame. **The clamp yields to this, not the other way round**, and that is
## the whole reason this constant exists rather than the camera simply fitting
## its view inside the level. On a map only a little wider than the view — this
## one is 176 across against a ~140-wide frame — fitting the frame exactly means
## sliding the camera far enough sideways to carry the hero off the screen
## entirely. Measured, not predicted: the first version of this did exactly
## that at spawn, putting him 158 px past the left edge of a 1152 px window.
##
## So void at the edge of the world is treated as the cosmetic problem it is,
## and losing sight of the unit you control as the real one.
##
## 0.15 was picked off screenshots at the two corners the level actually has.
## Higher is not better: at 0.25 the spawn frame loses its void but spends it
## on a screenful of blank rock with the hero pinned to the left edge, which is
## a worse picture than the small dark wedge 0.15 leaves in the far corner.
const MAX_TARGET_DRIFT := 0.15

var _offset := Vector3.ZERO
## The authored viewing angle, captured once and reasserted rather than
## recomputed — see snap_to_target() for why it can no longer be re-derived
## from where the target is standing.
var _aim := Basis.IDENTITY
## World XZ rectangle the view is kept inside; empty until set_bounds().
var _bounds := Rect2()
var _bounded := false


func _ready() -> void:
	_offset = global_position - target.global_position
	look_at(target.global_position)
	_aim = global_basis


## Keep the view inside [param level_bounds] — world X on the rect's x axis,
## world Z on its y, which is what LevelMap.bounds() returns.
##
## Handed in rather than read off the map, so this stays a camera and not
## something that knows what a level is; main.gd owns that seam, the same way
## it decides what stands on the map's spawn markers.
##
## Call it before the first snap_to_target(), or the opening frame is the one
## unclamped frame of the run — and that frame is the whole of issue #43.
func set_bounds(level_bounds: Rect2) -> void:
	_bounds = level_bounds
	_bounded = level_bounds.has_area()


## Jump straight to the target instead of gliding to it. Call this after
## teleporting the target — the hero is spawned at the map's start cell in
## main.gd, which happens after this _ready(), and without a snap the camera
## would visibly sail across the map on the first frames.
##
## Restores the authored angle rather than re-aiming at the target. Aiming used
## to be equivalent: the camera sat at exactly `target + _offset`, so looking at
## the target always reproduced the angle _ready() captured. Bounds break that
## identity — a clamped camera is deliberately somewhere else — and look_at()
## would then tilt the view by however much the clamp is holding it back,
## turning a fixed-perspective camera into one that pitches near a map edge.
func snap_to_target() -> void:
	global_position = _clamped(target.global_position + _offset)
	global_basis = _aim


func _physics_process(delta: float) -> void:
	var desired := _clamped(target.global_position + _offset)
	# Exponential smoothing that is stable regardless of frame rate.
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))


## Where the camera should actually sit, given it would rather be at
## [param desired] and the level ends where it does.
##
## Clamping the *destination* and then smoothing toward it is what makes the
## camera glide to a halt against an edge; clamping the smoothed result instead
## would let it keep pressing into the boundary and stop dead there.
func _clamped(desired: Vector3) -> Vector3:
	if not _bounded:
		return desired
	var correction := _bounds_correction(desired)
	# Priced one axis at a time, because the two cost wildly different amounts
	# here and a shared budget would spend them together: this level has depth
	# to spare and almost no width to spare, so the south edge — which costs
	# about a metre of drift to fix — would be throttled by the west edge, which
	# cannot be fixed at all. Separately, the cheap one is simply free.
	for axis in 2:
		if correction[axis] == 0.0:
			continue
		var alone := Vector2.ZERO
		alone[axis] = correction[axis]
		correction[axis] *= _affordable(desired, alone)
	return desired + Vector3(correction.x, 0.0, correction.y)


## How far the camera would have to move from [param from] for its view to stop
## running off the level, as a world XZ offset. Zero when it already fits.
func _bounds_correction(from: Vector3) -> Vector2:
	var view := _ground_view(from)
	var correction := Vector2.ZERO
	for axis in 2:
		if view.size[axis] >= _bounds.size[axis]:
			# The frame is larger than the level on this axis, so no position
			# hides the void — centre the level instead and split what is left
			# between the two edges rather than banking it all against one.
			correction[axis] = _bounds.get_center()[axis] - view.get_center()[axis]
		elif view.position[axis] < _bounds.position[axis]:
			correction[axis] = _bounds.position[axis] - view.position[axis]
		elif view.end[axis] > _bounds.end[axis]:
			correction[axis] = _bounds.end[axis] - view.end[axis]
	return correction


## The fraction of [param correction] that can be applied before the target
## drifts further off centre than MAX_TARGET_DRIFT allows. 1.0 whenever the
## correction is cheap, which on this map is everywhere except the edges.
##
## Measured in pixels rather than world units on purpose: a world-space budget
## would have to be expressed against the view, and the view is a trapezoid —
## a metre near the bottom of the screen costs several times the pixels a metre
## at the top does, which is exactly the difference between a hero pushed
## slightly off centre and a hero pushed out of frame.
##
## The measurement leans on the fixed angle: moving the camera by c projects the
## target exactly where moving the *target* by -c would, so two unprojections
## price a correction the camera has not made yet. Scaling the answer back
## linearly is an approximation — perspective is not linear in the shift, and
## it overshoots the budget by about 15% at the spawn corner. Left as is
## deliberately: this is a comfort threshold read off screenshots, not a
## boundary anything depends on, so iterating it would buy precision about a
## number that was never precise.
func _affordable(from: Vector3, correction: Vector2) -> float:
	# Where the target sits now, expressed as a point in front of *this* camera.
	var here := target.global_position - (from - global_position)
	var moved := here - Vector3(correction.x, 0.0, correction.y)
	var drift := (unproject_position(moved) - unproject_position(here)).abs()
	var budget := get_viewport().get_visible_rect().size * MAX_TARGET_DRIFT
	var affordable := 1.0
	for axis in 2:
		if drift[axis] > budget[axis]:
			affordable = minf(affordable, budget[axis] / drift[axis])
	return affordable


## The patch of ground this camera would show from [param from], as a world XZ
## rectangle. The ground plane is the one the target stands on.
##
## Measured by casting the four screen corners rather than derived from fov and
## aspect, so it stays correct whatever the window is doing — the void in issue
## #43 grew with the window, and a hand-tuned margin would have had that same
## bug. A pitched camera sees a trapezoid; its bounding box is what gets
## clamped, which errs toward showing less void rather than more.
##
## Only the ray *directions* are taken from the current transform, and those
## come from the basis alone — which never changes. That is what makes this
## valid for a position the camera has not moved to yet.
func _ground_view(from: Vector3) -> Rect2:
	var screen := get_viewport().get_visible_rect().size
	var height := from.y - target.global_position.y
	var low := Vector2.INF
	var high := -Vector2.INF
	for corner in [Vector2.ZERO, Vector2(screen.x, 0.0), Vector2(0.0, screen.y), screen]:
		var direction := project_ray_normal(corner)
		if direction.y >= -0.001:
			# That corner is on or above the horizon, so it has no ground under
			# it and there is no frame to fit inside the level. Fall back to
			# keeping the camera itself over the map. Only reachable if the
			# authored pitch or the fov is changed enough to put sky on screen.
			return Rect2(Vector2(from.x, from.z), Vector2.ZERO)
		var ground := direction * (height / -direction.y)
		var point := Vector2(from.x + ground.x, from.z + ground.z)
		low = low.min(point)
		high = high.max(point)
	return Rect2(low, high - low)
