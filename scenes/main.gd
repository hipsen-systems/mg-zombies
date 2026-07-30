extends Node3D
## Game entry scene (issues #5, #6, #7, #11).
##
## Owns the order the level comes up in: the map builds itself in its own
## _ready() (children run first), then this script places the hero on the map's
## start cell, bakes the navmesh over the geometry that now exists, and only
## then spawns the zombies — they path on the navmesh, so it has to exist first.
##
## The bake is synchronous (on_thread = false) because the web export has
## thread support disabled.

## Spawn units just above the floor surface and let gravity settle them, rather
## than guessing the exact tile height.
const SPAWN_CLEARANCE := 0.3

const ZOMBIE_SCENE := preload("res://scenes/enemies/zombie.tscn")

## How long the death screen sits there before the run restarts.
const RESTART_DELAY := 2.5

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _level: LevelMap = $NavigationRegion3D/LevelMap
@onready var _hero: Hero = $Hero
@onready var _camera: RTSCamera = $RTSCamera
@onready var _enemies: Node3D = $Enemies
@onready var _health_bar: ProgressBar = $HUD/HealthBar
@onready var _health_value: Label = $HUD/HealthBar/Value
@onready var _death_label: Label = $HUD/DeathLabel
@onready var _attack_move_label: Label = $HUD/AttackMoveLabel


func _ready() -> void:
	_hero.global_position = _level.start_position() + Vector3(0, SPAWN_CLEARANCE, 0)
	_camera.snap_to_target()
	_nav_region.bake_navigation_mesh(false)
	_spawn_zombies()

	_hero.health.health_changed.connect(_on_hero_health_changed)
	_hero.died.connect(_on_hero_died)
	_hero.attack_move_armed_changed.connect(_on_attack_move_armed_changed)
	_on_hero_health_changed(_hero.health.current, _hero.health.max_health)


## One zombie per `Z` cell in the level layout. The map says where an encounter
## is; deciding what stands there is this scene's job, so the map stays pure
## geometry and never has to know the enemy scenes exist.
func _spawn_zombies() -> void:
	for spawn in _level.zombie_spawn_positions():
		var zombie: Zombie = ZOMBIE_SCENE.instantiate()
		# Position before add_child: Zombie._ready() captures where it stands as
		# "home" — the centre of the patch it roams and the anchor of its leash.
		# Enemies sits at the origin, so local and global agree here.
		zombie.position = spawn + Vector3(0, SPAWN_CLEARANCE, 0)
		_enemies.add_child(zombie)


func _on_hero_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_value.text = "%d / %d" % [roundi(current), roundi(maximum)]


## Arming the attack command changes what the *next* left-click means, and a
## mode the player cannot see is a mode they will forget they are in.
func _on_attack_move_armed_changed(armed: bool) -> void:
	_attack_move_label.visible = armed


func _on_hero_died() -> void:
	_death_label.show()
	# Crude restart, which is all issue #7 asks for: a run carries no state
	# worth preserving yet.
	await get_tree().create_timer(RESTART_DELAY).timeout
	get_tree().reload_current_scene()
