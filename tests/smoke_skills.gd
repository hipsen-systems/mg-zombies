extends "res://tests/harness.gd"
## The skill tree is sound, it gates what it says it gates, and buying all of it
## does not break something in another folder (issue #9).
##
## [b]Two of these assertions are the reason the file exists, and neither is
## about the tree working.[/b] They are about what a tree is allowed to sell:
##
## - The hero must not be able to buy his way past the boss's reach. That
##   inversion is the boss's whole identity — every zombie loses the range
##   contest, the boss wins it — and a range skill is the one thing that can
##   undo it silently, from a .tres in a different folder.
## - The hero must not be able to buy an acquisition radius wider than the
##   clearance a respawn is placed with. `scenes/map/` promises 4 cells between
##   where a death puts him and anything a respawn restores; that promise is
##   measured against `acquire_radius`, so growing the radius breaks a rule
##   stated in three folder docs and enforced in none of them.
##
## Both are cross-folder invariants that no single folder's own checks can see,
## which is what makes them worth a test rather than a paragraph. The rest of
## the file is the ordinary half: validation, gating, cost, and the cap.

## Enough XP to fund a full build several times over. The tree costs 26 points;
## what is under test past this line is spending, not earning.
const FUNDING_LEVELS := 60

## Cells of clearance `scenes/map/` places a respawn with, and the size of a
## cell — kept here rather than read from the map because this test is asserting
## that the *skill tree* respects a documented figure, and reading the figure
## from the thing it constrains would make the check circular.
const RESPAWN_CLEARANCE_CELLS := 4.0
const CELL_SIZE := 4.0


func _check() -> void:
	var tree = hero.skill_tree
	if not check("the hero has a skill tree", tree != null):
		return
	note("%d nodes, %d points for a full build" % [tree.nodes.size(), tree.total_cost()])

	# --- 1. the shipped tree is sound -----------------------------------------
	# Structure plus stat names: the tree can check the first on its own, and
	# only the hero knows whether `attack_damge` is a stat or a typo.
	var problems: PackedStringArray = hero.skill_problems()
	if not check("the shipped tree has nothing wrong with it", problems.is_empty(),
		"; ".join(problems)):
		return

	# ...and the checker is not simply agreeable. A clean result on a good tree
	# proves nothing about validation; the shipped tree passing is exactly what a
	# validate() that always returned nothing would also look like. Cross-review
	# of PR #61 reported the cycle check as dead code — it is not, but the reason
	# nobody could tell from the suite was this gap.
	#
	# A cycle is the fault chosen because it is the one no single node can see.
	# The tree is deep-duplicated first: the hero's is a shared preloaded
	# resource, so mutating it in place would corrupt the run this test is still
	# using.
	var broken = tree.duplicate(true)
	broken.nodes[0].requires = {broken.nodes[1].id: 1}
	broken.nodes[1].requires = {broken.nodes[0].id: 1}
	var caught := PackedStringArray()
	for problem in broken.validate():
		if problem.contains("cycle"):
			caught.append(problem)
	check("a prerequisite cycle is caught rather than shipped",
		not caught.is_empty(), "; ".join(caught))
	check("and the hero's own tree was not the one edited",
		hero.skill_problems().is_empty())

	# --- 2. a gated node is refused until its prerequisite is met --------------
	# Funded first and deliberately overfunded, so what refuses the purchase is
	# the prerequisite and not an empty pool. Those are the two refusals, and a
	# test that cannot tell them apart proves neither.
	_fund()
	var funded: int = hero.experience.skill_points
	check("a gated skill is refused before its prerequisite",
		not hero.spend_skill_point(&"reach"),
		hero.skill_refusal(&"reach"))
	check("and the refusal cost nothing",
		hero.skill_rank(&"reach") == 0 and hero.experience.skill_points > 0)

	var strength_needed: int = tree.node(&"reach").requires[&"strength"]
	for i in strength_needed:
		if not check("strength rank %d" % (i + 1), hero.spend_skill_point(&"strength")):
			return
	check("meeting the prerequisite opens it", hero.skill_refusal(&"reach").is_empty())

	# --- 3. a node costs what it says it costs --------------------------------
	var cost: int = tree.cost_of_next_rank(&"reach")
	var points_before: int = hero.experience.skill_points
	check("the gated skill costs more than one point", cost > 1, "%d points" % cost)
	check("and it can now be bought", hero.spend_skill_point(&"reach"))
	check("for exactly its stated cost",
		hero.experience.skill_points == points_before - cost,
		"%d -> %d points" % [points_before, hero.experience.skill_points])

	# --- 4. buying the whole tree ---------------------------------------------
	# Every node to its cap, in whatever order the sweep reaches them. That the
	# order does not matter is the fold's property, not an accident: adds are
	# summed against the authored base and scales multiply what is left.
	_buy_everything(tree)
	var unbought := PackedStringArray()
	for id in tree.ids():
		var node = tree.node(id)
		if hero.skill_rank(id) < node.max_rank:
			unbought.append("%s %d/%d" % [id, hero.skill_rank(id), node.max_rank])
	if not check("every node reaches its maximum rank", unbought.is_empty(),
		"; ".join(unbought)):
		return
	# Measured against the pool rather than by counting purchases, so the three
	# ranks bought above are included and nothing can be spent unaccounted for.
	var spent: int = funded - hero.experience.skill_points
	check("and a full build costs exactly what the tree says",
		spent == tree.total_cost(), "%d of %d points" % [spent, tree.total_cost()])
	check("nothing can be bought past that",
		not hero.spend_skill_point(&"strength"),
		hero.skill_refusal(&"strength"))

	# --- 5. what a full build must still not be able to do --------------------
	# See the header. Both numbers belong to other folders; this is the only
	# place either is checked against what the tree sells.
	var boss = _boss()
	if not check("the boss is in the level to measure against", boss != null):
		return
	check("a fully invested hero still does not out-reach the boss",
		hero.attack_range < boss.attack_range,
		"%.1f against the boss's %.1f" % [hero.attack_range, boss.attack_range])

	var clearance := RESPAWN_CLEARANCE_CELLS * CELL_SIZE
	check("and cannot see further than a respawn is cleared for",
		hero.acquire_radius <= clearance,
		"%.1f acquire radius against %.0f units of clearance" % [hero.acquire_radius, clearance])
	done()


## Level the hero up enough times to fund a full build several times over.
## Through his own entry point, never into the Experience child — writes go
## through the owner, and a test is the worst place to take the first exception.
func _fund() -> void:
	for i in FUNDING_LEVELS:
		hero.gain_experience(hero.experience.xp_to_next())


## Buy every rank of every node, sweeping until a pass buys nothing.
##
## Sweeping rather than walking the prerequisites in order is the point: it
## proves the gates open as their requirements are met, without this file
## knowing the shape of the tree. It is also what makes the purchase order
## arbitrary, which the fold has to be indifferent to.
func _buy_everything(tree) -> void:
	var bought := true
	while bought:
		bought = false
		for id in tree.ids():
			while hero.spend_skill_point(id):
				bought = true


## The end boss, told from the trash by its reach — the stat under test here.
## Deliberately not found by class: every enemy in the level is a Zombie.
func _boss():
	var widest = null
	for enemy in living_enemies():
		if widest == null or enemy.attack_range > widest.attack_range:
			widest = enemy
	return widest
