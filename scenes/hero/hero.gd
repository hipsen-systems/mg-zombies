class_name Hero
extends CharacterBody3D
## The player-controlled hero: click-to-move (issue #5), takes damage and dies
## (issue #7), and now fights back (issue #11).
##
## Commands follow the StarCraft/Warcraft [b]smart command[/b] model, because
## that is the control scheme the whole game is styled after:
##
## - [b]Right-click[/b] is the smart command: on the ground it is a move order,
##   on an enemy it is an attack order.
## - [b]Left-click[/b] is selection, and never an attack. Nothing consumes a
##   bare left-click yet — the unit info bar is issue #36 — but the binding is
##   reserved now so the two never end up fighting over the button.
## - [b]A, then left-click[/b] is the attack command: on an enemy it attacks
##   that enemy, on the ground it is an attack-move — walk there, but stop to
##   kill anything that comes within [member acquire_radius] on the way, then
##   carry on to where you pointed.
##
## Which orders pick up targets by themselves is the part worth keeping
## straight, and each answer is a decision rather than a side effect:
##
## - [b]MOVE does not.[/b] A move order runs the gauntlet untouched. This is
##   what makes "sprint past the encounter" a real choice instead of a bug.
## - [b]ATTACK_MOVE does.[/b] That is the entire difference between it and MOVE.
## - [b]IDLE does.[/b] A hero standing still defends himself, so a player who
##   is reading the rest of the screen is not chewed on for free. It also makes
##   a separate retaliate-when-hit rule unnecessary: nothing can reach the hero
##   from outside [member acquire_radius] anyway.
## - [b]HOLD does, at a different radius.[/b] It acquires at
##   [member attack_range] rather than [member acquire_radius], so it takes what
##   comes to it and never has anything to walk to — which is the whole of the
##   difference from IDLE.
##
## [b]This script never names an enemy class.[/b] Targets are found through the
## "enemies" group and used through take_damage()/is_dead(), so scenes/hero/
## does not depend on scenes/enemies/ — the dependency runs one way, enemies to
## hero. A second enemy type needs no change in here.

## Emitted with the clamped destination of a plain move order.
##
## [b]Attack-move has its own signal since issue #67[/b], where this one used to
## carry both. They were one signal while nothing consumed either; the order
## marker is the first thing to care, and it draws them in different colours,
## so a listener has to be able to tell them apart. A flag on one signal would
## have done the same job and read worse at every call site.
signal move_ordered(world_point: Vector3)

## Emitted with the clamped destination of an attack-move order (issue #67).
signal attack_move_ordered(world_point: Vector3)

## Emitted when the hero is told to stand his ground, or to stop doing so
## (issue #67).
##
## [b]A mode the player cannot see is a mode they will forget they are in[/b] —
## the same reason [signal attack_move_armed_changed] exists, and the reason this
## reports a *state* rather than an event. Holding is not visible in the world:
## a hero standing his ground and a hero who has finished walking look identical
## until something wanders into reach.
signal holding_position_changed(holding: bool)

## Emitted when the hero is told to attack something — by right-click, by
## A+click, or by acquiring a target on his own.
##
## [b]All four acquiring paths fire it[/b], including a held hero taking what
## walks into his reach. Still unconsumed, which is why that last one is worth
## stating: a gap here would stay invisible until the first listener arrived, and
## then be a bug in a file nobody had touched.
signal attack_ordered(target: Node3D)

## Emitted when a target dies from this hero's damage. The XP hook for issue #8,
## and scenes/main.gd is what consumes it. Attribution is exact — it fires from
## the swing that landed the killing blow, not from the victim's own death
## signal, which any source of damage would trigger.
signal killed(victim: Node3D)

## Emitted when a skill point has been spent and the stat it bought has already
## been applied, so a listener reads the new numbers rather than the old ones.
signal skill_ranked_up(skill: StringName, rank: int)

## Emitted when the attack command is armed or disarmed, so the HUD can show
## the player that the next left-click means "attack" rather than "select".
signal attack_move_armed_changed(armed: bool)

## Emitted for a left-click this script did *not* take — that is, every click
## the armed attack command did not borrow. scenes/ui/ turns it into a selection.
##
## Handing the click on rather than letting the selection code read the mouse
## itself keeps one owner on the button. Two nodes both watching select_command
## would have to agree about the armed state mid-event, and which of them saw it
## first would depend on the order _unhandled_input walks the tree.
signal select_clicked(screen_point: Vector2)

## Emitted when the hero's health hits zero. scenes/main.gd listens, and answers
## it with [method respawn_at] rather than a scene reload (issue #38), so this
## fires once per death and not once per run.
signal died

## What the hero is currently under orders to do.
enum Order {
	## No orders. Holds position, but will defend itself.
	IDLE,
	## Walking somewhere, ignoring everything on the way.
	MOVE,
	## Closing on a specific enemy and swinging once in range.
	ATTACK_TARGET,
	## Walking somewhere, engaging whatever it meets and then resuming.
	ATTACK_MOVE,
	## Standing ground: swings at whatever comes within reach and never moves,
	## not one step (issue #67).
	HOLD,
}

## Ground is physics layer 1, enemies are layer 4 — see the table in
## scenes/CLAUDE.md. A click fires two rays rather than one, because the two
## questions want opposite tie-breaks. The ground ray must ignore walls, so
## clicking a wall means the floor behind it (issue #5). The enemy ray must
## respect them, so clicking a wall never means the zombie behind it. One
## combined query cannot do both, and the floor under a zombie's feet would
## sometimes win it anyway.
const GROUND_MASK := 1
const ENEMY_MASK := 8
const RAY_LENGTH := 1000.0

## Walls and static obstacles (physics layer 2) — the same blocker mask
## scenes/enemies/ tests its own line of sight against.
const SIGHT_BLOCKER_MASK := 2

## Roughly chest height on the 1.8-unit capsule. Matches the zombie's so both
## sight rays agree about what "can see" means; a mismatch would let one side
## see through cover the other treats as solid.
const EYE_HEIGHT := 1.2

const ENEMY_GROUP := "enemies"

## How far from the clicked ground point an enemy still counts as clicked.
##
## A 0.4-radius capsule seen down a ~57° camera is a small thing to hit, and an
## attack order that silently becomes a move order into a pack is the worst
## possible way to miss. If the enemy ray misses, the nearest living enemy
## within this distance of the ground point is taken instead. Keep it under half
## a cell (2.0) or clicking the floor beside a zombie stops meaning the floor.
const CLICK_SLACK := 1.6

## Target reassessment runs on a fixed tick rather than every frame, matching
## the sensing budget scenes/enemies/ already uses. Retargeting is a group scan
## and a repath; neither needs 60 Hz.
const RETARGET_INTERVAL := 0.2

## How far the visual jabs forward on a swing, in metres.
const SWING_LUNGE := 0.45

## Every stat a skill point is allowed to move (issue #9), and the whole of what
## this hero accepts from a [SkillTree]. Effects name stats as strings, so this
## list is what turns a typo in an authored tree into a load-time complaint
## rather than a skill that quietly does nothing — see [method skill_problems].
##
## Note what is [i]not[/i] here. [member acquire_radius] is deliberately not
## sellable: `scenes/map/` guarantees that nothing a respawn restores stands
## within 4 cells (16 units) of where it puts the hero, and that clearance is
## measured against this radius. A skill that grew it past 16 would let a
## respawn land him already in a fight, breaking an invariant three folders lean
## on — and it would break it in another folder's file. If it should ever be
## buyable, the clearance is the thing to change first.
const SKILL_STATS: Array[StringName] = [
	&"attack_damage",
	&"attack_range",
	&"attack_cooldown",
	&"move_speed",
	&"regen_per_second",
	&"max_health",
]

## The stat that does not live on this node. It belongs to the Health child, and
## it has to go through [method Health.set_max_health] rather than a plain write
## because moving the ceiling also heals by the difference.
const STAT_MAX_HEALTH := &"max_health"

## Which key buys which skill, until there is a panel to click (issue #9 is the
## data model; the tree is deliberately larger than the keyboard).
##
## [b]Kept here rather than in the tree data on purpose.[/b] Which key buys what
## is a fact about this hero's control scheme, and `scenes/skills/` must not
## learn about input actions — a tree that carried them could not be shared with
## a second actor, or re-bound without editing game content. The cost is that
## the four nodes without a key are reachable only through
## [method spend_skill_point] until the panel lands, which is the honest state
## for a design PR that ships no UI.
const SKILL_HOTKEYS := [
	{"action": &"skill_strength", "key": "1", "skill": &"strength"},
	{"action": &"skill_health", "key": "2", "skill": &"health"},
]

## What the unit info bar calls him. An export rather than a constant for the
## same reason the stats are: it is per-instance, so a named or unique hero
## needs no new code.
@export var display_name := "Hero"

@export_group("Movement")
@export var move_speed := 6.0
@export var turn_speed := 12.0

@export_group("Combat")
## Reach of the basic attack. Slightly longer than the zombie's, so trading
## blows toe-to-toe is not purely a coin flip.
@export var attack_range := 2.2
@export var attack_damage := 12.0
## Seconds between swings — attack speed, expressed the same way the zombie's is.
@export var attack_cooldown := 0.9
## Radius the hero picks up his own targets in, while idle or attack-moving.
## Well under the zombie's detection radius (12): the hero should be noticed
## before he notices, so a fight starts because the player walked into it.
@export var acquire_radius := 9.0

@export_group("Regeneration")
## Seconds out of combat — neither taking damage nor swinging — before health
## starts coming back. Without this, clearing a fight at low health makes the
## next one unwinnable and the only move is to die on purpose, which is a
## miserable way to use a checkpoint (issue #38).
@export var regen_delay := 5.0
@export var regen_per_second := 4.0

@export_group("Skills")
## What this hero's points can be spent on (issue #9).
##
## An export so a second actor — or a test — can be given a different tree, and
## a default so no hero is ever accidentally left without one. The resource is
## content and holds no ranks, so every hero sharing this instance is correct
## rather than a bug waiting to happen: the ledger below is the per-hero half.
@export var skill_tree: SkillTree = preload("res://scenes/skills/default_tree.tres")

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _dead := false

var _order: Order = Order.IDLE
var _target: Node3D = null
## Where an interrupted attack-move resumes once its fight is over. Guarded by
## a flag rather than a null sentinel so the type stays Vector3.
var _resume_point := Vector3.ZERO
var _has_resume_point := false
var _attack_move_armed := false

var _attack_timer := 0.0
var _retarget_timer := 0.0
var _regen_timer := 0.0
var _swing_tween: Tween = null

## Skill id → ranks bought. Only bought skills appear, so this dictionary is
## also exactly what a save file would have to store — the tree is content and
## can be reloaded, the ranks cannot be reconstructed from anything.
var _skill_ranks := {}

## The stats as authored, captured before any rank was bought. Kept because
## ranks are *recomputed* from these rather than accumulated onto the live
## values: adding a bonus on each purchase drifts the moment anything else ever
## writes to a stat, and cannot be undone by a respec.
var _base_stats := {}

## Accumulators for one recompute — see [method _apply_skills]. Members rather
## than locals so [method add_stat] and [method scale_stat] can be the small
## public surface a [SkillEffect] applies itself through.
var _stat_added := {}
var _stat_scaled := {}

@onready var health: Health = $Health
@onready var experience: Experience = $Experience
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _visual: Node3D = $Visual


func _ready() -> void:
	health.died.connect(_on_health_died)
	for stat in SKILL_STATS:
		_base_stats[stat] = _read_stat(stat)
	# Loud rather than silent: a tree whose ids or stat names are wrong produces
	# skills that refuse or do nothing, which reads in play as a balance problem
	# and is not one.
	for problem in skill_problems():
		push_error("skill tree: %s" % problem)


func is_dead() -> bool:
	return _dead


## Damage entry point — attackers call this rather than reaching into the
## Health child, so the hero stays free to react to a hit later (armour,
## interrupted casts, hit reactions).
func take_damage(amount: float) -> void:
	if _dead:
		return
	_mark_in_combat()
	health.take_damage(amount)


## XP entry point, and [method take_damage]'s counterpart: whoever is paying the
## hero calls this rather than reaching into the Experience child, so he stays
## free to react to a level later — a flourish, a heal, a shout — without every
## caller learning about it.
##
## Deliberately has no `_dead` guard where [method take_damage] does, and the
## asymmetry is the point: refusing damage to a corpse is the rule, whereas
## refusing *credit* to one would silently swallow a kill that lands after the
## hero falls. Nothing can produce one today — he cannot swing while dead — but
## the first damage-over-time effect can, and losing XP is the worse direction
## to be wrong in.
func gain_experience(amount: float) -> void:
	experience.grant(amount)


## Headline stats for the unit info bar (scenes/ui/, issue #36).
##
## The unit reports its own numbers rather than the panel reaching in for named
## properties, because the property that matters differs per actor — travel
## speed here is [member move_speed], on a zombie it is its chase speed. Read-only
## and display-only: nothing acts on this.
func unit_info() -> Dictionary:
	return {
		"name": display_name,
		"damage": attack_damage,
		"attack_cooldown": attack_cooldown,
		"move_speed": move_speed,
	}


# --- Skills ------------------------------------------------------------------

## How many ranks of [param skill] have been bought. Unknown skills read 0.
func skill_rank(skill: StringName) -> int:
	return int(_skill_ranks.get(skill, 0))


## The ledger, as the save file a run does not have yet would store it. Copied
## rather than handed out, because it is the one piece of state a caller could
## corrupt into ranks nobody paid for.
func skill_ranks() -> Dictionary:
	return _skill_ranks.duplicate()


## Why the next rank of [param skill] cannot be bought right now, or "".
##
## The tree answers what is a property of the tree — unknown skill, capped rank,
## prerequisite not met — and this adds the only part it deliberately cannot
## know, which is whether the points are there.
func skill_refusal(skill: StringName) -> String:
	if skill_tree == null:
		return "this hero has no skill tree"
	var refusal := skill_tree.refusal(skill, _skill_ranks)
	if not refusal.is_empty():
		return refusal
	var cost := skill_tree.cost_of_next_rank(skill)
	if experience.skill_points < cost:
		return "costs %d point%s" % [cost, "" if cost == 1 else "s"]
	return ""


## Buy a rank of [param skill], if it is unlocked, not capped, and affordable.
## Returns whether anything happened, so a caller can answer a refused keypress
## without inspecting the ledger itself.
##
## Refusal is silent by design here: a HUD showing 0 points already says why,
## and there is nothing a player can do about it but go and kill something.
## [method skill_refusal] is there for a panel that wants to say more.
func spend_skill_point(skill: StringName) -> bool:
	if not skill_refusal(skill).is_empty():
		return false
	# Last, and only once the rank is known to be buyable: spend() debits the
	# points, so a check after it would have to hand them back.
	if not experience.spend(skill_tree.cost_of_next_rank(skill)):
		return false
	_skill_ranks[skill] = skill_rank(skill) + 1
	_apply_skills()
	skill_ranked_up.emit(skill, skill_rank(skill))
	return true


## The skills a keypress can buy, their ranks and what each has bought, for the
## HUD's crib line.
##
## Reported by the hero rather than assembled by the panel, exactly as
## [method unit_info] is and for the same reason: what a rank *does* is a fact
## about this actor, and a screen that formatted it would have to learn the
## effects to display them.
##
## [b]Deliberately the bound skills and not the whole tree.[/b] That line is a
## reminder of what the keys do; a node the player cannot press has no business
## on it, and six of them would not fit anyway. Drawing the rest is the skill
## panel's job.
func skill_summary() -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	if skill_tree == null:
		return summary
	for binding in SKILL_HOTKEYS:
		var node := skill_tree.node(binding["skill"])
		if node == null:
			continue
		summary.append({
			"name": node.display_name,
			"hotkey": binding["key"],
			"rank": skill_rank(node.id),
			"max_rank": node.max_rank,
			"effect": node.describe(skill_rank(node.id)),
		})
	return summary


## Every node of this hero's tree and its live state, for the skill panel (issue
## #62).
##
## The whole-tree counterpart to [method skill_summary], and the two are
## deliberately different reports rather than one with a flag. That one is the
## crib sheet for the keys and carries only what a keypress can reach; this one
## carries what a panel draws, which is every node whether it is buyable, capped
## or still locked — a tree you cannot see the locked half of is not a tree, it
## is a list.
##
## Same rule as [method unit_info] about who assembles it: the panel formats and
## never interprets, so everything it would otherwise have to work out — what a
## rank costs, why it cannot be bought, what the next one would buy — is answered
## here. [member SkillNode.description] is passed through untouched; it is the one
## field that is authored prose rather than derived.
##
## [param depth] is the tree's own prerequisite depth, not a screen position. How
## a panel arranges the tiers is its business — see [method SkillTree.depth].
func skill_catalogue() -> Array[Dictionary]:
	var catalogue: Array[Dictionary] = []
	if skill_tree == null:
		return catalogue
	for id in skill_tree.ids():
		var node := skill_tree.node(id)
		if node == null:
			continue
		var rank := skill_rank(id)
		catalogue.append({
			"id": id,
			"name": node.display_name,
			"description": node.description,
			"rank": rank,
			"max_rank": node.max_rank,
			"cost": skill_tree.cost_of_next_rank(id),
			"depth": skill_tree.depth(id),
			# "" exactly when a click would succeed, so the panel never has to
			# decide for itself what makes a node buyable.
			"refusal": skill_refusal(id),
			"effect": node.describe(rank),
			# rank + 1, per the note on describe(): it reports what a rank *has*
			# bought, so asking for the current one advertises nothing at rank 0.
			"next_effect": node.describe(rank + 1) if rank < node.max_rank else "",
		})
	return catalogue


## Everything wrong with this hero's tree: the faults the tree can see itself,
## plus the one only an actor can — an effect naming a stat this hero does not
## have. Empty when it is sound.
##
## One implementation with two callers on purpose: [method _ready] turns it into
## errors, and `tests/` asserts it is empty. A stringly-typed stat name is the
## price of keeping `scenes/skills/` ignorant of this file, and an unchecked
## typo would spend a point on nothing at all.
func skill_problems() -> PackedStringArray:
	if skill_tree == null:
		return PackedStringArray(["this hero has no skill tree"])
	var problems := skill_tree.validate()
	for stat in skill_tree.stats_used():
		if not SKILL_STATS.has(stat):
			problems.append("no such stat on this hero: %s" % stat)
	for binding in SKILL_HOTKEYS:
		if skill_tree.node(binding["skill"]) == null:
			problems.append("%s is bound to missing skill %s" % [binding["key"], binding["skill"]])
	return problems


## An additive contribution to [param stat], from a [SkillEffect] applying
## itself. Only meaningful during a recompute.
func add_stat(stat: StringName, amount: float) -> void:
	_stat_added[stat] = float(_stat_added.get(stat, 0.0)) + amount


## A multiplicative contribution to [param stat]. Every one of these lands after
## every [method add_stat] — see [method _apply_skills].
func scale_stat(stat: StringName, factor: float) -> void:
	_stat_scaled[stat] = float(_stat_scaled.get(stat, 1.0)) * factor


## Recompute every sellable stat from the value it was authored with plus the
## ranks bought so far.
##
## [b]Three properties fall out of doing it this way, and all three are the
## point.[/b] It is idempotent, so calling it on every purchase cannot drift.
## The order ranks were bought in cannot change the result, because the fold is
## sum-the-adds-then-multiply-the-scales rather than a running total — which is
## the whole of the stacking rule this game has. And undoing it is free: a
## respec clears the ledger and calls this, and the hero is back to the numbers
## he was authored with, with nothing to unwind.
func _apply_skills() -> void:
	_stat_added.clear()
	_stat_scaled.clear()
	for skill in _skill_ranks:
		var rank := skill_rank(skill)
		var node := skill_tree.node(skill)
		if rank <= 0 or node == null:
			continue
		for effect in node.effects:
			if effect != null:
				effect.apply(self, rank)
	for stat in SKILL_STATS:
		var base := float(_base_stats.get(stat, 0.0))
		var added := float(_stat_added.get(stat, 0.0))
		var scaled := float(_stat_scaled.get(stat, 1.0))
		_write_stat(stat, (base + added) * scaled)


func _read_stat(stat: StringName) -> float:
	if stat == STAT_MAX_HEALTH:
		return health.max_health
	return float(get(stat))


## The one place a stat name becomes a property, and the one place the exception
## lives: max health belongs to the Health child and has to move through its own
## setter, which heals by the difference rather than diluting the bar.
func _write_stat(stat: StringName, value: float) -> void:
	if stat == STAT_MAX_HEALTH:
		health.set_max_health(value)
		return
	set(stat, value)


## Come back at [param point] with full health, ready to take orders (issue #38).
##
## The hero is revived in place rather than rebuilt, because the run around him
## survives his death: everything cleared behind the armed checkpoint stays
## cleared, so there is no scene to reload. Every piece of state a death leaves
## behind is reset here — the death flag, the orders, the armed attack command,
## the carried velocity, and the three timers.
##
## [b]The timers are cleared to stop state leaking across a death, not to hold
## him back.[/b] They count *down*, and _physics_process returns above the line
## that decrements them while [member _dead] is set, so they are frozen at
## whatever they read when he fell — dying mid-cooldown would otherwise make his
## first swing of the new life wait out the remainder of the last one. Zeroing
## them means the opposite of a delay: he lands fully ready.
##
## What actually stops him swinging the moment he arrives is not here at all.
## It is the map's rule that nothing a respawn [i]restores[/i] stands within 4
## cells of the cell it puts him on (see scenes/map/CLAUDE.md), which is well
## outside [member acquire_radius], so there is nothing to acquire on the frame
## he comes back. Restored is load-bearing, and issue #54 is where it got added:
## stated over every placement the rule is false, and one zombie behind the boss
## gate is the counterexample. That is the invariant to re-check if a checkpoint
## is ever placed with less clearance — not this reset. Issue #9 left
## [member acquire_radius] out of [constant SKILL_STATS] so that no skill can
## grow it into the clearance, and tests/ asserts as much.
func respawn_at(point: Vector3) -> void:
	_dead = false
	_clear_orders()
	_set_attack_move_armed(false)
	velocity = Vector3.ZERO
	global_position = point
	# The agent is still holding the path he was walking when he died, and
	# nothing else clears it: leave it and the first order after the respawn is
	# judged finished or not against a destination from the previous life.
	_nav_agent.target_position = point
	_attack_timer = 0.0
	_retarget_timer = 0.0
	_regen_timer = 0.0
	# Last, so health_changed reaches the HUD with the hero already alive and
	# standing where he belongs.
	health.revive()


## What the hero is currently doing, for the HUD and for tests.
func current_order() -> Order:
	return _order


## Whether he is currently standing his ground (issue #67).
##
## The same question as [code]current_order() == Order.HOLD[/code], and it exists
## because `tests/` cannot ask it that way: that folder holds the hero untyped on
## purpose, so naming the enum would make it fail to parse whenever the global
## class cache is missing. Reads better than the comparison anyway, which is why
## it is public rather than a note in the test.
func is_holding_position() -> bool:
	return _order == Order.HOLD


## The enemy the hero is currently attacking, or null.
func current_target() -> Node3D:
	return _target if _is_valid_target(_target) else null


# --- Commands ----------------------------------------------------------------

## Public move order — also the entry point for future AI/skills/tests.
##
## Issuing an order cancels the previous one outright: the target is replaced
## (NavigationAgent3D repaths on the next query) and the carried-over horizontal
## velocity is dropped so the hero cannot coast another frame along the
## abandoned heading. Rapid re-clicking therefore reads as an instant redirect.
func command_move_to(world_point: Vector3) -> void:
	var reachable := _on_navmesh(world_point)
	_clear_orders()
	_order = Order.MOVE
	_nav_agent.target_position = reachable
	move_ordered.emit(reachable)


## Attack a specific enemy: close on it, then swing on cooldown until it dies.
## Ignored for anything that is not a living enemy, so a stale click cannot
## leave the hero attacking a corpse.
func command_attack(target: Node3D) -> void:
	if not _is_valid_target(target):
		return
	_clear_orders()
	_order = Order.ATTACK_TARGET
	_target = target
	_nav_agent.target_position = _on_navmesh(target.global_position)
	attack_ordered.emit(target)


## Attack-move: walk to a point, engaging anything that comes within
## [member acquire_radius] and resuming afterwards.
func command_attack_move(world_point: Vector3) -> void:
	var reachable := _on_navmesh(world_point)
	_clear_orders()
	_order = Order.ATTACK_MOVE
	_resume_point = reachable
	_has_resume_point = true
	_nav_agent.target_position = reachable
	attack_move_ordered.emit(reachable)


## Stand ground: swing at whatever comes within [member attack_range] and do not
## move for it (issue #67).
##
## [b]The difference from IDLE is the whole feature, and it is not "does he
## fight".[/b] Both fight. An idle hero acquires anything within
## [member acquire_radius] — nine units, four times his reach — and walks to it,
## which is what makes him wander out of a doorway the player parked him in.
## Holding acquires at reach and never travels, so the position the player chose
## is the position he keeps.
func command_hold_position() -> void:
	# Already holding: re-pressing the key must not re-announce a state that has
	# not changed, and there is nothing else to reset — he is standing still with
	# no destination by definition.
	if _order == Order.HOLD:
		return
	_clear_orders()
	_order = Order.HOLD
	# The agent is still holding the path from the last order. Left alone, the
	# *next* order after this one is judged finished or not against a stale
	# destination — the same trap respawn_at() documents.
	_nav_agent.target_position = global_position
	holding_position_changed.emit(true)


## Drop every order and stand there. Bound to `S` since issue #67; it has existed
## unbound since issue #5 as the public way to cancel an order.
##
## Note this leaves him IDLE rather than HOLD, and the two differ: he will still
## acquire and walk to anything inside [member acquire_radius]. "Stop what you are
## doing" and "stand exactly here" are separate commands in the scheme this game
## copies, and collapsing them would leave no way to say the first.
func command_stop() -> void:
	_clear_orders()


func _clear_orders() -> void:
	# Before the assignment, so the state it reports is the one being left. This
	# is the only path out of HOLD: every command routes through here, as do death
	# and respawn, and nothing else assigns the order away from it — _reassess()
	# and _finish_engagement() both leave a held hero held.
	var was_holding := _order == Order.HOLD
	_order = Order.IDLE
	_target = null
	_has_resume_point = false
	# Drop the carried-over heading so a new order never coasts a frame along
	# the old one.
	velocity.x = 0.0
	velocity.z = 0.0
	if was_holding:
		holding_position_changed.emit(false)


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		return

	if event.is_action_pressed("attack_move"):
		_set_attack_move_armed(not _attack_move_armed)
		return

	if event.is_action_pressed("cancel_command"):
		_set_attack_move_armed(false)
		return

	# Both disarm `A` first, on the rule the right-click handler below already
	# keeps: any command cancels an armed attack, or the arming survives the
	# command that was meant to replace it. `S` is the more obvious of the two —
	# a key that means "cancel what you are doing" leaving a half-issued attack
	# command loaded would be the plainest possible surprise.
	if event.is_action_pressed("hold_position"):
		_set_attack_move_armed(false)
		command_hold_position()
		return

	if event.is_action_pressed("stop_command"):
		_set_attack_move_armed(false)
		command_stop()
		return

	# Spending a point is not a command, so it deliberately does not disarm `A`
	# or cancel an order — a player banking a level mid-fight keeps whatever the
	# hero was doing. Driven from the table so a re-binding is one entry, and
	# above the click handlers because none of these are mouse buttons anyway.
	for binding in SKILL_HOTKEYS:
		if event.is_action_pressed(binding["action"]):
			spend_skill_point(binding["skill"])
			return

	# Use the position carried by the click itself rather than the live mouse
	# position: the two can differ by the time the event is handled, and it
	# keeps this path deterministic for headless tests.
	if event.is_action_pressed("select_command"):
		if not _attack_move_armed:
			# A bare left-click is selection (issue #36), which scenes/ui/ owns.
			# Deliberately not an attack: an RTS where inspecting a unit also
			# swings at it is unusable.
			select_clicked.emit((event as InputEventMouseButton).position)
			return
		_set_attack_move_armed(false)
		_issue_attack_click((event as InputEventMouseButton).position)
		return

	if event.is_action_pressed("move_command"):
		# Any world command cancels an armed attack — otherwise the arming
		# survives the click that was meant to replace it.
		_set_attack_move_armed(false)
		_issue_smart_click((event as InputEventMouseButton).position)


## Right-click: attack what is under the cursor, or move to the ground.
func _issue_smart_click(screen_point: Vector2) -> void:
	var ground = _ground_point_at(screen_point)
	var enemy := _target_at(screen_point, ground)
	if enemy != null:
		command_attack(enemy)
	elif ground != null:
		command_move_to(ground)


## A + left-click: attack what is under the cursor, or attack-move to the ground.
func _issue_attack_click(screen_point: Vector2) -> void:
	var ground = _ground_point_at(screen_point)
	var enemy := _target_at(screen_point, ground)
	if enemy != null:
		command_attack(enemy)
	elif ground != null:
		command_attack_move(ground)


func _set_attack_move_armed(armed: bool) -> void:
	if _attack_move_armed == armed:
		return
	_attack_move_armed = armed
	attack_move_armed_changed.emit(armed)


# --- Per-frame ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if _dead:
		_halt()
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_tick_regen(delta)

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		_reassess()

	match _order:
		Order.IDLE:
			_halt()
		Order.MOVE, Order.ATTACK_MOVE:
			_process_travel(delta)
		Order.ATTACK_TARGET:
			_process_attack(delta)
		Order.HOLD:
			_process_hold(delta)


## Order bookkeeping and target acquisition. Runs on the retarget tick, not
## every frame — everything that needs per-frame precision (the cooldown,
## gravity, movement) lives in _physics_process instead.
func _reassess() -> void:
	match _order:
		# The two acquiring orders, sharing one branch because they acquire
		# identically. What differs is what happens after the kill, and that is
		# _finish_engagement()'s job: an attack-move keeps its destination and
		# carries on, an idle hero simply stands down again.
		Order.IDLE, Order.ATTACK_MOVE:
			var found := _nearest_enemy_to(global_position, acquire_radius, true)
			if found != null:
				_engage(found)

		Order.ATTACK_TARGET:
			if not _is_valid_target(_target):
				_finish_engagement()
				return
			# Repath only while out of reach. Repathing inside attack range
			# would fight the "stand still and swing" branch every tick.
			if _horizontal_distance_to(_target.global_position) > attack_range:
				_nav_agent.target_position = _on_navmesh(_target.global_position)

		# Holding acquires like the two above and at a different radius, which is
		# the entire behaviour: at reach rather than at [member acquire_radius],
		# so there is never anything to walk to. It stays in HOLD while it does —
		# taking a target here by switching to ATTACK_TARGET would hand the hero
		# straight back to the branch that repaths, and the hold would end the
		# first time anything strayed near him.
		#
		# Everything _engage() does *except* the order change and the repath,
		# which are the two things a hold must not do — so it is written out
		# rather than called. The signal is not optional: [signal attack_ordered]
		# says it fires when he takes a target on his own, and a held hero doing
		# exactly that would otherwise be the one acquisition that never
		# announced itself. Nothing consumes it yet, which is precisely why the
		# gap would have gone unnoticed until something did.
		Order.HOLD:
			if not _is_valid_target(_target):
				var found := _nearest_enemy_to(global_position, attack_range, true)
				if found != null:
					_target = found
					attack_ordered.emit(found)

		Order.MOVE:
			pass


## Take a target without disturbing a pending attack-move destination.
func _engage(target: Node3D) -> void:
	_order = Order.ATTACK_TARGET
	_target = target
	_nav_agent.target_position = _on_navmesh(target.global_position)
	attack_ordered.emit(target)


## The target is gone: resume the attack-move that was interrupted, or stand down.
func _finish_engagement() -> void:
	_target = null
	# A hold outlives whatever walked into it. Without this the order would end on
	# the first kill — the hero would stand his ground right up until the moment
	# it mattered and then quietly stop, which is worse than not having the
	# command, because the player has already stopped watching him.
	if _order == Order.HOLD:
		return
	if _has_resume_point:
		_order = Order.ATTACK_MOVE
		_nav_agent.target_position = _resume_point
	else:
		_order = Order.IDLE


func _process_travel(delta: float) -> void:
	if _nav_agent.is_navigation_finished():
		_order = Order.IDLE
		_has_resume_point = false
		_halt()
		return
	_travel(delta, move_speed)


func _process_attack(delta: float) -> void:
	if not _is_valid_target(_target):
		# _reassess() cleans this up on the next tick; until then, stand.
		_halt()
		return

	# `to_target` is the facing direction only. The range test goes through the
	# shared helper, so this check and the repath check in _reassess() are one
	# code path rather than two that happen to agree today.
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	if _horizontal_distance_to(_target.global_position) > attack_range:
		if _nav_agent.is_navigation_finished():
			# The path says we arrived and the target is still out of reach, so
			# it is not reachable from here — the navmesh clamp put its goal
			# somewhere we cannot close on. Stand and face rather than jitter.
			# Deliberately not "give up": dropping the target would re-acquire
			# the same one on the next tick and flap. The player can always
			# issue another order.
			_face(to_target, delta)
			_halt()
			return
		_travel(delta, move_speed)
		return

	_halt()
	_face(to_target, delta)
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	_swing(_target)


## Standing ground (issue #67): swing at what is in reach, and do not move for
## anything.
##
## Deliberately a near-copy of the tail of [method _process_attack] rather than a
## share of it. What that method mostly *is* is the decision about closing on a
## target — repath, or stand and face because the path is finished — and this
## order exists precisely to have no such decision. Factoring the two together
## would mean a helper whose first act is to branch on which caller it has.
func _process_hold(delta: float) -> void:
	_halt()
	if not _is_valid_target(_target):
		# _reassess() picks one up on the next tick if anything is in reach; until
		# then, stand. Nothing here reaches for a target of its own, because that
		# would run the group scan at 60 Hz rather than at RETARGET_INTERVAL.
		return
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	_face(to_target, delta)
	# Range is re-tested every frame even though _reassess() only ever hands this
	# order a target that was in reach when it looked, because the *target* moves:
	# a zombie that walks back out between reassessments would otherwise be hit
	# from beyond reach for up to a tick. Through the shared helper, so this is
	# the same measurement _process_attack makes rather than a third one that
	# happens to agree.
	if _horizontal_distance_to(_target.global_position) > attack_range:
		return
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	_swing(_target)


## Land a hit. There is no wind-up: the blow arrives the instant the cooldown
## expires, matching the zombie. Add a telegraph on both when there are attack
## animations to hang one on.
func _swing(target: Node3D) -> void:
	_mark_in_combat()
	_play_swing()
	target.take_damage(attack_damage)
	# Health.died fires synchronously inside take_damage(), so the victim
	# already knows it is dead by the time this returns.
	if target.has_method("is_dead") and target.is_dead():
		killed.emit(target)
		_finish_engagement()


func _play_swing() -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_visual.position.z = 0.0
	# Forward is -Z, matching the node's facing convention.
	_swing_tween = create_tween()
	_swing_tween.tween_property(_visual, "position:z", -SWING_LUNGE, 0.08)
	_swing_tween.tween_property(_visual, "position:z", 0.0, 0.16)


func _tick_regen(delta: float) -> void:
	_regen_timer = maxf(_regen_timer - delta, 0.0)
	if _regen_timer > 0.0:
		return
	if health.current >= health.max_health:
		return
	health.heal(regen_per_second * delta)


## Both taking a hit and landing one count as combat, so a hero trading blows
## never regenerates mid-fight.
func _mark_in_combat() -> void:
	_regen_timer = regen_delay


# --- Movement helpers --------------------------------------------------------

func _travel(delta: float, speed: float) -> void:
	var next := _nav_agent.get_next_path_position()
	var direction := next - global_position
	direction.y = 0.0
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()
	_face(direction, delta)


## Every range test in this script measures horizontally, and they must all
## agree. `_reassess()` decides whether to repath and `_process_attack()`
## decides whether to swing, both against `attack_range`; if one of them counted
## the height difference and the other did not, they would disagree at the
## boundary and the hero would repath and swing in alternate ticks. Flat floors
## hide that today — the first ramp or ledge would not.
func _horizontal_distance_to(point: Vector3) -> float:
	var offset := point - global_position
	offset.y = 0.0
	return offset.length()


## Hold position but keep stepping the body, so gravity still settles it.
func _halt() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()


## Turn toward a horizontal direction. Forward is -Z (Godot's convention), so a
## rigged model drops in later without a compensating rotation.
func _face(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return
	direction = direction.normalized()
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


## Clamp a world point onto the navigation map, so an order is never
## unreachable — a click on the void outside the level becomes "walk as far
## that way as you can" instead of a path request that resolves to nothing.
func _on_navmesh(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, point)


# --- Picking things out of the world -----------------------------------------

## Resolve a screen position to a point on the ground.
##
## The raycast alone is not enough: it only collides with the ground layer, so
## a click on the dark background, past the edge of the level, or above a wall
## produces no hit at all. Dropping those clicks is what made a second click
## look like it was ignored — the hero silently kept walking to its previous
## destination. Falling back to the hero's ground plane means every click
## yields a point; the order it turns into then clamps it onto the navmesh.
##
## Returns a Vector3, or null if there is no camera to project from.
func _ground_point_at(screen_point: Vector2):
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_point)
	var direction := camera.project_ray_normal(screen_point)
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * RAY_LENGTH, GROUND_MASK
	)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		return result.position
	var ground := Plane(Vector3.UP, global_position.y)
	return ground.intersects_ray(origin, direction)


## The enemy a click means, if any.
##
## **Walls are in this ray's mask, and that is the whole point of it.** With
## enemies alone the ray tunnelled: clicking a wall with a zombie behind it
## resolved to an attack order on a zombie the player could not see, and the
## hero walked off to fight it. Including layer 2 makes the nearer surface win,
## which is what the renderer decides too, so a click can only name an enemy
## that is actually drawn.
##
## Not a general occlusion solve, and the reason is worth knowing: rock caps
## carry no collider on purpose (see scenes/map/CLAUDE.md), so a ray into a rock
## mass is stopped by the wall pieces bounding it rather than by the rock
## itself. Those sit on every rock/floor boundary at full wall height, so a
## descending click ray meets one on its way out — everything except a ray
## threading the corner gap where two of them meet.
func _target_at(screen_point: Vector2, ground_point) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_point)
	var direction := camera.project_ray_normal(screen_point)
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * RAY_LENGTH, ENEMY_MASK | SIGHT_BLOCKER_MASK
	)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		if _is_valid_target(result.collider):
			return result.collider
		# A wall got there first, so whatever is past it is off screen. The
		# click stays a ground order rather than becoming an attack.
		return null
	# The ray met neither enemy nor wall, so the click landed on open floor or
	# past the edge of the level. Only here is the slack radius safe to apply —
	# there is nothing between the camera and that ground to hide a zombie.
	if ground_point == null:
		return null
	return _nearest_enemy_to(ground_point, CLICK_SLACK)


## Nearest living enemy to a point, measured horizontally so a unit's height
## never decides which of two is closer. Returns null if none is within range.
##
## `require_sight` is true only for automatic acquisition, and it is measured
## from the hero rather than from `point` — the two are the same thing there.
## The click paths pass false on purpose: the player can only click something
## already drawn on screen, so demanding a second opinion from a raycast would
## only reject clicks the player could plainly see were valid.
func _nearest_enemy_to(point: Vector3, radius: float, require_sight := false) -> Node3D:
	var best: Node3D = null
	var best_distance := radius
	for candidate in get_tree().get_nodes_in_group(ENEMY_GROUP):
		if not _is_valid_target(candidate):
			continue
		var enemy := candidate as Node3D
		var offset := enemy.global_position - point
		offset.y = 0.0
		var distance := offset.length()
		if distance > best_distance:
			continue
		# Sight last: it is a raycast, and the cheap distance test has already
		# thrown out most of the group by the time we get here.
		if require_sight and not _can_see(enemy):
			continue
		best = enemy
		best_distance = distance
	return best


## Chest-to-chest ray against walls only, mirroring the zombie's.
##
## Without it the hero picks up targets through solid rock and walks off to
## fight something the player never saw — the same complaint scenes/enemies/
## records in reverse ("zombies detect the hero through solid rock, then appear
## round a corner for no visible reason"), and worse here, because this is the
## unit the player is supposed to be commanding.
func _can_see(target: Node3D) -> bool:
	var from := global_position + Vector3.UP * EYE_HEIGHT
	var to := target.global_position + Vector3.UP * EYE_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to, SIGHT_BLOCKER_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Everything this script assumes about an enemy, in one place: it is a live
## node in the tree, it is in the enemies group, and it is not already dead.
## Deliberately duck-typed — see the note at the top about the dependency
## direction between scenes/hero/ and scenes/enemies/.
func _is_valid_target(candidate) -> bool:
	if not is_instance_valid(candidate):
		return false
	var node := candidate as Node3D
	if node == null or not node.is_inside_tree():
		return false
	if not node.is_in_group(ENEMY_GROUP):
		return false
	if node.has_method("is_dead") and node.is_dead():
		return false
	return true


func _on_health_died() -> void:
	_dead = true
	_clear_orders()
	_set_attack_move_armed(false)
	velocity = Vector3.ZERO
	died.emit()
