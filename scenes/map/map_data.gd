class_name MapData
extends RefCounted
## One map, read from its file and checked before anything is built from it
## (issue #73).
##
## A map is a standalone JSON file under `maps/`, not a literal in a script and
## not a Godot resource: a resource can carry a script reference, so loading an
## untrusted one runs code on the player's machine, and community-authored maps
## are a stated horizon goal. JSON parses to plain data and can do nothing else.
## That is also why the reader here is strict in every direction — an unknown
## key, a wrong type, a cell that is not on the floor — because a file that is
## refused with a readable reason is the whole difference between a community
## map and a support problem.
##
## [b]Every fault is one line in [member problems], and a map with any is not
## built.[/b] The same shape as [method SkillTree.validate], for the same
## reason: a mistake in data that is merely tolerated shows up in play as a
## balance problem, and it is not one. What a parser must never do is read a
## malformed file as an empty one — this project has been caught by that four
## times, in four different tools — so nothing here is optional, nothing is
## defaulted, and a fault that stops the read says so rather than returning an
## empty map that builds an empty level.
##
## [b]What this owns and what it does not.[/b] Everything that is a fact about
## the *data* lives here: the grid, the placements, the path distances, which
## checkpoint each placement is filed under, and every rule those have to obey.
## [LevelMap] turns a valid one into geometry and is the only thing that knows
## what a cell is in world units. Which scene an `asset` id names is neither's
## business — [method assets_used] is the hook for whoever spawns things to check
## the ids against what it can actually spawn, exactly as an actor checks a
## skill tree's stat names, and for the same reason: the file cannot know.

## The one format this build reads. A file naming any other version is refused
## before anything else in it is looked at, so a reader can never half-apply
## rules written for a different shape. Anything that changes what the reader
## accepts — a new key, a new layer, a new marker kind — bumps this, because the
## reader refuses keys it does not know and a v1 reader must say "this is a v2
## file" rather than "this key is unknown". Present from the first release
## because it cannot be retrofitted once files exist outside the team.
const FORMAT_VERSION := 1

## The two things a grid cell can be. Everything else — the spawn, the boss, a
## checkpoint, an enemy — is a marker or an actor *placed on* a floor cell,
## never a third kind of cell, so nothing is said twice.
const ROCK := "#"
const FLOOR := "."

## The only terrain kind there is. Outdoor terrain (issue #75) will be another,
## with positions in its own coordinate space; a grid's are `[column, row]`.
const TERRAIN_GRID := "grid"

const MARKER_SPAWN := "spawn"
const MARKER_BOSS := "boss"
const MARKER_CHECKPOINT := "checkpoint"

## What an `id` or an `asset` may look like. Ids are contracts — a save names a
## map by its id, a registry (issue #74) resolves an asset by it — so they are
## held to the one spelling that survives being typed twice.
const ID_PATTERN := "^[a-z][a-z0-9_]*$"

## Straight-line cells between where a respawn puts the hero and anything that
## respawn restores. `scenes/hero/` leans on this number: 4 cells is 16 units,
## against an `acquire_radius` of 9, and that gap is the only reason he cannot be
## swung at on the frame he comes back. `tests/smoke_startup.gd` measures it on
## the assembled scene; this is the check an author meets before the scene is
## ever assembled.
const RESPAWN_CLEARANCE_CELLS := 4.0

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
]

var id := ""
var display_name := ""
## The grid, north first. Only [constant ROCK] and [constant FLOOR] once read.
var rows := PackedStringArray()
var spawn_cell := Vector2i(-1, -1)
var boss_cell := Vector2i(-1, -1)
var boss_asset := &""
## Which stretch of the run the boss belongs to, filed by the same rule as every
## actor — see [member checkpoints].
var boss_segment := 0
## Every checkpoint, ordered by path distance from the spawn. Entry 0 is the
## spawn cell on its own — a run always has somewhere to come back to — and each
## later entry is one authored group with its *nearest* cell first, so `[k][0]`
## is where a respawn at checkpoint k lands. A cell, never an average of the
## group: the centre of an L-shaped gate can be rock.
var checkpoints: Array = []
## Every actor as `{"asset": StringName, "cell": Vector2i, "segment": int}`, in
## file order. `segment` is the index of the last checkpoint at or before the
## actor's own path distance, so respawning at checkpoint k restores exactly the
## actors with `segment >= k`.
var actors: Array[Dictionary] = []
## Everything wrong with the map, one line each. Empty means it may be built.
var problems := PackedStringArray()

## Path distance in cells from the spawn, per reachable floor cell.
var _distances := {}
## Groups of checkpoint cells as authored, before ordering.
var _checkpoint_groups: Array = []
var _id_pattern := RegEx.create_from_string(ID_PATTERN)


## Read the map at [param path]. Never null: a file that cannot be read or
## parsed comes back as a map whose [member problems] say why.
static func from_file(path: String) -> MapData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var map := MapData.new()
		map.problems.append("cannot be opened: %s" % error_string(FileAccess.get_open_error()))
		return map
	return from_text(file.get_as_text())


## Read a map from JSON text.
static func from_text(text: String) -> MapData:
	var json := JSON.new()
	if json.parse(text) != OK:
		var map := MapData.new()
		# get_error_line() counts from 0; every editor counts from 1.
		map.problems.append("not valid JSON: line %d: %s" % [
			json.get_error_line() + 1, json.get_error_message(),
		])
		return map
	return from_variant(json.data)


## Read a map from already-parsed JSON — what `JSON.parse` hands back. The
## entry point a test uses to break one thing in an otherwise good map.
static func from_variant(data: Variant) -> MapData:
	var map := MapData.new()
	map._read(data)
	return map


func is_valid() -> bool:
	return problems.is_empty()


func width() -> int:
	return rows[0].length() if not rows.is_empty() else 0


func height() -> int:
	return rows.size()


## What is at [param cell]; anything off the grid is rock, so no map needs a
## border it did not draw.
func cell_kind(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= rows.size():
		return ROCK
	var row := rows[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return ROCK
	return row[cell.x]


## The flood-fills ask this for every neighbour of every cell, so it compares a
## code point rather than building a one-character String per call — worth 15%
## of a map load, measured, and nothing more is worth chasing in GDScript.
func is_floor(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= rows.size() or cell.x < 0 or cell.x >= rows[cell.y].length():
		return false
	return rows[cell.y].unicode_at(cell.x) == FLOOR.unicode_at(0)


## Every `asset` id the map names — the actors' and the boss's — deduplicated.
## The hook for whoever spawns things to check the ids against what it can
## spawn before a single one is missing from the level.
func assets_used() -> Array[StringName]:
	var used: Array[StringName] = []
	if not boss_asset.is_empty():
		used.append(boss_asset)
	for actor in actors:
		if not used.has(actor["asset"]):
			used.append(actor["asset"])
	return used


# --- Reading ------------------------------------------------------------------

## Three stages, each gated on the one before, so a fault is reported once at
## the level it belongs to rather than as a cascade: the shape of the file, then
## whether every placement stands on the floor, then the route those placements
## make. Within a stage everything wrong is reported, because an author fixing
## a map wants the whole list.
func _read(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		problems.append("the map is %s, not an object" % _type_name(data))
		return
	var version: Variant = data.get("format_version")
	if not _is_whole_number(version):
		problems.append("format_version is missing or not a whole number")
		return
	if int(version) != FORMAT_VERSION:
		problems.append("format_version %d is not one this build reads (it reads %d)" % [
			int(version), FORMAT_VERSION,
		])
		return

	_check_keys(data, "the map",
		["format_version", "id", "display_name", "terrain", "markers", "actors"])
	id = _read_id(data, "id", "the map")
	display_name = _read_string(data, "display_name", "the map")
	var grid_ok := _read_terrain(data.get("terrain"))
	_read_markers(data.get("markers"))
	_read_actors(data.get("actors"))
	if not grid_ok or not problems.is_empty():
		return
	if not _check_cells():
		return
	_check_route()


func _read_terrain(terrain: Variant) -> bool:
	if typeof(terrain) != TYPE_DICTIONARY:
		problems.append("terrain is %s, not an object" % _type_name(terrain))
		return false
	_check_keys(terrain, "terrain", ["kind", "rows"])
	var kind: Variant = terrain.get("kind")
	if typeof(kind) != TYPE_STRING or kind != TERRAIN_GRID:
		problems.append('terrain kind %s is not one this build knows (it knows "%s")' % [
			_describe(kind), TERRAIN_GRID,
		])
		return false
	var read_rows: Variant = terrain.get("rows")
	if typeof(read_rows) != TYPE_ARRAY or read_rows.is_empty():
		problems.append("terrain rows is %s, not a non-empty array of strings"
			% _type_name(read_rows))
		return false
	var sound := true
	for index in read_rows.size():
		if typeof(read_rows[index]) != TYPE_STRING:
			problems.append("terrain row %d is %s, not a string" % [
				index, _type_name(read_rows[index]),
			])
			sound = false
	if not sound:
		return false
	var grid_width: int = read_rows[0].length()
	if grid_width == 0:
		problems.append("terrain rows are empty strings")
		return false
	for index in read_rows.size():
		var row: String = read_rows[index]
		if row.length() != grid_width:
			problems.append("terrain row %d is %d cells wide, row 0 is %d" % [
				index, row.length(), grid_width,
			])
			sound = false
		for col in row.length():
			if row[col] != ROCK and row[col] != FLOOR:
				problems.append('terrain row %d has "%s" at column %d; a cell is "%s" or "%s"' % [
					index, row[col], col, ROCK, FLOOR,
				])
				sound = false
	if sound:
		rows = PackedStringArray(read_rows)
	return sound


func _read_markers(markers: Variant) -> void:
	if typeof(markers) != TYPE_ARRAY:
		problems.append("markers is %s, not an array" % _type_name(markers))
		return
	var spawns := 0
	var bosses := 0
	for index in markers.size():
		var marker: Variant = markers[index]
		var label := "markers[%d]" % index
		if typeof(marker) != TYPE_DICTIONARY:
			problems.append("%s is %s, not an object" % [label, _type_name(marker)])
			continue
		var kind: Variant = marker.get("kind")
		match kind:
			MARKER_SPAWN:
				spawns += 1
				_check_keys(marker, label, ["kind", "cell"])
				var cell: Variant = _read_cell(marker.get("cell"), label)
				if cell != null:
					spawn_cell = cell
			MARKER_BOSS:
				bosses += 1
				_check_keys(marker, label, ["kind", "cell", "asset"])
				var cell: Variant = _read_cell(marker.get("cell"), label)
				if cell != null:
					boss_cell = cell
				boss_asset = StringName(_read_id(marker, "asset", label))
			MARKER_CHECKPOINT:
				_check_keys(marker, label, ["kind", "cells"])
				var cells: Variant = marker.get("cells")
				if typeof(cells) != TYPE_ARRAY or cells.is_empty():
					problems.append("%s cells is %s, not a non-empty array of cells" % [
						label, _type_name(cells),
					])
					continue
				var group: Array[Vector2i] = []
				for cell_index in cells.size():
					var cell: Variant = _read_cell(cells[cell_index], "%s cells[%d]" % [label, cell_index])
					if cell != null:
						group.append(cell)
				if group.size() == cells.size():
					_checkpoint_groups.append(group)
			_:
				problems.append('%s kind %s is not one this build knows ("%s", "%s" or "%s")' % [
					label, _describe(kind), MARKER_SPAWN, MARKER_BOSS, MARKER_CHECKPOINT,
				])
	if spawns != 1:
		problems.append("expected exactly one spawn marker, found %d" % spawns)
	if bosses != 1:
		problems.append("expected exactly one boss marker, found %d" % bosses)


func _read_actors(read_actors: Variant) -> void:
	if typeof(read_actors) != TYPE_ARRAY:
		problems.append("actors is %s, not an array" % _type_name(read_actors))
		return
	for index in read_actors.size():
		var actor: Variant = read_actors[index]
		var label := "actors[%d]" % index
		if typeof(actor) != TYPE_DICTIONARY:
			problems.append("%s is %s, not an object" % [label, _type_name(actor)])
			continue
		_check_keys(actor, label, ["asset", "cell"])
		var asset := _read_id(actor, "asset", label)
		var cell: Variant = _read_cell(actor.get("cell"), label)
		if asset.is_empty() or cell == null:
			continue
		actors.append({"asset": StringName(asset), "cell": cell, "segment": 0})


# --- Cells --------------------------------------------------------------------

## Every placement stands on a floor cell inside the grid, no cell carries two
## things, and each checkpoint is one connected gate. Returns whether all of
## that held, because the route checks assume it.
func _check_cells() -> bool:
	var sound := true
	var claimed := {}
	for placement in _placements():
		var cell: Vector2i = placement["cell"]
		var label: String = placement["label"]
		if cell.x >= width() or cell.y >= height():
			problems.append("%s is off the grid, which is %d by %d" % [label, width(), height()])
			sound = false
			continue
		if not is_floor(cell):
			problems.append("%s stands on rock" % label)
			sound = false
			continue
		if claimed.has(cell):
			problems.append("%s shares its cell with %s" % [label, claimed[cell]])
			sound = false
			continue
		claimed[cell] = label

	# A gate is one thing to arm, so its cells have to touch — and two gates
	# that touch each other would be one thing to the player and two to the
	# respawn rule, which is the ambiguity refused here.
	var owner := {}
	for index in _checkpoint_groups.size():
		for cell in _checkpoint_groups[index]:
			owner[cell] = index
	var touching := {}
	for index in _checkpoint_groups.size():
		var group: Array[Vector2i] = _checkpoint_groups[index]
		var reached := {group[0]: true}
		var queue: Array[Vector2i] = [group[0]]
		var head := 0
		while head < queue.size():
			var cell: Vector2i = queue[head]
			head += 1
			for delta in NEIGHBOURS:
				var next: Vector2i = cell + delta
				if reached.has(next) or not owner.has(next):
					continue
				if owner[next] != index:
					touching[Vector2i(mini(index, owner[next]), maxi(index, owner[next]))] = true
					continue
				reached[next] = true
				queue.append(next)
		if reached.size() != group.size():
			problems.append("%s is not one connected gate: %d of its %d cells are cut off" % [
				_checkpoint_label(index), group.size() - reached.size(), group.size(),
			])
			sound = false
	for pair in touching:
		problems.append("%s touches %s; merge them or move one" % [
			_checkpoint_label(pair.x), _checkpoint_label(pair.y),
		])
		sound = false
	return sound


# --- The route ----------------------------------------------------------------

## The spawn reaches everything, checkpoints fall in an unambiguous order along
## the run, and the two rules a respawn depends on hold: nothing a respawn
## restores stands within [constant RESPAWN_CLEARANCE_CELLS] of where it lands
## the hero, and nothing is filed behind a checkpoint that a player can reach
## without passing it.
func _check_route() -> void:
	_distances = _flood({})
	if not _distances.has(boss_cell):
		problems.append("the boss at %s is walled off from the spawn" % _cell_text(boss_cell))
	for index in _checkpoint_groups.size():
		var group: Array[Vector2i] = _checkpoint_groups[index]
		if not _distances.has(group[0]):
			problems.append("%s is walled off from the spawn, so it can never be armed"
				% _checkpoint_label(index))
	for index in actors.size():
		if not _distances.has(actors[index]["cell"]):
			problems.append("%s is walled off from the spawn, so it can never be fought"
				% _actor_label(index))
	if not problems.is_empty():
		return

	# Order the checkpoints along the run by distance, nearest cell first within
	# each. Nothing is numbered by hand, so moving a gate re-files every actor
	# behind it — and a tie would leave the order to the sort, which is not a
	# rule anyone can read.
	var ordered: Array = []
	for group in _checkpoint_groups:
		var cells: Array[Vector2i] = group.duplicate()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _distances[a] < _distances[b])
		ordered.append(cells)
	ordered.sort_custom(func(a: Array, b: Array) -> bool:
		return _distances[a[0]] < _distances[b[0]])
	for index in range(1, ordered.size()):
		if _distances[ordered[index][0]] == _distances[ordered[index - 1][0]]:
			problems.append("the checkpoints at %s and %s are both %d cells from the spawn, so their order along the run is ambiguous" % [
				_cell_text(ordered[index - 1][0]), _cell_text(ordered[index][0]),
				_distances[ordered[index][0]],
			])
	var start: Array[Vector2i] = [spawn_cell]
	checkpoints = [start]
	checkpoints.append_array(ordered)
	if not problems.is_empty():
		return

	for actor in actors:
		actor["segment"] = _segment_of(actor["cell"])
	boss_segment = _segment_of(boss_cell)
	_check_clearance()
	_check_split_segments()


## Nothing a respawn restores may stand within the clearance of the cell it
## lands the hero on. Per checkpoint, over the placements with `segment >=` that
## checkpoint — those are the ones that arrive back at their cells together with
## the hero, on a player who has just lost a fight. Straight-line, because it is
## about what can *see* him; the segment distances are path, because they are
## about what he had to walk.
func _check_clearance() -> void:
	var placements := _restored_placements()
	for index in checkpoints.size():
		var landing: Vector2i = checkpoints[index][0]
		for placement in placements:
			if int(placement["segment"]) < index:
				continue
			var offset: Vector2 = Vector2(placement["cell"] - landing)
			if offset.length() < RESPAWN_CLEARANCE_CELLS:
				problems.append("%s is %.1f cells from checkpoint %d, which restores it; %d is the minimum" % [
					placement["label"], offset.length(), index, int(RESPAWN_CLEARANCE_CELLS),
				])


## Segments are cut by path distance, but "behind the checkpoint" is really a
## question about routes, and the two only agree while nothing hangs off the
## route deeper than the next checkpoint is far. A dead-end spur longer than
## that breaks it: its far end scores a distance past the checkpoint, so an
## actor the player cleared *before* the checkpoint is filed ahead of it and
## comes back on every respawn there — in a place they have already left, for
## no reason they can see. Flooding with the checkpoint's cells treated as rock
## answers what really lies behind it.
func _check_split_segments() -> void:
	var placements := _restored_placements()
	for index in range(1, checkpoints.size()):
		var blocked := {}
		for cell in checkpoints[index]:
			blocked[cell] = true
		var before := _flood(blocked)
		for placement in placements:
			if int(placement["segment"]) < index or not before.has(placement["cell"]):
				continue
			problems.append("%s can be reached without passing checkpoint %d but is filed in segment %d, so it would be restored on every respawn there; shorten the spur it is on, or move the checkpoint past it" % [
				placement["label"], index, int(placement["segment"]),
			])


## Path distance in cells from the spawn to every floor cell it can reach,
## treating each cell of [param blocked] as rock.
func _flood(blocked: Dictionary) -> Dictionary:
	var distances := {spawn_cell: 0}
	var queue: Array[Vector2i] = [spawn_cell]
	# An index rather than pop_front(), which shifts the whole array per dequeue.
	# Measured: it makes no difference at this size — a flood is ~1.5 ms over
	# the dungeon's 620 cells either way, and that is interpreter cost per
	# neighbour visit. Three floods per map, so reading a map is ~4.5 ms at
	# startup, which the old builder paid too and nobody had measured.
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var distance: int = distances[cell]
		for delta in NEIGHBOURS:
			var next: Vector2i = cell + delta
			if distances.has(next) or blocked.has(next) or not is_floor(next):
				continue
			distances[next] = distance + 1
			queue.append(next)
	return distances


## The last checkpoint at or before [param cell]'s own path distance.
func _segment_of(cell: Vector2i) -> int:
	var distance: int = _distances[cell]
	var segment := 0
	for index in checkpoints.size():
		if distance >= _distances[checkpoints[index][0]]:
			segment = index
	return segment


# --- Small readers ------------------------------------------------------------

## Everything a respawn can restore — the actors and the boss — with the segment
## each is filed under. Only meaningful once [method _check_route] has filed them.
func _restored_placements() -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	for index in actors.size():
		placements.append({
			"cell": actors[index]["cell"], "segment": actors[index]["segment"],
			"label": _actor_label(index),
		})
	placements.append({"cell": boss_cell, "segment": boss_segment, "label": "the boss"})
	return placements


## Every placement with a label, for the checks that treat them alike.
func _placements() -> Array[Dictionary]:
	var placements: Array[Dictionary] = [
		{"cell": spawn_cell, "label": "the spawn"},
		{"cell": boss_cell, "label": "the boss"},
	]
	for index in _checkpoint_groups.size():
		for cell in _checkpoint_groups[index]:
			placements.append({"cell": cell, "label": _checkpoint_label(index)})
	for index in actors.size():
		placements.append({"cell": actors[index]["cell"], "label": _actor_label(index)})
	return placements


## A key the reader does not know is refused rather than skipped: a typo in
## `"markers"` would otherwise read as a map with no markers, which the count
## check catches — but a typo in an optional key some later version adds would
## read as nothing at all, and that is the failure this whole file exists to
## rule out.
func _check_keys(dict: Dictionary, label: String, known: Array[String]) -> void:
	for key in dict:
		if not known.has(String(key)):
			problems.append('%s has a key this build does not know: "%s"' % [label, key])


func _read_string(dict: Dictionary, key: String, label: String) -> String:
	var value: Variant = dict.get(key)
	if typeof(value) != TYPE_STRING or value.is_empty():
		problems.append("%s %s is %s, not a non-empty string" % [label, key, _type_name(value)])
		return ""
	return value


func _read_id(dict: Dictionary, key: String, label: String) -> String:
	var value := _read_string(dict, key, label)
	if value.is_empty():
		return ""
	if _id_pattern.search(value) == null:
		problems.append('%s %s "%s" is not an id: lowercase letters, digits and underscores, starting with a letter' % [
			label, key, value,
		])
		return ""
	return value


## A cell is `[column, row]`, two whole numbers, zero-based, row 0 being the
## first string of the grid. Null when it is not, with the fault recorded.
func _read_cell(value: Variant, label: String) -> Variant:
	if typeof(value) != TYPE_ARRAY or value.size() != 2 \
			or not _is_whole_number(value[0]) or not _is_whole_number(value[1]) \
			or int(value[0]) < 0 or int(value[1]) < 0:
		problems.append("%s cell %s is not a [column, row] pair of whole numbers from 0" % [
			label, _describe(value),
		])
		return null
	return Vector2i(int(value[0]), int(value[1]))


## JSON has no integers — every number arrives as a float — so "whole" is the
## test, not the type.
static func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and value == floorf(value)


func _checkpoint_label(index: int) -> String:
	return "the checkpoint at %s" % _cell_text(_checkpoint_groups[index][0])


func _actor_label(index: int) -> String:
	return "the %s at %s" % [actors[index]["asset"], _cell_text(actors[index]["cell"])]


static func _cell_text(cell: Vector2i) -> String:
	return "[%d, %d]" % [cell.x, cell.y]


static func _type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "missing"
		TYPE_DICTIONARY: return "an object"
		TYPE_ARRAY: return "an array"
		TYPE_STRING: return "a string"
		TYPE_FLOAT, TYPE_INT: return "a number"
		TYPE_BOOL: return "a boolean"
	return type_string(typeof(value))


static func _describe(value: Variant) -> String:
	if typeof(value) == TYPE_NIL:
		return "(missing)"
	return JSON.stringify(value)
