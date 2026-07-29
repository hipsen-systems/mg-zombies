class_name Maze
extends Node3D
## Grid-driven maze builder (issue #6).
##
## The map is authored as ASCII in [member layout] — one character per 4×4
## cell — and turned into KayKit dungeon geometry at runtime. Authoring a map
## is therefore editing a text block, not placing hundreds of nodes by hand,
## and the .tscn stays tiny.
##
## Everything this builds is a StaticBody3D with a real collision shape,
## because the NavigationMesh parses static colliders only (see
## scenes/CLAUDE.md) — geometry without collision would be invisible to
## pathfinding. The zone markers are the deliberate exception: they are plain
## MeshInstance3Ds so they cannot affect the bake.

## Emitted once the geometry exists, before the navmesh is baked.
signal built

const CELL_SIZE := 4.0

## Measured from the KayKit pieces: `wall` is 4 tall, and `floor_tile_large`
## sits with its walking surface 0.05 above the node origin.
const WALL_HEIGHT := 4.0
const FLOOR_TOP := 0.05

const CELL_WALL := "#"
const CELL_FLOOR := "."
const CELL_START := "S"
const CELL_BOSS := "B"

## Physics layers, per the table in scenes/CLAUDE.md.
const LAYER_GROUND := 1
const LAYER_WALL := 2

const FLOOR_SCENE := preload("res://assets/dungeon/floor_tile_large.gltf")
const FLOOR_DIRT_SCENE := preload("res://assets/dungeon/floor_dirt_large.gltf")
const WALL_SCENE := preload("res://assets/dungeon/wall.gltf")

## Cell offsets for the four edges a cell can wall off, with the yaw the wall
## piece needs. The `wall` mesh is 4 long on X and 1 thick on Z, so a
## north/south edge is unrotated and an east/west edge is turned a quarter turn.
const EDGES := [
	{"cell": Vector2i(0, -1), "offset": Vector3(0, 0, -CELL_SIZE * 0.5), "yaw": 0.0},
	{"cell": Vector2i(0, 1), "offset": Vector3(0, 0, CELL_SIZE * 0.5), "yaw": 0.0},
	{"cell": Vector2i(-1, 0), "offset": Vector3(-CELL_SIZE * 0.5, 0, 0), "yaw": PI * 0.5},
	{"cell": Vector2i(1, 0), "offset": Vector3(CELL_SIZE * 0.5, 0, 0), "yaw": PI * 0.5},
]

## The map. North is row 0. Must be rectangular; exactly one S and one B.
##
## Corridors are one cell (4 units) wide, which leaves ~3 units of clear space
## once the walls straddle the cell edges. Agents travel them single-file: the
## navmesh bakes at agent_radius 1.0 (see the gotcha in CLAUDE.md), so the
## walkable ribbon is only ~1 unit wide. Two 0.4-radius agents fit across that
## with ~0.2 to spare, but nothing steers them apart — avoidance_enabled is off
## and no code sets it — so in practice they queue. Chokepoints are the default,
## not the exception; encounter design should assume a queue, not a brawl.
@export var layout: PackedStringArray = PackedStringArray([
	"###############",
	"#####.....#####",
	"#####.....#####",
	"#####..B..#####",
	"#####.....#####",
	"#######.#######",
	"#.....#.#.....#",
	"#.###.#.#.###.#",
	"#.#...#.#...#.#",
	"#.#.###.###.#.#",
	"#.#.#.......#.#",
	"#.#.#.#####.#.#",
	"#...#.#...#...#",
	"###.#.#.#.#.###",
	"#.....#.#.#...#",
	"#.#####.#.###.#",
	"#..S....#.....#",
	"###############",
])

var _start_cell := Vector2i(-1, -1)
var _boss_cell := Vector2i(-1, -1)
var _rock_material_cache: StandardMaterial3D = null


func _ready() -> void:
	build()


## World position of the cell the hero starts in.
func start_position() -> Vector3:
	return _cell_to_world(_start_cell)


## World position of the boss room's centre — the end of the core loop.
func boss_position() -> Vector3:
	return _cell_to_world(_boss_cell)


## Rebuild the maze from [member layout]. Safe to call again after editing it.
func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_start_cell = Vector2i(-1, -1)
	_boss_cell = Vector2i(-1, -1)

	if not _validate_layout():
		return

	for row in layout.size():
		for col in layout[row].length():
			var cell := Vector2i(col, row)
			var kind := _cell_kind(cell)
			if kind == CELL_WALL:
				_add_rock_cap(cell)
				continue
			if kind == CELL_START:
				_start_cell = cell
			elif kind == CELL_BOSS:
				_boss_cell = cell
			_build_open_cell(cell, kind)

	if not _boss_is_reachable():
		push_error(
			"Maze: the boss cell is walled off from the start cell. " +
			"Fix `layout` — the map is unplayable as authored."
		)
	built.emit()


func _validate_layout() -> bool:
	if layout.is_empty():
		push_error("Maze: `layout` is empty.")
		return false
	var width := layout[0].length()
	for row in layout.size():
		if layout[row].length() != width:
			push_error("Maze: row %d is %d cells wide, expected %d." % [
				row, layout[row].length(), width,
			])
			return false
	var starts := 0
	var bosses := 0
	for row in layout:
		starts += row.count(CELL_START)
		bosses += row.count(CELL_BOSS)
	if starts != 1 or bosses != 1:
		push_error("Maze: expected exactly one '%s' and one '%s', found %d and %d." % [
			CELL_START, CELL_BOSS, starts, bosses,
		])
		return false
	return true


func _build_open_cell(cell: Vector2i, kind: String) -> void:
	var centre := _cell_to_world(cell)
	# Start and boss rooms get the dirt tile so they read as distinct places
	# from a top-down camera without needing custom materials.
	var floor_scene := FLOOR_SCENE
	if kind == CELL_START or kind == CELL_BOSS:
		floor_scene = FLOOR_DIRT_SCENE
	_add_piece(floor_scene, centre, 0.0, LAYER_GROUND)

	if kind == CELL_START:
		_add_zone_marker(centre, Color(0.3, 0.9, 0.4))
	elif kind == CELL_BOSS:
		_add_zone_marker(centre, Color(0.95, 0.25, 0.2))

	# Wall off every edge that faces a wall cell or the outside of the grid.
	for edge in EDGES:
		if _cell_kind(cell + edge["cell"]) == CELL_WALL:
			_add_piece(WALL_SCENE, centre + edge["offset"], edge["yaw"], LAYER_WALL)


## Cap a solid-rock cell at wall height.
##
## Wall pieces only ever sit on the boundary between rock and open floor, so
## every rock cell is an open hole in the middle — from the camera angle you
## see straight through the map into the void. A tile laid flush with the top
## of the walls closes it and makes the rock read as one solid mass.
##
## Visual only — no StaticBody, deliberately. Giving these collision would bake
## navmesh islands inside solid rock, and since Hero.command_move_to() clamps a
## click onto the nearest navmesh point, clicking a wall could then order the
## hero to a spot he can never reach.
func _add_rock_cap(cell: Vector2i) -> void:
	var cap := FLOOR_SCENE.instantiate()
	cap.position = _cell_to_world(cell) + Vector3(0, WALL_HEIGHT - FLOOR_TOP, 0)
	# Tinted well down so the rock mass never competes with the lit corridor
	# floor for the player's eye — the whole point of the top-down view is that
	# walkable and not-walkable are obvious at a glance.
	for mesh_instance in _mesh_instances(cap):
		mesh_instance.material_override = _rock_material()
	add_child(cap)


func _rock_material() -> StandardMaterial3D:
	if _rock_material_cache == null:
		_rock_material_cache = StandardMaterial3D.new()
		_rock_material_cache.albedo_color = Color(0.16, 0.18, 0.23)
		_rock_material_cache.roughness = 1.0
	return _rock_material_cache


## Instance a dungeon piece with a collision box derived from its own mesh
## bounds, so the collider tracks the art if a piece is ever swapped out.
func _add_piece(scene: PackedScene, position: Vector3, yaw: float, layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	# Level geometry never needs to detect anything; it only gets collided with.
	body.collision_mask = 0
	body.position = position
	body.rotation.y = yaw
	add_child(body)

	var visual := scene.instantiate()
	body.add_child(visual)

	var bounds := _merged_aabb(visual)
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = bounds.position + bounds.size * 0.5
	body.add_child(collider)


## A flat, unshaded plate just above the floor marking a named area. Carries no
## collision on purpose: the navmesh must not see it.
func _add_zone_marker(centre: Vector3, colour: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CELL_SIZE * 0.7, 0.02, CELL_SIZE * 0.7)
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 0.6
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.material_override = material
	marker.position = centre + Vector3(0, 0.07, 0)
	add_child(marker)


func _merged_aabb(node: Node) -> AABB:
	var bounds := AABB()
	var found := false
	for mesh_instance in _mesh_instances(node):
		var box := mesh_instance.get_aabb()
		box.position += mesh_instance.position
		if found:
			bounds = bounds.merge(box)
		else:
			bounds = box
			found = true
	return bounds


func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_mesh_instances(child))
	return found


func _cell_kind(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= layout.size():
		return CELL_WALL
	var row := layout[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return CELL_WALL
	return row[cell.x]


func _cell_to_world(cell: Vector2i) -> Vector3:
	var cols := float(layout[0].length())
	var rows := float(layout.size())
	return Vector3(
		(float(cell.x) - (cols - 1.0) * 0.5) * CELL_SIZE,
		0.0,
		(float(cell.y) - (rows - 1.0) * 0.5) * CELL_SIZE
	)


## Flood-fill the open cells from the start. Catches a map edit that seals the
## boss room off before anyone has to discover it by walking there.
func _boss_is_reachable() -> bool:
	if _start_cell.x < 0 or _boss_cell.x < 0:
		return false
	var seen := {_start_cell: true}
	var queue: Array[Vector2i] = [_start_cell]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == _boss_cell:
			return true
		for edge in EDGES:
			var next: Vector2i = cell + edge["cell"]
			if seen.has(next) or _cell_kind(next) == CELL_WALL:
				continue
			seen[next] = true
			queue.append(next)
	return false
