class_name LevelMap
extends Node3D
## Grid-driven level builder (issues #6, #37, #38, #73).
##
## The map is a JSON file under `maps/` — see [MapData] for the format and
## every rule it is held to — read and checked at [method load_map], then
## turned into KayKit dungeon geometry at runtime. Authoring a map is editing a
## data file rather than a script or a scene, and the .tscn stays tiny.
##
## [b]This script is the only thing that knows what a cell is in world
## units.[/b] [MapData] owns the data and every fact about it: the grid, where
## the placements are, which checkpoint each is filed under. This one owns
## geometry and coordinates, and the public API below is the seam — positions
## come out of here in world units, and nothing downstream reads a cell.
##
## Openness is a property of the map, not of this builder: walls are only
## raised on the rock/floor boundary, so a 12-cell-wide clearing costs the same
## code as a one-cell corridor. That is why issue #37 replaced the maze with an
## open level without touching the build rules.
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

## The map file this level is built from. Loaded in [method _ready], so the
## scene comes up built the way it always has — `scenes/main.gd` relies on the
## geometry existing before its own `_ready()` bakes the navmesh over it.
@export_file("*.json") var map_path := "res://maps/dungeon.json"

## The map as read and checked, or null while nothing valid is loaded. Read-only
## from outside: [method load_map] is the one way it changes.
var map: MapData = null

var _rock_material_cache: StandardMaterial3D = null


func _ready() -> void:
	load_map(map_path)


## Read, check and build the map at [param path], replacing whatever stands
## here. Returns whether it built.
##
## [b]A map with anything wrong with it is not built at all.[/b] Every problem
## is pushed as its own error, so an author gets the whole list rather than the
## first line — and the level is left empty rather than half-built, because a
## half-built level is the failure that reads as something else downstream: a
## hero placed at the origin, enemies pathing to nowhere, a test that times out
## instead of saying what is wrong.
func load_map(path: String) -> bool:
	map_path = path
	map = null
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var candidate := MapData.from_file(path)
	if not candidate.is_valid():
		for problem in candidate.problems:
			push_error("LevelMap: %s: %s" % [path, problem])
		return false
	map = candidate
	_build()
	built.emit()
	return true


## The level's whole footprint on the ground plane: world X on the returned
## rect's x axis, world Z on its y. Empty until a map is loaded.
##
## It covers every cell, rock included, because every cell is *drawn* — rock is
## capped at wall height (see [method _add_rock_cap]) rather than left as a
## hole. So this rectangle is exactly the region that has something in it, and
## anything outside it is empty void, which is what makes it the shape
## scenes/'s camera clamps its view into (issue #43). The walkable floor is a
## smaller and wrong answer to that question: rock frames the level, and a
## camera that refused to show it would push the walls off screen.
func bounds() -> Rect2:
	if map == null:
		return Rect2()
	var size := Vector2(float(map.width()), float(map.height())) * CELL_SIZE
	return Rect2(-size * 0.5, size)


## World position of the cell the hero starts in.
func start_position() -> Vector3:
	return _cell_to_world(map.spawn_cell) if map != null else Vector3.ZERO


## World position of the boss room's centre — the end of the core loop.
func boss_position() -> Vector3:
	return _cell_to_world(map.boss_cell) if map != null else Vector3.ZERO


## The stretch of the run the boss cell belongs to (issue #39), on the same
## rule as an actor's: the last checkpoint at or before its own path distance.
##
## The boss is one authored marker rather than an entry in [method
## actor_spawns], so whoever places it has nowhere else to read this from —
## and without it a respawn would clear the boss away with the rest of its
## segment and have nothing telling it to put one back.
func boss_segment() -> int:
	return map.boss_segment if map != null else 0


## Which asset stands on the boss cell, by id. The map says what; resolving the
## id to a scene is whoever spawns it — the map never names a file.
func boss_asset() -> StringName:
	return map.boss_asset if map != null else &""


## Every actor as `{"asset": StringName, "position": Vector3, "segment": int}`,
## in file order. The map says what stands where, by id, and which stretch of
## the run it belongs to; whoever instances the actors resolves the id.
##
## The three are returned together rather than as parallel arrays because
## nothing downstream can tell a mismatched triple apart from a correct one.
##
## `segment` is the index of the last checkpoint at or before the actor's own
## path distance, so respawning at checkpoint *k* restores exactly the actors
## with `segment >= k` — see [method checkpoints].
func actor_spawns() -> Array[Dictionary]:
	var spawns: Array[Dictionary] = []
	if map == null:
		return spawns
	for actor in map.actors:
		spawns.append({
			"asset": actor["asset"],
			"position": _cell_to_world(actor["cell"]),
			"segment": actor["segment"],
		})
	return spawns


## Every checkpoint, ordered by path distance from the start (issue #38).
##
## Entry 0 is the start cell, which is checkpoint 0 by definition — a run always
## has somewhere to come back to, even before the hero has walked onto a pad.
## Later entries are the authored gates, each holding all of that checkpoint's
## cells with the *nearest* one first, so `[0]` is where the hero respawns and
## the whole array is where the pads go.
func checkpoints() -> Array[PackedVector3Array]:
	var groups: Array[PackedVector3Array] = []
	if map == null:
		return groups
	for group in map.checkpoints:
		var positions := PackedVector3Array()
		for cell in group:
			positions.append(_cell_to_world(cell))
		groups.append(positions)
	return groups


func _build() -> void:
	for row in map.height():
		for col in map.width():
			var cell := Vector2i(col, row)
			if not map.is_floor(cell):
				_add_rock_cap(cell)
				continue
			_build_open_cell(cell)


func _build_open_cell(cell: Vector2i) -> void:
	var centre := _cell_to_world(cell)
	# Start and boss rooms get the dirt tile so they read as distinct places
	# from a top-down camera without needing custom materials.
	var floor_scene := FLOOR_SCENE
	if cell == map.spawn_cell or cell == map.boss_cell:
		floor_scene = FLOOR_DIRT_SCENE
	_add_piece(floor_scene, centre, 0.0, LAYER_GROUND)

	if cell == map.spawn_cell:
		_add_zone_marker(centre, Color(0.3, 0.9, 0.4))
	elif cell == map.boss_cell:
		_add_zone_marker(centre, Color(0.95, 0.25, 0.2))

	# Wall off every edge that faces a rock cell or the outside of the grid.
	for edge in EDGES:
		if not map.is_floor(cell + edge["cell"]):
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


## The grid is centred on the origin, so a map's world extent is symmetric and
## [method bounds] needs no offset.
func _cell_to_world(cell: Vector2i) -> Vector3:
	var cols := float(map.width())
	var rows := float(map.height())
	return Vector3(
		(float(cell.x) - (cols - 1.0) * 0.5) * CELL_SIZE,
		0.0,
		(float(cell.y) - (rows - 1.0) * 0.5) * CELL_SIZE
	)
