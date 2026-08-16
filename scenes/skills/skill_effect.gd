class_name SkillEffect
extends Resource
## What one node of the skill tree does when ranks of it are bought (issue #9).
##
## [b]The base class names a seam rather than abstracting over one.[/b] Every
## effect in the game today is a [StatModifier], and that is deliberate: issue #9
## chose a fold over authored numbers instead of a modifier system with sources,
## durations and stacking rules. What the base buys is that the [i]second[/i]
## kind — a behaviour grant, an ability, a passive that changes how an order
## resolves — arrives as another subclass and changes nothing in the tree, in the
## ledger, or in the fold that applies them.
##
## [b]An effect applies itself to an actor; the actor does not interpret the
## effect.[/b] That is what stops scenes/hero/ growing a branch per effect kind.
## The actor's half is a small duck-typed surface — add_stat(), scale_stat() —
## in the same spirit as the take_damage()/is_dead() contract scenes/hero/
## already uses on enemies, and for the same reason: this folder must not name
## the classes that consume it.
##
## [b]apply() runs on every recompute, not once per purchase.[/b] The actor
## resets to its authored values and folds the whole ledger in again, so an
## implementation has to be a pure statement of "rank N of me is worth this" —
## never an accumulation onto a live value, and never a side effect that would
## be wrong to fire twice. That is what makes a purchase idempotent, and it is
## the same property a respec would rest on.


## Fold [param rank] ranks of this effect into [param actor]. Override.
func apply(_actor: Object, _rank: int) -> void:
	pass


## How [param rank] ranks of this reads on screen, e.g. "+6 dmg". Override.
## Empty for an effect with nothing worth showing, or for rank 0.
func describe(_rank: int) -> String:
	return ""


## Every stat name this effect writes.
##
## Stat names are strings, which is the price of keeping this folder ignorant of
## the actor that owns them — and a typo in one would otherwise be a skill that
## silently does nothing. This method is what lets an actor check a tree against
## the stats it actually accepts before the first point is ever spent. Override
## in anything that writes a stat.
func stats_used() -> Array[StringName]:
	var none: Array[StringName] = []
	return none


## Everything wrong with this effect as authored, one line each. Collected by
## [method SkillTree.validate], which calls it rather than inspecting subclasses
## — checking a new effect kind is then the new subclass's own business, and the
## tree never learns what kinds exist. Override.
func problems() -> PackedStringArray:
	return PackedStringArray()
