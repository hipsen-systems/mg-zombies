class_name LevelMap
extends Node3D
## Grid-driven level builder (issues #6, #37, #38).
##
## The map is authored as ASCII in [member layout] — one character per 4×4
## cell — and turned into KayKit dungeon geometry at runtime. Authoring a map
## is therefore editing a text block, not placing hundreds of nodes by hand,
## and the .tscn stays tiny.
##
## Openness is a property of the layout, not of this builder: walls are only
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

const CELL_WALL := "#"
const CELL_FLOOR := "."
const CELL_START := "S"
const CELL_BOSS := "B"
## An ordinary floor cell that also marks where a zombie spawns (issue #7).
## Encounters are authored in the layout for the same reason the map is: placing
## an enemy is editing one character. The map itself never instances enemies —
## scenes/main.gd reads [method zombie_spawns] and does that.
const CELL_ZOMBIE := "Z"
## Ordinary floor cell that also marks a respawn checkpoint (issue #38). A run of
## orthogonally adjacent `C` cells is *one* checkpoint, so a map author can lay a
## gate across a door the hero could otherwise walk round: the pads are per cell,
## the checkpoint is per run. The map only says where — scenes/main.gd instances
## checkpoint.tscn on the cells, exactly as it does zombies on the `Z` cells.
const CELL_CHECKPOINT := "C"

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
## One route runs from `S` (bottom left) to `B` (top right), and its width is
## the thing that varies: 10-cell clearings, a 3-cell-thick passage between
## them, and two deliberate one-cell chokepoints. Two dead-end spurs hang off
## the route — a chamber north of the first clearing and a vault south of the
## second — each holding a pair of zombies and nothing else. There is no second
## way round: every path from `S` to `B` goes through both chokepoints.
##
## **A one-cell chokepoint is single-file, and that is now a choice per
## location rather than a property of the whole map.** The navmesh bakes at
## agent_radius 1.0 (see the gotcha in CLAUDE.md), so the walkable ribbon
## through a one-cell gap is only ~1 unit wide. Two 0.4-radius agents fit across
## it with ~0.2 to spare, but nothing steers them apart — avoidance_enabled is
## off and no code sets it — so in practice they queue. Put a chokepoint where a
## queue is the encounter you want; a clearing is where units can spread out.
##
## Zombie spawns (`Z`) are kept well clear of the start cell: a zombie inside
## its own detection radius (12 units = 3 cells) of `S` would charge the hero
## the moment the run begins, before the player has taken a single step. The
## nearest one here is 7 cells away.
##
## [b]That rule binds every `C` cell the hero can respawn on too[/b], and it is
## sharper there, because the zombies ahead of a checkpoint are restored to their
## spawns by the very respawn that puts him on it — so the two arrive together,
## every time, on a player who has just lost a fight. Both checkpoints here were
## moved to earn it: this one back into the tunnel (it sat at the mouth, one cell
## from a spawn) and the boss-room guard four cells deeper into its room (it
## stood in the doorway the gate covers). Nothing is now within 4 cells of a
## respawn cell.
##
## The two checkpoints sit on the only places every route passes through that are
## *also* late enough to be worth reaching: inside the one-cell tunnel (24 from
## the start) and on the six-cell threshold of the boss room (46). `S` is
## checkpoint 0. The remaining cut — the throat out of the start clearing — is
## four cells from `S` and would bank nothing.
@export var layout: PackedStringArray = PackedStringArray([
	"############################################",
	"############################################",
	"########################...............#####",
	"######################...................###",
	"#####################....................###",
	"#####################...Z.................##",
	"####################..........B...........##",
	"####################..................Z...##",
	"#####################.........Z...........##",
	"#####################....................###",
	"######################..................####",
	"########################..............######",
	"############################CCCCCC##########",
	"#############################....###########",
	"#####.....####################..############",
	"####.Z...Z.#################..Z..###########",
	"####.......################......###########",
	"######..##################.....#############",
	"######...#################..Z..#############",
	"######...#################.........#########",
	"####........#############..............#####",
	"###...........##########......Z.........####",
	"##...Z.........#########.................###",
	"##..........Z..#########..Z..............###",
	"##...................###..................##",
	"##...............Z...CCC.Z................##",
	"##..Z................###.............Z....##",
	"###..........###########........Z........###",
	"####...Z...##############...............####",
	"######.####################..........#######",
	"######.########################...##########",
	"####......#####################..###########",
	"###........##################........#######",
	"##..........#################..Z..Z..#######",
	"##....S.....##################......########",
	"###........#################################",
	"####......##################################",
	"############################################",
])

var _start_cell := Vector2i(-1, -1)
var _boss_cell := Vector2i(-1, -1)
var _zombie_cells: Array[Vector2i] = []
var _checkpoint_cells: Array[Vector2i] = []
## Path distance in cells from the start, per open cell. Keys are Vector2i.
var _distances := {}
## Checkpoint groups, ordered by distance from the start, each an Array[Vector2i]
## whose own cells are ordered the same way. Group 0 is always the start cell.
var _checkpoint_groups: Array = []
## Segment index per entry of [member _zombie_cells].
var _spawn_segments: Array[int] = []
var _rock_material_cache: StandardMaterial3D = null


func _ready() -> void:
	build()


## World position of the cell the hero starts in.
func start_position() -> Vector3:
	return _cell_to_world(_start_cell)


## World position of the boss room's centre — the end of the core loop.
func boss_position() -> Vector3:
	return _cell_to_world(_boss_cell)


## The stretch of the run the boss cell belongs to (issue #39), on the same
## rule as a spawn's: the last checkpoint at or before its own path distance.
##
## The boss is one authored instance rather than an entry in [method
## zombie_spawns], so whoever places it has nowhere else to read this from —
## and without it a respawn would clear the boss away with the rest of its
## segment and have nothing telling it to put one back.
func boss_segment() -> int:
	return _segment_of(_boss_cell)


## Every `Z` cell as `{"position": Vector3, "segment": int}`, in layout order.
## Whoever instances the enemies decides what to put there; the map only says
## where, and which stretch of the run it belongs to.
##
## The two are returned together rather than as parallel arrays because nothing
## downstream can tell a mismatched pair apart from a correct one.
##
## `segment` is the index of the last checkpoint at or before the spawn's own
## path distance, so respawning at checkpoint *k* restores exactly the spawns
## with `segment >= k` — see [method checkpoints].
func zombie_spawns() -> Array[Dictionary]:
	var spawns: Array[Dictionary] = []
	for index in _zombie_cells.size():
		spawns.append({
			"position": _cell_to_world(_zombie_cells[index]),
			"segment": _spawn_segments[index],
		})
	return spawns


## Every checkpoint, ordered by path distance from the start (issue #38).
##
## Entry 0 is the start cell, which is checkpoint 0 by definition — a run always
## has somewhere to come back to, even before the hero has walked onto a pad.
## Later entries are the runs of adjacent `C` cells, each entry holding all of
## that checkpoint's cells with the *nearest* one first, so `[0]` is where the
## hero respawns and the whole array is where the pads go.
func checkpoints() -> Array[PackedVector3Array]:
	var groups: Array[PackedVector3Array] = []
	for group in _checkpoint_groups:
		var positions := PackedVector3Array()
		for cell in group:
			positions.append(_cell_to_world(cell))
		groups.append(positions)
	return groups


## Rebuild the level from [member layout]. Safe to call again after editing it.
func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_start_cell = Vector2i(-1, -1)
	_boss_cell = Vector2i(-1, -1)
	_zombie_cells.clear()
	_checkpoint_cells.clear()
	_checkpoint_groups.clear()
	_spawn_segments.clear()
	_distances.clear()

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
			elif kind == CELL_ZOMBIE:
				_zombie_cells.append(cell)
			elif kind == CELL_CHECKPOINT:
				_checkpoint_cells.append(cell)
			_build_open_cell(cell, kind)

	_distances = _flood_distances({})
	if not _distances.has(_boss_cell):
		push_error(
			"LevelMap: the boss cell is walled off from the start cell. " +
			"Fix `layout` — the map is unplayable as authored."
		)
	_group_checkpoints()
	_assign_spawn_segments()
	_warn_about_split_segments()
	built.emit()


func _validate_layout() -> bool:
	if layout.is_empty():
		push_error("LevelMap: `layout` is empty.")
		return false
	var width := layout[0].length()
	for row in layout.size():
		if layout[row].length() != width:
			push_error("LevelMap: row %d is %d cells wide, expected %d." % [
				row, layout[row].length(), width,
			])
			return false
	var starts := 0
	var bosses := 0
	for row in layout:
		starts += row.count(CELL_START)
		bosses += row.count(CELL_BOSS)
	if starts != 1 or bosses != 1:
		push_error("LevelMap: expected exactly one '%s' and one '%s', found %d and %d." % [
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


## Path distance in cells from the start to every open cell it can reach,
## treating each cell of [param blocked] as if it were rock.
##
## With nothing blocked this doubles as the reachability check: a boss cell
## missing from the result is walled off, which catches a map edit that seals the
## goal away before anyone has to discover it by walking there. With a
## checkpoint's cells blocked it answers the other question — what lies *behind*
## that checkpoint — which is what [method _warn_about_split_segments] needs.
func _flood_distances(blocked: Dictionary) -> Dictionary:
	var distances := {}
	if _start_cell.x < 0:
		return distances
	distances[_start_cell] = 0
	var queue: Array[Vector2i] = [_start_cell]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var distance: int = distances[cell]
		for edge in EDGES:
			var next: Vector2i = cell + edge["cell"]
			if distances.has(next) or blocked.has(next):
				continue
			if _cell_kind(next) == CELL_WALL:
				continue
			distances[next] = distance + 1
			queue.append(next)
	return distances


## Collect the `C` cells into checkpoints and order them along the run.
##
## Adjacent `C` cells are one checkpoint, which is what lets a gate span a door
## wide enough to walk round; a checkpoint the player can miss costs them far
## more progress than the one they thought they had banked. Within a group the
## nearest cell comes first, so callers have an unambiguous respawn point without
## averaging positions — an average can land in rock, a cell never does.
func _group_checkpoints() -> void:
	var start_group: Array[Vector2i] = [_start_cell]
	_checkpoint_groups = [start_group]
	var seen := {}
	for cell in _checkpoint_cells:
		if seen.has(cell):
			continue
		var group: Array[Vector2i] = []
		var queue: Array[Vector2i] = [cell]
		seen[cell] = true
		while not queue.is_empty():
			var current: Vector2i = queue.pop_front()
			group.append(current)
			for edge in EDGES:
				var next: Vector2i = current + edge["cell"]
				if seen.has(next) or _cell_kind(next) != CELL_CHECKPOINT:
					continue
				seen[next] = true
				queue.append(next)
		if _distance_of(group[0]) < 0:
			push_error(
				"LevelMap: the checkpoint at %s is walled off from the start " % group[0] +
				"cell, so it can never be armed. Fix `layout`."
			)
			continue
		group.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _distance_of(a) < _distance_of(b)
		)
		_checkpoint_groups.append(group)
	_checkpoint_groups.sort_custom(func(a: Array, b: Array) -> bool:
		return _distance_of(a[0]) < _distance_of(b[0])
	)


## File each spawn under the last checkpoint at or before its own path distance.
func _assign_spawn_segments() -> void:
	for cell in _zombie_cells:
		_spawn_segments.append(_segment_of(cell))


## The last checkpoint at or before [param cell]'s own path distance.
##
## Cached for the spawns because they are asked for as a list, and computed on
## demand for the boss cell — one rule either way, so the boss can never end up
## filed by a different one than the zombies standing next to it.
func _segment_of(cell: Vector2i) -> int:
	var distance := _distance_of(cell)
	var segment := 0
	for index in _checkpoint_groups.size():
		if distance >= _distance_of(_checkpoint_groups[index][0]):
			segment = index
	return segment


## Catch the authoring hazard the segment rule creates.
##
## Segments are cut by path distance, but "behind the checkpoint" is really a
## question about routes, and the two only agree while nothing hangs off the
## route deeper than the next checkpoint is far. A dead-end spur longer than the
## run to the next checkpoint breaks that: its far end scores a distance past the
## checkpoint, so a spawn the player cleared *before* the checkpoint is filed
## ahead of it and comes back on every respawn — for no reason the player can
## see, in a place they have already left.
##
## Only spawns are checked, not cells. An empty cell filed on the wrong side of a
## checkpoint changes nothing that anyone can observe, and the current level has
## eleven of them in the deep corners of the south vault; warning about those
## would train everyone to ignore this.
func _warn_about_split_segments() -> void:
	for index in range(1, _checkpoint_groups.size()):
		var blocked := {}
		for cell in _checkpoint_groups[index]:
			blocked[cell] = true
		var behind := _flood_distances(blocked)
		for spawn in _zombie_cells.size():
			if _spawn_segments[spawn] < index or not behind.has(_zombie_cells[spawn]):
				continue
			push_warning(
				"LevelMap: the spawn at %s is reachable without passing " % _zombie_cells[spawn] +
				"checkpoint %d, but sits in segment %d, so it will be " % [
					index, _spawn_segments[spawn],
				] +
				"restored on every respawn there. Shorten the spur it is on, " +
				"or move the checkpoint past it."
			)


func _distance_of(cell: Vector2i) -> int:
	if not _distances.has(cell):
		return -1
	return int(_distances[cell])
