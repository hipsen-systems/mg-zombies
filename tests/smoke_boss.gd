extends "res://tests/harness.gd"
## The run can actually be finished (issue #66).
##
## [b]This is the only assertion in the suite that the game is completable[/b],
## and it exists because the game was not: the boss shipped in #39 with numbers
## its own folder doc called "a first pass", and playtesting found that no build
## a player can reach could kill it. Every check was green throughout — nothing
## here or anywhere else asserted that the last encounter has a solution.
##
## [b]What is measured, and why it is the boss alone.[/b] The hero is funded with
## exactly the XP the level pays — one kill per `Z` cell, nothing invented — and
## then fights the boss with the room cleared. That is not a softer fight than the
## real one, which is the part worth following: the points being spent here are
## *paid for* by those same kills, so a hero who has them has already cleared the
## room by definition. Measured with the room still standing the fight is lost, as
## it should be: that models charging the gate without doing the level, and such a
## hero would not have the points either.
##
## [b]It is deliberately the worst play available.[/b] `command_attack` walks in
## and stands there trading blows, which is exactly what the boss's longer reach
## is designed to punish — see `scenes/enemies/`. So this asserts the floor: if
## standing still and swinging wins by a hair, then moving wins properly, and the
## encounter has a solution for a player who has not mastered it. It says nothing
## about the ceiling.

## What one zombie is worth. Read here rather than off a spawn, because the point
## of the funding below is to reproduce *the level's whole yield*, and reading the
## reward from the thing being counted would make it agree with itself.
const XP_PER_ZOMBIE := 10.0

## The margin that says the fight is still a fight. Generous on purpose — the
## bound, not the measured value, is what is asserted, and the measurement (10 of
## 100 hp) sits far outside it. If a hero change ever turns this red, that is the
## signal and not a false alarm: re-measure and decide, do not widen it.
const WALKOVER_FRACTION := 0.75

## Frames to let the fight resolve. ~12 s measured; this is 60.
const FIGHT_BUDGET := 3600


func _check() -> void:
	var boss := _find_boss()
	if not check("the boss is standing in the level", boss != null):
		return

	# Isolate the encounter — see the header for why this is the real fight and
	# not a softer one. remove_child before queue_free, the same ordering
	# scenes/main.gd uses on respawn: a freed-but-still-parented zombie stays in
	# the enemies group for one more frame and the hero can acquire it.
	var cleared := 0
	for enemy in get_nodes_in_group("enemies"):
		if enemy != boss and is_instance_valid(enemy):
			enemy.get_parent().remove_child(enemy)
			enemy.queue_free()
			cleared += 1

	# Start him on the boss-room gate, which is where a player who has just armed
	# that checkpoint begins. respawn_at() rather than a bare move, because it is
	# the public method that both places him and fills him up — a test must not
	# reach into the Health child to do the second half.
	var gates: Array[PackedVector3Array] = level.checkpoints()
	hero.respawn_at(gates[gates.size() - 1][0])
	await step(10)

	# The level's entire yield, and not a point more.
	var spawns: Array[Dictionary] = level.zombie_spawns()
	check("the cleared room is the level's whole zombie population",
		cleared == spawns.size(), "%d cleared, %d spawns" % [cleared, spawns.size()])
	hero.gain_experience(float(spawns.size()) * XP_PER_ZOMBIE)
	var points: int = hero.experience.skill_points
	check("killing every zombie in the level pays at least one point", points > 0,
		"level %d, %d point(s) from %d kills"
			% [hero.experience.level, points, spawns.size()])
	# Damage is what a small pool buys best: Frenzy needs two ranks of Strength
	# before it opens and then costs two a rank.
	while hero.spend_skill_point(&"strength"):
		pass
	var info: Dictionary = hero.unit_info()
	note("hero: %.0f hp, %.0f dmg / %.2f s = %.1f dps" % [
		hero.health.max_health, info["damage"], info["attack_cooldown"],
		float(info["damage"]) / float(info["attack_cooldown"])])
	note("boss: %.0f hp, %.0f dmg / %.1f s, reach %.1f against his %.1f" % [
		boss.health.max_health, boss.attack_damage, boss.attack_cooldown,
		boss.attack_range, hero.attack_range])

	hero.command_attack(boss)
	await wait_for("the fight resolves", func() -> bool:
		return hero.is_dead() or boss.is_dead(), FIGHT_BUDGET)
	if not check("a hero who did the level can kill the boss", boss.is_dead(),
		"boss left on %.0f/%.0f hp" % [boss.health.current, boss.health.max_health]):
		return
	check("and is alive at the end of it", not hero.is_dead())
	note("won with %.0f/%.0f hp" % [hero.health.current, hero.health.max_health])
	check("and it was not a walkover",
		hero.health.current < hero.health.max_health * WALKOVER_FRACTION,
		"%.0f of %.0f hp left" % [hero.health.current, hero.health.max_health])
	done()


## The boss by its own report rather than by node name or by class: it is the
## same script and the same group as every zombie, and what makes it the boss is
## what it calls itself.
func _find_boss() -> Node3D:
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.get("display_name") == "Zombie Warlord":
			return enemy
	return null
