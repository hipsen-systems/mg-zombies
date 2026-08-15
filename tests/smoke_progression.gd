extends "res://tests/harness.gd"
## Kills pay XP, XP pays levels, levels pay skill points — and nothing else
## (issue #8).
##
## [b]The assertion this file exists for is a negative one:[/b] that reaching a
## level changes no stat by itself. That is the design rule the whole skill tree
## rests on — two heroes of the same level are different builds because of what
## they spent, not what they reached — and it is the kind of rule that decays
## quietly, since the obvious "improvement" is to make levelling feel generous by
## slipping a stat into it.
##
## The kills are real, because kill-to-XP is the wiring under test and a granted
## number would prove only that the component adds up. Once a level has been
## earned the honest way, the second one is topped up through
## [method Hero.gain_experience] rather than by walking to five more zombies:
## what is being checked past that point is spending, and the walking is already
## covered by the other tests.
##
## [b]The top-up goes through the hero, not into his Experience child.[/b] The
## two are the same call — one forwards to the other — but scenes/components/
## states "only writing goes through the owner" without exceptions, and a test
## is the worst place to take the first one: it is the file a reader copies when
## they write the second.

## Budget for one engagement — closing the distance plus the fight. Measured at
## ~6-10 s each in smoke_combat.gd, and the first kills here are the same fight.
const ENGAGE_BUDGET := 1800

var _levels: Array = []


func _check() -> void:
	var progress = hero.experience
	check("the hero starts at level 1 with nothing banked",
		progress.level == 1 and progress.skill_points == 0 and is_zero_approx(progress.xp),
		"level %d, %.0f xp, %d point(s)" % [progress.level, progress.xp, progress.skill_points])

	# Connected before the first swing, so what is measured is every level the
	# run produced rather than the ones that happened after we started looking.
	progress.leveled_up.connect(func(level: int, points: int) -> void: _levels.append([level, points]))

	var damage_at_start: float = hero.attack_damage
	var max_health_at_start: float = hero.health.max_health
	var needed: float = progress.xp_to_next()
	note("level 2 costs %.0f xp; a zombie is worth %.0f" % [needed, _nearest_reward()])

	# --- 1. a kill pays XP ----------------------------------------------------
	if not await _kill_one("the first kill lands"):
		return
	check("killing a zombie grants xp", progress.xp > 0.0 or progress.level > 1,
		"%.0f xp toward level %d" % [progress.xp, progress.level])

	# --- 2. enough kills level him up -----------------------------------------
	# Bounded rather than counted: how many kills a level costs is a balance
	# number and this test must not be the thing that freezes it.
	var kills := 1
	while progress.level < 2 and kills < 8:
		if not await _kill_one("kill %d lands" % (kills + 1)):
			return
		kills += 1
	if not check("killing zombies levels the hero up", progress.level == 2,
		"level %d after %d kill(s)" % [progress.level, kills]):
		return
	check("the level-up fired once, with a point", _levels == [[2, 1]],
		"leveled_up fired %s" % [_levels])
	check("the level paid a skill point", progress.skill_points == 1,
		"%d point(s) unspent" % progress.skill_points)

	# --- 3. and the level alone changed no stat -------------------------------
	# The rule this file exists for. Levelling is worth points and nothing else;
	# every stat gain in the game is bought.
	check("levelling up on its own raises no stat",
		is_equal_approx(hero.attack_damage, damage_at_start)
			and is_equal_approx(hero.health.max_health, max_health_at_start),
		"%.0f dmg / %.0f max hp, unchanged" % [hero.attack_damage, hero.health.max_health])

	# --- 4. spending a point is what raises one -------------------------------
	check("a point buys a rank of strength", hero.spend_skill_point(&"strength"))
	check("strength raised the hero's damage",
		is_equal_approx(hero.attack_damage, damage_at_start + hero.strength_damage_per_rank),
		"%.0f -> %.0f dmg" % [damage_at_start, hero.attack_damage])
	check("the point is gone", progress.skill_points == 0)
	check("a second point cannot be spent from an empty pool",
		not hero.spend_skill_point(&"strength"),
		"still rank %d" % hero.skill_rank(&"strength"))

	# --- 5. the other skill, and what a raised ceiling does to current hp ------
	hero.gain_experience(progress.xp_to_next())
	if not check("a second level pays a second point",
		progress.level == 3 and progress.skill_points == 1,
		"level %d, %d point(s)" % [progress.level, progress.skill_points]):
		return
	var hp_before: float = hero.health.current
	check("a point buys a rank of health", hero.spend_skill_point(&"health"))
	check("health raised the ceiling",
		is_equal_approx(hero.health.max_health, max_health_at_start + hero.health_per_rank),
		"%.0f -> %.0f max hp" % [max_health_at_start, hero.health.max_health])
	# The half that is easy to get wrong: buying hit points at 40/100 must leave
	# 50/110, not 40/110. A point that visibly does nothing reads as one wasted.
	check("and healed by the same amount rather than diluting the bar",
		is_equal_approx(hero.health.current, hp_before + hero.health_per_rank),
		"%.0f -> %.0f hp" % [hp_before, hero.health.current])

	# --- 6. a rank cannot be bought past its cap ------------------------------
	# Deliberately overfunded, so what stops the purchases is the cap and not an
	# empty pool — those are the two refusals, and a test that cannot tell them
	# apart proves neither.
	hero.gain_experience(progress.xp_to_next() * 20.0)
	var rank_before: int = hero.skill_rank(&"strength")
	var points_before: int = progress.skill_points
	var max_rank: int = hero.skill_max_rank
	var attempts := max_rank + 2
	var bought := 0
	for i in attempts:
		if hero.spend_skill_point(&"strength"):
			bought += 1
	check("a skill stops at its maximum rank",
		hero.skill_rank(&"strength") == max_rank,
		"rank %d of %d" % [hero.skill_rank(&"strength"), max_rank])
	check("and every refused purchase past it spent nothing",
		bought == max_rank - rank_before and progress.skill_points == points_before - bought,
		"%d of %d attempts bought a rank, %d of %d points left"
			% [bought, attempts, progress.skill_points, points_before])
	done()


## Order the nearest zombie killed and wait it out. Returns false once something
## has already failed, so the caller can stop rather than pile on.
func _kill_one(what: String) -> bool:
	var target = _nearest_enemy()
	if not check("%s: there is something to fight" % what, target != null):
		return false
	hero.command_attack(target)
	return await wait_for(
		what,
		func() -> bool: return not is_instance_valid(target) or target.is_dead(),
		ENGAGE_BUDGET,
		{"the hero lost the fight": func() -> bool: return hero.is_dead()},
	)


func _nearest_reward() -> float:
	var target = _nearest_enemy()
	return target.xp_reward if target != null else 0.0


## Nearest living enemy to the hero, horizontally.
func _nearest_enemy():
	var best = null
	var best_distance := INF
	for enemy in living_enemies():
		var offset: Vector3 = enemy.global_position - hero.global_position
		offset.y = 0.0
		if offset.length() < best_distance:
			best_distance = offset.length()
			best = enemy
	return best
