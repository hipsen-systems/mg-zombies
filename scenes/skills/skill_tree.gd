class_name SkillTree
extends Resource
## The whole authored skill tree (issue #9): a flat list of [SkillNode]s that is
## a tree only because of what they require of each other.
##
## [b]This resource is content, not state.[/b] It holds no ranks and no points,
## which is what lets one instance be shared by every actor that uses it — and
## what makes a save file's payload the actor's [code]{id: rank}[/code] ledger
## and nothing else. Every method here therefore takes the ranks it should
## reason about rather than reading them from anywhere.
##
## [b]It knows about points but never about a pool.[/b] [method refusal] answers
## the half of "can this be bought" that is a property of the tree — is it
## unlocked, is there a rank left — and stops at the half that is a property of
## the buyer. Whoever holds the points asks this first and pays second, which is
## the ordering scenes/hero/ keeps for the reason it records: a check made after
## the debit would have to hand a point back.


## The nodes, in authoring order. Order is not depth: what gates what is
## [member SkillNode.requires], so a node can be moved in this list freely.
@export var nodes: Array[SkillNode] = []


## The node with [param id], or null.
func node(id: StringName) -> SkillNode:
	for candidate in nodes:
		if candidate != null and candidate.id == id:
			return candidate
	return null


func ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for candidate in nodes:
		if candidate != null and not candidate.id.is_empty():
			found.append(candidate.id)
	return found


## Every stat name any effect in the tree writes, deduplicated.
##
## The hook an actor uses to check a tree against the stats it actually accepts,
## before a single point is spent on a skill that would silently do nothing.
func stats_used() -> Array[StringName]:
	var used: Array[StringName] = []
	for candidate in nodes:
		if candidate == null:
			continue
		for effect in candidate.effects:
			if effect == null:
				continue
			for stat in effect.stats_used():
				if not used.has(stat):
					used.append(stat)
	return used


## Why the next rank of [param id] cannot be bought given [param ranks], or ""
## if it can. Everything except affordability — see the note at the top.
func refusal(id: StringName, ranks: Dictionary) -> String:
	var target := node(id)
	if target == null:
		return "no such skill: %s" % id
	if int(ranks.get(id, 0)) >= target.max_rank:
		return "%s is already at rank %d" % [target.display_name, target.max_rank]
	if not target.is_open(ranks):
		return "%s needs %s" % [target.display_name, _requirement_text(target)]
	return ""


func can_rank_up(id: StringName, ranks: Dictionary) -> bool:
	return refusal(id, ranks).is_empty()


## Points the next rank of [param id] costs, or 0 for an unknown skill.
func cost_of_next_rank(id: StringName) -> int:
	var target := node(id)
	return target.cost_per_rank if target != null else 0


## Points it would take to buy every rank of every node. What a full build
## costs, and the number a test can hold the tree to.
func total_cost() -> int:
	var total := 0
	for candidate in nodes:
		if candidate != null:
			total += candidate.max_rank * candidate.cost_per_rank
	return total


## Everything structurally wrong with this tree, one line each; empty when it is
## sound.
##
## Checked at load rather than trusted, because a tree is authored in a .tres
## and a mistake there — an id typed twice, a prerequisite naming a node that
## was renamed — produces a skill that is quietly unbuyable rather than an
## error. What this cannot check is whether the stat names mean anything; only
## the actor that owns the stats knows that, which is why [method stats_used]
## exists for it to answer with.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen := {}
	for index in nodes.size():
		var candidate := nodes[index]
		if candidate == null:
			problems.append("node %d is empty" % index)
			continue
		var label := String(candidate.id) if not candidate.id.is_empty() else "node %d" % index
		if candidate.id.is_empty():
			problems.append("%s has no id" % label)
		elif seen.has(candidate.id):
			problems.append("%s is defined twice" % label)
		else:
			seen[candidate.id] = true
		if candidate.max_rank < 1:
			problems.append("%s has max_rank %d" % [label, candidate.max_rank])
		if candidate.cost_per_rank < 1:
			problems.append("%s costs %d points a rank" % [label, candidate.cost_per_rank])
		if candidate.effects.is_empty():
			problems.append("%s does nothing" % label)
		problems.append_array(_requirement_problems(candidate, label))
		problems.append_array(_effect_problems(candidate, label))
	problems.append_array(_cycle_problems())
	return problems


func _requirement_problems(candidate: SkillNode, label: String) -> PackedStringArray:
	var problems := PackedStringArray()
	for required_id in candidate.requires:
		var rank := int(candidate.requires[required_id])
		if required_id == candidate.id:
			problems.append("%s requires itself" % label)
			continue
		var required := node(required_id)
		if required == null:
			problems.append("%s requires unknown skill %s" % [label, required_id])
			continue
		# A requirement above what the other node can reach is the failure this
		# check is really for: it reads as a deep unlock and is a dead node.
		if rank < 1 or rank > required.max_rank:
			problems.append("%s requires rank %d of %s, which caps at %d"
				% [label, rank, required_id, required.max_rank])
	return problems


func _effect_problems(candidate: SkillNode, label: String) -> PackedStringArray:
	var problems := PackedStringArray()
	for index in candidate.effects.size():
		var effect := candidate.effects[index]
		if effect == null:
			problems.append("%s has an empty effect at %d" % [label, index])
			continue
		for problem in effect.problems():
			problems.append("%s: %s" % [label, problem])
	return problems


## Prerequisites that lead back to themselves. The one structural fault that is
## invisible from any single node, and it makes every node on the ring
## permanently unbuyable rather than merely wrong.
func _cycle_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	var state := {}
	for candidate in nodes:
		if candidate != null and not candidate.id.is_empty():
			_walk(candidate.id, state, PackedStringArray(), problems)
	return problems


func _walk(
	id: StringName, state: Dictionary, path: PackedStringArray, problems: PackedStringArray
) -> void:
	var visit := int(state.get(id, 0))
	if visit == 2:
		return
	if visit == 1:
		var ring := path.duplicate()
		ring.append(String(id))
		problems.append("prerequisite cycle: %s" % " -> ".join(ring))
		return
	state[id] = 1
	var here := node(id)
	if here != null:
		var onward := path.duplicate()
		onward.append(String(id))
		for required_id in here.requires:
			_walk(required_id, state, onward, problems)
	state[id] = 2


func _requirement_text(target: SkillNode) -> String:
	var parts := PackedStringArray()
	for required_id in target.requires:
		var required := node(required_id)
		var label := required.display_name if required != null else String(required_id)
		parts.append("%s %d" % [label, int(target.requires[required_id])])
	return " and ".join(parts)
