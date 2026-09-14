extends "res://tests/harness.gd"
## Every shipped map is a valid map, and the validator is not simply agreeable
## (issue #73).
##
## [b]The second half is the reason the file exists.[/b] Every map under
## `maps/` validating clean is exactly what a reader that checks nothing would
## also report, and a parser that reads a malformed file as an empty one has
## caught four tools in this repo already. So each rule the format is held to is
## shown a file that breaks it, and asserted to be refused with the reason an
## author would need — the same discipline `smoke_skills.gd` applies to the
## skill tree's cycle check, one rule at a time.
##
## The broken maps are one small synthetic level rather than the shipped one
## with a cell moved, so that redesigning the dungeon never means rewriting
## these. The level is a corridor with a dead-end spur, which is the smallest
## shape on which every rule — including the spur rule — can be broken by
## changing one thing.

## The map data script, loaded by path rather than named: `MapData` as a type
## would make this folder fail to parse whenever the global class cache is
## missing, which is the state a fresh checkout is in until `--import` has run.
## Static constructors are callable on the loaded script.
var _map_data := load("res://scenes/map/map_data.gd")

## A corridor from the spawn past one checkpoint to the boss, with a spur off
## the spawn cell that runs deeper than the checkpoint is far — so an actor at
## its end scores a distance past the checkpoint while never having to pass it.
const ROWS := [
	"###################",
	"#S.....C......Z.B.#",
	"#.#################",
	"#.#################",
	"#.#################",
	"#.#################",
	"#.#################",
	"#.#################",
	"#.#################",
	"###################",
]


func _check() -> void:
	# --- 1. every shipped map is valid, and the level came up from one --------
	var shipped := PackedStringArray()
	var dir := DirAccess.open("res://maps")
	if dir != null:
		for name in dir.get_files():
			if name.get_extension() == "json":
				shipped.append("res://maps/%s" % name)
	# A glob that stops matching would otherwise validate nothing and pass —
	# the one result a check over shipped content must never produce.
	if not check("there are map files to validate", not shipped.is_empty(),
		"%d under res://maps" % shipped.size()):
		return
	for path in shipped:
		var map = _map_data.from_file(path)
		check("%s is a valid map" % path, map.is_valid(), "; ".join(map.problems))
	check("the level was built from a shipped map", shipped.has(level.map_path), level.map_path)
	check("and holds the map it was built from",
		level.map != null and level.map.is_valid() and level.map.id == "dungeon",
		level.map.id if level.map != null else "no map")
	check("with an actor standing for every entry in the file",
		living_enemies().size() == level.map.actors.size() + 1,
		"%d standing, %d actors and a boss in the file" % [
			living_enemies().size(), level.map.actors.size(),
		])

	# --- 2. the synthetic map is valid, so each refusal below is one change ---
	var good = _map_data.from_variant(_synthetic())
	if not check("the synthetic map validates clean", good.is_valid(), "; ".join(good.problems)):
		return
	var used: Array = good.assets_used()
	check("and names the ids something has to resolve",
		used.size() == 2 and used.has(&"boss") and used.has(&"zombie"), str(used))
	check("and files the spur's checkpoint and the actor beyond it as expected",
		good.checkpoints.size() == 2 and good.actors[0]["segment"] == 1 and good.boss_segment == 1,
		"%d checkpoints, actor in segment %d, boss in %d" % [
			good.checkpoints.size(), good.actors[0]["segment"], good.boss_segment,
		])

	# --- 3. what it does with garbage --------------------------------------
	# Each case names the problem an author would see. Substrings rather than
	# whole messages, so rewording a message is not a test edit — but specific
	# enough that the wrong rule firing is caught.
	_refuses("text that is not JSON", _map_data.from_text("{ not json"), "not valid JSON: line ")
	_refuses("a file whose top level is not an object", _map_data.from_variant([]),
		"is an array, not an object")
	var data := _synthetic()
	data.erase("format_version")
	_refuses("a map with no format_version", _map_data.from_variant(data),
		"format_version is missing")
	data = _synthetic()
	data["format_version"] = 2
	_refuses("a format version this build does not read", _map_data.from_variant(data),
		"format_version 2 is not one this build reads")
	# The first outdoor layer, arriving before the reader knows it: refused by
	# name rather than skipped, which is the whole difference between "this
	# file is newer than the game" and a map that silently loses a layer.
	data = _synthetic()
	data["decoration"] = []
	_refuses("a key the reader does not know", _map_data.from_variant(data),
		'a key this build does not know: "decoration"')
	data = _synthetic()
	data.erase("actors")
	_refuses("a missing layer", _map_data.from_variant(data), "actors is missing")

	# --- 4. the grid and the placements on it ------------------------------
	data = _synthetic()
	data["terrain"]["rows"][3] = "#.##"
	_refuses("a ragged grid", _map_data.from_variant(data), "row 3 is 4 cells wide, row 0 is 19")
	data = _synthetic()
	data["terrain"]["rows"][1] = "#.................Z"
	_refuses("a mark left in the grid", _map_data.from_variant(data),
		'row 1 has "Z" at column 18')
	data = _synthetic()
	data["markers"].append({"kind": "spawn", "cell": [3, 1]})
	_refuses("two spawns", _map_data.from_variant(data), "exactly one spawn marker, found 2")
	data = _synthetic()
	data["actors"][0]["asset"] = "Zombie-1"
	_refuses("an asset id with the wrong spelling", _map_data.from_variant(data),
		'"Zombie-1" is not an id')
	data = _synthetic()
	data["actors"][0]["cell"] = [14, 0]
	_refuses("an actor standing on rock", _map_data.from_variant(data),
		"the zombie at [14, 0] stands on rock")
	data = _synthetic()
	data["actors"][0]["cell"] = [40, 1]
	_refuses("an actor off the grid", _map_data.from_variant(data),
		"the zombie at [40, 1] is off the grid")
	data = _synthetic()
	data["actors"][0]["cell"] = [16, 1]
	_refuses("two things on one cell", _map_data.from_variant(data),
		"the zombie at [16, 1] shares its cell with the boss")
	data = _synthetic()
	data["markers"][2]["cells"] = [[7, 1], [9, 1]]
	_refuses("a checkpoint whose cells do not touch", _map_data.from_variant(data),
		"is not one connected gate")
	data = _synthetic()
	data["markers"].append({"kind": "checkpoint", "cells": [[8, 1]]})
	_refuses("two checkpoints that touch", _map_data.from_variant(data),
		"the checkpoint at [7, 1] touches the checkpoint at [8, 1]")

	# --- 5. the route ---------------------------------------------------------
	data = _synthetic()
	data["terrain"]["rows"][1] = "#..............#..#"
	_refuses("a boss walled off from the spawn", _map_data.from_variant(data),
		"the boss at [16, 1] is walled off")
	# Two cells from the checkpoint that restores it: the rule `scenes/hero/`
	# leans on, met exactly by the shipped map and so worth its own refusal.
	data = _synthetic()
	data["actors"][0]["cell"] = [9, 1]
	_refuses("an actor inside the respawn clearance", _map_data.from_variant(data),
		"the zombie at [9, 1] is 2.0 cells from checkpoint 1, which restores it")
	# The end of the spur is 7 cells from the spawn and the checkpoint is 6, so
	# an actor there is filed behind the checkpoint without being behind it.
	data = _synthetic()
	data["actors"][0]["cell"] = [1, 8]
	_refuses("an actor on a spur longer than the checkpoint is far", _map_data.from_variant(data),
		"the zombie at [1, 8] can be reached without passing checkpoint 1")

	# --- 6. and the loader builds nothing from a map it refuses ---------------
	# On a second, unparented level rather than the live one, so the run this
	# test is standing in stays intact. The one error line below is the loader
	# doing its job, not this test failing.
	note("the ERROR that follows is the loader refusing a missing file, as it should")
	var probe = load("res://scenes/map/level_map.gd").new()
	var built: bool = probe.load_map("res://maps/no_such_map.json")
	check("a map that cannot be read is not built",
		not built and probe.map == null and probe.get_child_count() == 0,
		"built=%s map=%s children=%d" % [built, probe.map, probe.get_child_count()])
	probe.free()
	done()


## Assert that [param map] was refused, and for the right reason.
func _refuses(what: String, map, reason: String) -> void:
	var found := false
	for problem in map.problems:
		if problem.contains(reason):
			found = true
	check("refuses %s" % what, not map.is_valid() and found,
		"; ".join(map.problems) if not map.problems.is_empty() else "accepted it")


## A fresh copy of the synthetic map every time, so one case's edit can never
## leak into the next.
func _synthetic() -> Dictionary:
	return {
		"format_version": 1,
		"id": "corridor",
		"display_name": "Corridor",
		"terrain": {"kind": "grid", "rows": _rows()},
		"markers": [
			{"kind": "spawn", "cell": [1, 1]},
			{"kind": "boss", "cell": [16, 1], "asset": "boss"},
			{"kind": "checkpoint", "cells": [[7, 1]]},
		],
		"actors": [
			{"asset": "zombie", "cell": [14, 1]},
		],
	}


## The corridor with its marks erased: the letters above are for the reader, and
## the format carries them as markers and actors instead.
func _rows() -> Array:
	var rows := []
	for row in ROWS:
		rows.append(row.replace("S", ".").replace("Z", ".").replace("B", ".").replace("C", "."))
	return rows
