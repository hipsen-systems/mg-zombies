extends Node3D
## Game entry scene (issues #5, #6, #7, #11, #36, #38).
##
## Owns the order the level comes up in: the map builds itself in its own
## _ready() (children run first), then this script places the hero on the map's
## start cell, bakes the navmesh over the geometry that now exists, and only
## then spawns the zombies — they path on the navmesh, so it has to exist first.
##
## The bake is synchronous (on_thread = false) because the web export has
## thread support disabled.
##
## It also wires the HUD and unit selection (scenes/ui/) to the hero, and that
## is all it does with them: this script calls HUD methods and never touches a
## Label, so the layout is free to change without a gameplay script changing too.
##
## [b]It owns the respawn rule.[/b] The map says where the checkpoints are and
## which stretch of the run each spawn belongs to; deciding what a death costs is
## this script's, because it is the one thing here that knows both the armed
## checkpoint and what is currently standing in the level.

## Spawn units just above the floor surface and let gravity settle them, rather
## than guessing the exact tile height.
const SPAWN_CLEARANCE := 0.3

const ZOMBIE_SCENE := preload("res://scenes/enemies/zombie.tscn")
const CHECKPOINT_SCENE := preload("res://scenes/map/checkpoint.tscn")

## How long the death screen sits there before the hero comes back.
const RESPAWN_DELAY := 2.5

## Which stretch of the run a spawned zombie came from, so a respawn can restore
## exactly the ones ahead of the armed checkpoint. Stored on the instance because
## the alternative — a list kept here — would be a second record of a set the
## scene tree already holds, and zombies remove themselves from it when a corpse
## finishes fading.
const SEGMENT_META := &"checkpoint_segment"

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _level: LevelMap = $NavigationRegion3D/LevelMap
@onready var _hero: Hero = $Hero
@onready var _camera: RTSCamera = $RTSCamera
@onready var _enemies: Node3D = $Enemies
@onready var _checkpoints_root: Node3D = $Checkpoints
@onready var _hud: HUD = $HUD
@onready var _selection: UnitSelection = $UnitSelection

## Where the hero comes back, one entry per checkpoint. Entry 0 is the start
## cell, so this is never empty and a death before the first pad still respawns.
var _respawn_points := PackedVector3Array()
var _checkpoint_nodes: Array[Checkpoint] = []
var _armed_checkpoint := 0


func _ready() -> void:
	_hero.global_position = _level.start_position() + Vector3(0, SPAWN_CLEARANCE, 0)
	_camera.snap_to_target()
	_nav_region.bake_navigation_mesh(false)
	_place_checkpoints()
	_spawn_zombies(0)

	_hero.health.health_changed.connect(_hud.set_hero_health)
	_hero.died.connect(_on_hero_died)
	_hero.attack_move_armed_changed.connect(_hud.set_attack_move_armed)
	# The hero owns the left mouse button because he owns the command scheme it
	# belongs to, and hands on the clicks his attack command did not take.
	_hero.select_clicked.connect(_selection.select_at)
	_selection.selection_changed.connect(_hud.show_unit)

	_hud.set_hero_health(_hero.health.current, _hero.health.max_health)
	# Last, and after the connection above: the hero starts selected, and the
	# info bar only learns that from the signal this emits.
	_selection.select_unit(_hero)


## One zombie per `Z` cell from [param from_segment] onward. The map says where
## an encounter is; deciding what stands there is this scene's job, so the map
## stays pure geometry and never has to know the enemy scenes exist.
func _spawn_zombies(from_segment: int) -> void:
	for spawn in _level.zombie_spawns():
		var segment: int = spawn["segment"]
		if segment < from_segment:
			continue
		var zombie: Zombie = ZOMBIE_SCENE.instantiate()
		zombie.set_meta(SEGMENT_META, segment)
		# Position before add_child: Zombie._ready() captures where it stands as
		# "home" — the centre of the patch it roams and the anchor of its leash.
		# Enemies sits at the origin, so local and global agree here.
		zombie.position = spawn["position"] + Vector3(0, SPAWN_CLEARANCE, 0)
		_enemies.add_child(zombie)


## Lay the checkpoint pads the map marked out.
func _place_checkpoints() -> void:
	var groups := _level.checkpoints()
	for index in groups.size():
		# The nearest cell of a checkpoint is where the hero comes back — see
		# LevelMap.checkpoints() for why it is a cell and not an average.
		_respawn_points.append(groups[index][0])
		# Checkpoint 0 is the start cell. It gets no pad: the map already paints
		# it green, and it is the one checkpoint that arms itself, since the hero
		# is standing on it before he can walk anywhere.
		if index == 0:
			continue
		var checkpoint: Checkpoint = CHECKPOINT_SCENE.instantiate()
		checkpoint.setup(index, groups[index])
		checkpoint.reached.connect(_on_checkpoint_reached)
		_checkpoint_nodes.append(checkpoint)
		_checkpoints_root.add_child(checkpoint)


## The hero stepped on a pad. The most recently armed checkpoint is the one he
## comes back to, so walking back through an earlier one really does hand back
## the ground in between — the lit pad is always the promise being made.
func _on_checkpoint_reached(index: int) -> void:
	if index == _armed_checkpoint:
		return
	_armed_checkpoint = index
	for checkpoint in _checkpoint_nodes:
		checkpoint.set_armed(checkpoint.index == index)
	_hud.flash_checkpoint()


func _on_hero_died() -> void:
	_hud.show_death()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_inside_tree():
		return
	_respawn()


## Put the hero back at the armed checkpoint and restore the run ahead of it.
##
## [b]Only what is ahead.[/b] Everything cleared behind the checkpoint stays
## cleared, so a death costs the segment being fought and not the run; and
## everything ahead is restored, so a hard fight cannot be whittled down by
## dying at it over and over.
func _respawn() -> void:
	_hud.hide_death()
	# Before the clear below, not after: the info bar may be pointed at a zombie
	# that is about to be freed, and it has no way to notice one that is removed
	# rather than killed.
	_selection.select_unit(_hero)
	# Clear first, then spawn. Restoring a segment means putting it back as it
	# was authored, which is not the same as topping up the survivors — a zombie
	# left mid-chase would otherwise stay standing wherever it ran the hero down,
	# alongside a fresh copy of every one that died.
	_clear_from_segment(_armed_checkpoint)
	_spawn_zombies(_armed_checkpoint)
	_hero.respawn_at(_respawn_points[_armed_checkpoint] + Vector3(0, SPAWN_CLEARANCE, 0))
	# The hero has teleported, so the follow camera would otherwise sail across
	# the level — the same reason _ready() snaps after placing him.
	_camera.snap_to_target()


## Remove every zombie from [param from_segment] onward, living, chasing or
## already a corpse.
##
## remove_child before queue_free, so they leave the `enemies` group this frame
## rather than at the end of it: a freed-but-still-parented zombie is one the
## hero can acquire and walk toward on the tick between the two.
func _clear_from_segment(from_segment: int) -> void:
	for zombie in _enemies.get_children():
		if int(zombie.get_meta(SEGMENT_META, 0)) < from_segment:
			continue
		_enemies.remove_child(zombie)
		zombie.queue_free()
