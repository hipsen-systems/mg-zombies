class_name OrderMarker
extends Node3D
## The ping that shows where an order landed (issue #67).
##
## A right-click used to produce movement and nothing else, which in a top-down
## view with the hero often off-centre makes a click that was *received* look
## identical to one that was dropped. `scenes/hero/` has a rule that every click
## produces an order, written because dropped clicks read as an unresponsive
## hero; this is the other half of it, because an order the player cannot see is
## the same experience as no order at all.
##
## [b]Green for a move, red for an attack-move[/b] — the RTS convention the whole
## game is styled after, and the one thing about this the player already knows
## before being told.
##
## [b]It is inert, exactly as selection is.[/b] It reads no state, is read by
## nothing, and holds no opinion about what the hero is doing — it is told where
## an order went and draws a ring there. That is what lets it be driven straight
## from the hero's order signals without becoming a second record of his orders.

## Life of one ping. Short: this answers "did that register", which is a question
## the player has stopped asking within about half a second.
const HOLD_TIME := 0.16
const FADE_TIME := 0.42

## How far the ring floats above the floor, matching the selection ring's
## clearance for the same reason — unit and marker origins both sit on the floor.
const GROUND_CLEARANCE := 0.06

## Ring sizes, in metres. It lands wide and shrinks onto the point, which is what
## makes the ping read as *arriving somewhere* rather than merely appearing.
const START_SCALE := 1.7
const END_SCALE := 1.0

## [b]These collide with `scenes/map/`'s zone markers, which is why the ring has
## a dark rim behind it.[/b] That folder paints the start cell green
## (0.3, 0.9, 0.4) and the boss cell red (0.95, 0.25, 0.2) — the exact constraint
## that pushed the selection ring to cyan and orange.
##
## The first version of this file argued the collision was acceptable: a ping is
## transient and animated where the selection ring is static, so motion should
## carry a hue difference that would defeat a still shape. **A screenshot of a
## move ping landing on the green plate showed nothing there at all.** The
## argument was not wrong about motion, but it was answering the wrong question —
## a marker that is invisible for the frame the player looks at it has already
## failed, whatever it does over the next half second.
##
## So the contrast is in the marker rather than in the palette, which keeps the
## one convention a new player arrives with (green means go, red means fight) and
## costs a second mesh. `Rim` is a slightly larger near-black torus a hair below
## the coloured one; it reads as an outline on pale floor and as the whole shape
## on a plate the same hue as the ring.
const MOVE_COLOUR := Color(0.36, 1.0, 0.42)
const ATTACK_COLOUR := Color(1.0, 0.3, 0.24)

@onready var _ring: MeshInstance3D = $Ring
@onready var _rim: MeshInstance3D = $Rim

var _material: StandardMaterial3D = null
var _rim_material: StandardMaterial3D = null
var _rim_alpha := 1.0
var _tween: Tween = null


func _ready() -> void:
	# Duplicated for the reason `scenes/enemies/` and the selection ring both
	# record: a scene's sub-resources are shared between instances, and this one
	# is recoloured and faded at runtime. One marker exists today; if that ever
	# stops being true the failure mode is silent.
	_material = _ring.get_surface_override_material(0).duplicate()
	_ring.set_surface_override_material(0, _material)
	_rim_material = _rim.get_surface_override_material(0).duplicate()
	_rim.set_surface_override_material(0, _rim_material)
	_rim_alpha = _rim_material.albedo_color.a
	hide()


## A move order landed at [param world_point]. Connected to
## [signal Hero.move_ordered].
func show_move(world_point: Vector3) -> void:
	_ping(world_point, MOVE_COLOUR)


## An attack-move order landed at [param world_point]. Connected to
## [signal Hero.attack_move_ordered].
func show_attack_move(world_point: Vector3) -> void:
	_ping(world_point, ATTACK_COLOUR)


## Drop a ping and let it fade.
##
## One marker re-used rather than an instance per click, and the tween is killed
## first: clicking again before the last ping has faded is the single most
## ordinary thing a player does with this, and it must show the *new* point
## rather than queue behind the old one.
func _ping(world_point: Vector3, colour: Color) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	global_position = world_point + Vector3.UP * GROUND_CLEARANCE
	scale = Vector3.ONE * START_SCALE
	_material.albedo_color = colour
	_material.emission = colour
	_set_alpha(1.0)
	show()

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector3.ONE * END_SCALE, HOLD_TIME + FADE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Fade starts after the hold, so the ping is at full strength for the moment
	# the player is actually looking for it.
	_tween.tween_method(_set_alpha, 1.0, 0.0, FADE_TIME).set_delay(HOLD_TIME)
	_tween.chain().tween_callback(hide)


func _set_alpha(alpha: float) -> void:
	_material.albedo_color.a = alpha
	# Emission does not read alpha, so a ring left glowing at zero opacity is a
	# bright ring on a transparent one. Dimming both is what actually fades it.
	_material.emission_energy_multiplier = alpha
	# The rim fades with the ring rather than on its own clock, or the outline
	# outlives the thing it is outlining — scaled by its authored opacity so the
	# .tscn stays the one place that decides how dark it is.
	_rim_material.albedo_color.a = alpha * _rim_alpha
