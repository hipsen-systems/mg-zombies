class_name StatModifier
extends SkillEffect
## A [SkillEffect] that moves one of an actor's numbers.
##
## The only effect kind the game has, and the reason the fold has two phases:
## every [constant Mode.ADD] on a stat is summed and applied to the authored
## base, and only then is every [constant Mode.SCALE] on it multiplied in. That
## single ordering rule is what a stacking system would otherwise have to
## exist to answer, and it means the order ranks are bought in can never change
## the result.


enum Mode {
	## base + per_rank * rank.
	ADD,
	## base * (1 + per_rank * rank). Linear rather than compounding, so three
	## ranks of -8% is -24% and not -22.1%: a rank should be worth exactly what
	## the rank before it was, or the last one in a branch reads as a swindle.
	SCALE,
}

## The stat this moves, named as the actor knows it. Checked against the stats
## the actor accepts — see [method SkillEffect.stats_used].
@export var stat: StringName = &""
@export var mode: Mode = Mode.ADD
## What one rank is worth. Signed: a negative [constant Mode.ADD] is a cost, and
## a negative [constant Mode.SCALE] is a reduction — which is how a shorter
## attack cooldown is authored, since less of it is better.
@export var per_rank := 0.0
## Unit shown after the number, e.g. "dmg". Display only, and free text: the
## actor's stat name is rarely what a player should be reading.
@export var unit := ""


func apply(actor: Object, rank: int) -> void:
	match mode:
		Mode.ADD:
			actor.add_stat(stat, per_rank * rank)
		Mode.SCALE:
			actor.scale_stat(stat, 1.0 + per_rank * rank)


func describe(rank: int) -> String:
	if rank <= 0:
		return ""
	if mode == Mode.SCALE:
		return "%s%%%s" % [_signed(per_rank * rank * 100.0), _suffix()]
	return "%s%s" % [_signed(per_rank * rank), _suffix()]


func stats_used() -> Array[StringName]:
	var used: Array[StringName] = []
	if not stat.is_empty():
		used.append(stat)
	return used


func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if stat.is_empty():
		found.append("a stat modifier names no stat")
	# Zero is not merely useless, it is the shape a half-authored node has: the
	# stat picked, the number not yet filled in.
	if is_zero_approx(per_rank):
		found.append("%s is modified by 0 a rank" % stat)
	return found


func _suffix() -> String:
	return "" if unit.is_empty() else " " + unit


## Signed, with a trailing ".0" trimmed off by hand — GDScript has no "%g", the
## same dodge scenes/ui/ makes for the same reason.
static func _signed(value: float) -> String:
	var text := "%+.1f" % value
	return text.trim_suffix(".0")
