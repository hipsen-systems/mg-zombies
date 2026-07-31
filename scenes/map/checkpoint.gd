class_name Checkpoint
extends Node3D
## A respawn pad, laid on the `C` cells of the level layout (issue #38).
##
## One node is one checkpoint, which may cover several cells: LevelMap groups a
## run of adjacent `C` cells so a gate can span a door the hero could otherwise
## walk round. The pads are built per cell here for the same reason — a single
## plate stretched across six cells would be one flat slab where the level is
## made of tiles.
##
## [b]This node only reports being stepped on.[/b] Which checkpoint is armed is
## scenes/main.gd's to know, because only one can be, and a node that decided
## that for itself would need to hear about every other one. So arming arrives
## from outside through [method set_armed] and this script owns nothing but its
## own appearance.

## Emitted when the hero walks onto any of this checkpoint's cells. Re-emitted on
## every entry, including walking back onto one already armed.
signal reached(index: int)

## The hero is physics layer 3 — see the table in scenes/CLAUDE.md. This is the
## first area of any kind to watch that layer; the selection ray was the first
## query to.
const HERO_MASK := 4

const HERO_GROUP := "hero"

## Matches the zone markers LevelMap draws on the start and boss cells: a thin
## plate sitting just above the floor tile, covering most of its cell.
const PAD_SIZE := LevelMap.CELL_SIZE * 0.8
const PAD_THICKNESS := 0.02
const PAD_CLEARANCE := 0.07

## Tall enough that the trigger is crossed by a 1.8-unit capsule however the
## floor settles under it, and short enough not to reach anything on top of a
## wall.
const TRIGGER_HEIGHT := 2.4

## Violet, and the choice is forced from two directions. LevelMap paints the
## start cell green and the boss cell red, and scenes/ui/ rings the hero in cyan
## and enemies in orange — and unlike those two markers, a checkpoint pad is
## somewhere units *stand*, so a ring is drawn on top of it every time it
## matters. Violet is the one hue that collides with neither set.
const COLOUR_ARMED := Color(0.7, 0.42, 1.0)
const COLOUR_IDLE := Color(0.32, 0.24, 0.46)
const EMISSION_ARMED := 0.9
const EMISSION_IDLE := 0.15

## Position along the run, matching the index LevelMap.checkpoints() returned
## this checkpoint's cells at. 0 is the start cell, which never gets a pad.
var index := 0

var _cells := PackedVector3Array()
var _materials: Array[StandardMaterial3D] = []


## Place this checkpoint on its cells. Call it [b]before[/b] add_child, the way
## scenes/main.gd sets a zombie's position first: the pads and triggers are built
## in _ready(), and there is nothing to build them from until this has run.
func setup(checkpoint_index: int, cells: PackedVector3Array) -> void:
	index = checkpoint_index
	_cells = cells


func _ready() -> void:
	for centre in _cells:
		_build_pad(centre)
		_build_trigger(centre)
	set_armed(false)


## Light the pad, or put it out. Called by whoever tracks the armed checkpoint —
## including on the ones being disarmed, so exactly one is ever lit.
func set_armed(armed: bool) -> void:
	for material in _materials:
		material.albedo_color = COLOUR_ARMED if armed else COLOUR_IDLE
		material.emission = COLOUR_ARMED if armed else COLOUR_IDLE
		material.emission_energy_multiplier = EMISSION_ARMED if armed else EMISSION_IDLE


func _build_pad(centre: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(PAD_SIZE, PAD_THICKNESS, PAD_SIZE)
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	var pad := MeshInstance3D.new()
	pad.mesh = mesh
	pad.material_override = material
	pad.position = centre + Vector3(0, PAD_CLEARANCE, 0)
	add_child(pad)
	_materials.append(material)


## An Area3D rather than a distance check in _process: this has to fire for one
## cell of a six-cell gate whichever way the hero crosses it, and the physics
## server already answers exactly that.
##
## It carries no collision layer, because nothing needs to detect the trigger
## itself, and being an Area3D it is invisible to the navmesh bake — which parses
## static colliders only (see CLAUDE.md). A StaticBody3D here would bake a hole
## in the walkable surface at every checkpoint.
func _build_trigger(centre: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(LevelMap.CELL_SIZE, TRIGGER_HEIGHT, LevelMap.CELL_SIZE)
	var collider := CollisionShape3D.new()
	collider.shape = shape

	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = HERO_MASK
	area.position = centre + Vector3(0, TRIGGER_HEIGHT * 0.5, 0)
	area.add_child(collider)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


## The mask already limits this to the hero's layer; the group test is what keeps
## it true if anything else is ever put on that layer.
func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(HERO_GROUP):
		return
	reached.emit(index)
