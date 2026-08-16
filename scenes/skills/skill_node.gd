class_name SkillNode
extends Resource
## One buyable node of the skill tree (issue #9): what it costs, what it needs
## first, and what it does.
##
## [b]A node carries no position and no hotkey.[/b] Where it is drawn belongs to
## the panel that draws it, and which key buys it belongs to whoever owns the
## control scheme — scenes/hero/ keeps that mapping. A tree that knew about
## input could not be shared with a second actor, and a tree that knew about
## layout could not be re-laid-out without editing game content.


## Stable identity, and the reason it is stable: the ledger a save file would
## hold is [code]{id: rank}[/code], so an id is a save-compatibility contract.
## Rename a node's [member display_name] freely; retire an id rather than
## reusing it.
@export var id: StringName = &""

@export var display_name := ""

## One line for a panel that does not exist yet. Never parsed — [member effects]
## are what actually happens, and a description that disagreed with them would
## be the lie that a generated one cannot tell.
@export_multiline var description := ""

@export_range(1, 20) var max_rank := 1

## Skill points one rank costs. Flat across the ranks of a node rather than a
## per-rank array: a rising cost is a balance decision, and there is still
## nothing to balance it against.
@export_range(1, 10) var cost_per_rank := 1

## Skill id → the rank of that skill this node needs before its own first rank
## can be bought. Empty means it is open from the start.
##
## A dictionary rather than a list of requirement objects, because every
## prerequisite so far is "at least this many ranks of that" and a resource per
## edge would be three files to express one number.
@export var requires: Dictionary = {}

@export var effects: Array[SkillEffect] = []


## Whether every prerequisite is met by [param ranks], a skill id → rank map.
## Says nothing about cost or the rank cap — see [method SkillTree.refusal] for
## the whole answer.
func is_open(ranks: Dictionary) -> bool:
	for required_id in requires:
		if int(ranks.get(required_id, 0)) < int(requires[required_id]):
			return false
	return true


## What [param rank] ranks of this node have bought, as one line for the HUD.
##
## Assembled from the effects rather than written out beside them, so a node
## cannot advertise something it does not do.
func describe(rank: int) -> String:
	var parts := PackedStringArray()
	for effect in effects:
		if effect == null:
			continue
		var text := effect.describe(rank)
		if not text.is_empty():
			parts.append(text)
	return ", ".join(parts)
