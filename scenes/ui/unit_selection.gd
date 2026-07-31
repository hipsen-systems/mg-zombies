class_name UnitSelection
extends Node3D
## Which unit the player is currently inspecting (issue #36), and the ring that
## marks it in the 3D view so the world and the info bar always agree.
##
## [b]Selection is inert.[/b] It issues no orders, deals no damage, and no
## gameplay script reads it — scenes/hero/ never learns what is selected. That is
## the whole point: an RTS where inspecting a unit also swings at it is unusable,
## so the player can read an enemy's numbers with a fight already under way and
## nothing about the fight changes.
##
## [b]The hero owns the left mouse button, not this node.[/b] scenes/hero/ owns
## the command scheme the button belongs to, so it decides whether a click was
## taken by the armed attack command and emits [signal Hero.select_clicked] only
## for the ones it did not take. Reading the input here as well would put two
## nodes on one button and make the outcome depend on which of them
## _unhandled_input happened to reach first — with the armed click landing as
## both an attack and a selection, or neither, depending on node order.
##
## The unit contract is duck-typed on purpose, exactly as scenes/hero/ treats
## enemies: anything with unit_info() and a Health child can be selected, so a
## boss or a second enemy type needs no change in here.

## Emitted whenever the selected unit changes. Never carries null — see
## [method select_unit].
signal selection_changed(unit: Node3D)

## Hero (physics layer 3) and enemies (layer 4) — see the table in
## scenes/CLAUDE.md. Walls (layer 2) ride along in the query so a unit standing
## behind rock cannot be clicked through it, the same rule scenes/hero/ applies
## to its attack-targeting ray.
const SELECTABLE_MASK := 4 | 8
const SIGHT_BLOCKER_MASK := 2
const RAY_LENGTH := 1000.0

## How far above the unit's feet the ring floats. Unit origins sit on the floor,
## so this is clearance over the floor tile and nothing more.
const RING_HEIGHT := 0.06

## Cyan for the hero, orange for anything else.
##
## [b]Deliberately not the RTS-classic green and red[/b], and the reason is a
## constraint from scenes/map/: it paints the start cell green and the boss cell
## red as floor markers. A green ring is invisible on the green start marker —
## which is where the hero stands for the first seconds of every run, exactly
## when the player is working out that the ring means something — and a red ring
## would vanish the same way on the boss cell the moment issue #39 puts something
## selectable there. Cyan and orange collide with neither, and still read as
## friendly and hostile. If those markers are ever recoloured, re-check these.
const RING_COLOUR_FRIENDLY := Color(0.25, 0.85, 1.0)
const RING_COLOUR_HOSTILE := Color(1.0, 0.55, 0.15)

## The unit selection falls back to. Wired from the scene, the way the camera's
## target is: there is never "nothing selected", because a bar with no content
## is dead screen space.
@export var hero: Node3D

var _selected: Node3D = null
var _health: Health = null

@onready var _ring: MeshInstance3D = $Ring
var _ring_material: StandardMaterial3D = null


func _ready() -> void:
	# Duplicate the material for the same reason scenes/enemies/ does: a scene's
	# sub-resources are shared between instances, and this one is recoloured at
	# runtime. There is only one ring today, but the failure mode if that ever
	# stops being true is silent.
	_ring_material = _ring.get_surface_override_material(0).duplicate()
	_ring.set_surface_override_material(0, _ring_material)
	_ring.visible = false


## Keep the ring under the unit. Cheap enough to run every frame, and a moving
## target makes anything slower visibly lag behind the unit it is marking.
func _process(_delta: float) -> void:
	_place_ring()


## Also called the moment the selection changes, not left to the next frame:
## otherwise the ring spends one frame still drawn around the previous unit,
## which is exactly the frame the player is looking at it.
func _place_ring() -> void:
	if not is_instance_valid(_selected):
		_ring.visible = false
		return
	_ring.visible = true
	_ring.global_position = _selected.global_position + Vector3.UP * RING_HEIGHT


## What is selected right now. Public for the HUD and for tests.
func selected_unit() -> Node3D:
	return _selected


## Resolve a click to a unit and select it. Ground, sky, a wall, or a corpse all
## mean "the hero" — the fallback is what keeps the bar from ever being empty.
func select_at(screen_point: Vector2) -> void:
	select_unit(_unit_at(screen_point))


## Select a unit, or the hero if it is null or no longer selectable.
func select_unit(unit: Node3D) -> void:
	if not _is_selectable(unit):
		unit = hero
	if unit == _selected:
		return
	_stop_watching()
	_selected = unit
	_start_watching()
	_ring_material.albedo_color = (
		RING_COLOUR_FRIENDLY if _selected == hero else RING_COLOUR_HOSTILE
	)
	_place_ring()
	selection_changed.emit(_selected)


func _start_watching() -> void:
	_health = _health_of(_selected)
	if _health != null:
		_health.died.connect(_on_selected_died)


func _stop_watching() -> void:
	if _health != null and _health.died.is_connected(_on_selected_died):
		_health.died.disconnect(_on_selected_died)
	_health = null


## The selected unit died, so the bar would be showing a corpse. Fall back to
## the hero — except when it *is* the hero, where there is nothing to fall back
## to and scenes/main.gd is already restarting the run.
func _on_selected_died() -> void:
	if _selected == hero:
		return
	select_unit(hero)


## The unit a click means, if any.
##
## Walls are in the mask deliberately, and the reason is the bug scenes/hero/
## records: a ray masked on units alone tunnels through rock and names something
## the player has never seen. Here that is only a wrong info panel rather than a
## wrong order, but it is the same wrong answer, and the two click paths
## disagreeing about what is visible would be worse than either rule alone.
##
## No grace radius, unlike the attack click's CLICK_SLACK. Missing an attack is
## expensive — the order silently becomes a walk into a pack — while missing a
## selection just falls back to the hero, which is one click to undo. Slack here
## would instead make the cheap escape hatch unreliable: clicking the floor
## beside a zombie to get back to the hero would keep selecting the zombie.
func _unit_at(screen_point: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_point)
	var direction := camera.project_ray_normal(screen_point)
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * RAY_LENGTH, SELECTABLE_MASK | SIGHT_BLOCKER_MASK
	)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result:
		return null
	# A wall got there first, so whatever is behind it is off screen.
	return result.collider as Node3D


## Everything this node assumes about a selectable unit, in one place. Note that
## a dead zombie clears its collision layer, so a corpse cannot be raycast in the
## first place; the is_dead() test catches the frame between the killing blow and
## that clear, and anything selected by name rather than by click.
func _is_selectable(unit) -> bool:
	if not is_instance_valid(unit):
		return false
	var node := unit as Node3D
	if node == null or not node.is_inside_tree():
		return false
	if not node.has_method("unit_info"):
		return false
	if node.has_method("is_dead") and node.is_dead():
		return false
	return true


## Units keep their hit points in a Health child (scenes/components/), and both
## the info bar and the death fallback need it. Fetched with get() rather than a
## property access because the unit is only ever typed as Node3D here.
func _health_of(unit: Node3D) -> Health:
	if not is_instance_valid(unit):
		return null
	return unit.get("health") as Health
