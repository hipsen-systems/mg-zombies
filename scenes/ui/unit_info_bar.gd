class_name UnitInfoBar
extends PanelContainer
## The bottom-of-screen panel describing the selected unit (issue #36): its
## name, live hit points, and the three numbers that decide a fight.
##
## It reads a unit through three duck-typed hooks and never names Hero or Zombie:
##
## - [code]unit_info() -> Dictionary[/code] for the display name and the stats,
##   so a unit reports its own numbers rather than this panel guessing which
##   property holds them. A zombie's travel speed is [code]chase_speed[/code] and
##   the hero's is [code]move_speed[/code]; only they know which of theirs is the
##   one worth showing.
## - a [code]Health[/code] child for the bar, subscribed to while it is shown so
##   damage lands on screen as it happens.
## - an optional [code]stats_changed[/code] signal, subscribed to on the same
##   terms so a stat moving under this panel lands on screen too (issue #65).
##
## [b]Both subscriptions exist for one reason: nothing here can notice a value
## changing by itself.[/b] The stats row used to be read once at selection and
## never again, so buying a rank of Strength left the old damage on screen until
## the player selected another unit and came back. A unit that never emits is
## simply one whose row never needs redrawing, which is why the hook is optional
## rather than a fourth required member of the contract.
##
## Keys are read with defaults, so a unit that reports only some of them shows
## a dash for the rest instead of failing.

const UNKNOWN := "—"

## The optional hook above. Named once because it is used three times — connect,
## disconnect, and the guard on each — and a typo in any of them would fail
## silently, leaving exactly the stale row this was written to fix.
const STATS_CHANGED := &"stats_changed"

var _unit: Node3D = null
var _health: Health = null

@onready var _name_label: Label = $Margin/Rows/NameLabel
@onready var _hp_bar: ProgressBar = $Margin/Rows/HpBar
@onready var _hp_value: Label = $Margin/Rows/HpBar/Value
@onready var _stats_label: Label = $Margin/Rows/StatsLabel


## Point the panel at a unit. Null hides it, which should not happen in play —
## selection always falls back to the hero — but a hidden panel beats a stale
## one if it ever does.
func show_unit(unit: Node3D) -> void:
	_unsubscribe()
	_unit = unit
	if not is_instance_valid(_unit) or not _unit.has_method("unit_info"):
		_unit = null
		hide()
		return

	_draw_stats()
	if _unit.has_signal(STATS_CHANGED):
		_unit.connect(STATS_CHANGED, _draw_stats)

	_health = _unit.get("health") as Health
	if _health != null:
		_health.health_changed.connect(_on_health_changed)
		_on_health_changed(_health.current, _health.max_health)
	else:
		_hp_bar.hide()
	show()


## Draw the name and the stats row from the unit's own report.
##
## Re-read every time rather than cached, which is the whole of the fix for issue
## #65: a stat can move while the selection does not, so the values this row was
## drawn from are not the values the unit currently has.
func _draw_stats() -> void:
	if not is_instance_valid(_unit):
		return
	var info: Dictionary = _unit.call("unit_info")
	_name_label.text = str(info.get("name", "Unit"))
	_stats_label.text = "DMG %s     ATK SPD %s     SPEED %s" % [
		_format_number(info.get("damage")),
		_format_attack_speed(info.get("attack_cooldown")),
		_format_number(info.get("move_speed")),
	]


## is_instance_valid, not a null check, for the reason UnitSelection records: a
## unit can leave the level without dying, so this can be holding a freed Health
## — a reference that is non-null and unusable at once. Ordering in
## scenes/main.gd happens to redirect the panel before anything is freed, but
## that protection lives in another folder, and the sibling class does not lean
## on it.
##
## Called before _unit is reassigned, so both disconnects still name the unit
## they were made against.
func _unsubscribe() -> void:
	if is_instance_valid(_health) and _health.health_changed.is_connected(_on_health_changed):
		_health.health_changed.disconnect(_on_health_changed)
	_health = null
	_hp_bar.show()
	if is_instance_valid(_unit) and _unit.has_signal(STATS_CHANGED) \
			and _unit.is_connected(STATS_CHANGED, _draw_stats):
		_unit.disconnect(STATS_CHANGED, _draw_stats)


func _on_health_changed(current: float, maximum: float) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value = current
	_hp_value.text = "%d / %d" % [roundi(current), roundi(maximum)]


## Seconds between swings is how both actors store attack speed, but it reads
## backwards on a HUD — a bigger number is a worse attacker. Shown as swings per
## second so the three stats all improve upwards.
func _format_attack_speed(cooldown) -> String:
	if not (cooldown is float or cooldown is int) or float(cooldown) <= 0.0:
		return UNKNOWN
	return "%.2f/s" % (1.0 / float(cooldown))


## One decimal, with a bare ".0" trimmed off — 12 rather than 12.0, but 3.4 kept.
## GDScript's format strings have no %g, so the trim is done by hand.
func _format_number(value) -> String:
	if not (value is float or value is int):
		return UNKNOWN
	var text := "%.1f" % float(value)
	return text.trim_suffix(".0")
