class_name SkillPanel
extends Control
## The skill tree as something a player can actually click (issue #62).
##
## Issue #9 landed the tree with no UI, which left four of its six nodes with no
## way to be bought in play at all — `1` and `2` reach Strength and Health and
## nothing reaches the rest. Inventing four more hotkeys would be a worse answer
## than none, so this is the answer instead.
##
## [b]It formats and never interprets[/b], the same rule the skill line above it
## keeps: every number and every sentence here comes from
## [method Hero.skill_catalogue]. This script does not know what a rank buys, what
## one costs, or why one cannot be bought — it knows how to lay six of them out
## and which one was clicked. A new skill in the .tres therefore appears here with
## no edit to this folder, which is the whole test of whether the split is real.
##
## [b]The layout is derived, not authored.[/b] Nodes are grouped into rows by
## their prerequisite depth, so the row a node lands in follows from what it
## requires. The alternative — a position per node, edited here — would have to be
## touched every time game content gained a skill, which is exactly the coupling
## the tree was designed to avoid. See [method SkillTree.depth].

## The player clicked a node they want a rank of. Nothing here buys anything:
## this folder does not own the points, the ledger, or the rules, and a widget
## that spent them would be the second owner of all three. Same arrangement as
## [signal HUD.restart_requested].
signal rank_up_requested(skill: StringName)

## The panel opened or closed. The tree is frozen while it is up and
## `scenes/main.gd` is what freezes it — this only reports the change, for the
## reason recorded on [signal HUD.restart_requested]: the pause flag lives on the
## SceneTree rather than the scene, so exactly one script may own it.
signal toggled(open: bool)

const LOCKED_COLOR := Color(0.55, 0.58, 0.66)
const OPEN_COLOR := Color(0.86, 0.88, 0.94)
const AFFORDABLE_COLOR := Color(1, 0.85, 0.4)
const MAXED_COLOR := Color(0.62, 0.84, 0.66)

@onready var _rows: VBoxContainer = $Frame/Margin/Body/Rows
@onready var _points_label: Label = $Frame/Margin/Body/Points

## Refused while the run is over. The victory panel owns the screen at that point
## and says so in its own folder doc; this keeps that true from here rather than
## relying on nobody pressing the key.
var _available := true


func _ready() -> void:
	# The tree is paused while this is up, and a paused node receives neither
	# input nor GUI dispatch — which would leave the panel unable to close itself
	# and every button dead under the cursor. Set here rather than in the scene
	# file so the reason travels with the line, exactly as the victory panel does.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


## [b]This folder reads one key, and this is it.[/b] Every other input action in
## the project is consumed by `scenes/hero/`, because every other one is a command
## to a unit. Opening a panel is not: it issues no order and changes nothing about
## what the hero is doing, so routing it through the command scheme would put a
## screen toggle in the file that owns attack-move.
##
## Safe alongside that scheme for the reason `scenes/ui/`'s doc already records
## about the victory button: this is a keyboard action nothing else claims, not a
## second listener on the mouse button the hero owns.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_skills"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"cancel_command"):
		# Escape closes it. The hero also treats Escape as "disarm", and both can
		# run without conflicting — but only because this consumes the event, so
		# closing the panel does not also reach into the game behind it.
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	elif _available:
		open()


func open() -> void:
	if visible or not _available:
		return
	show()
	toggled.emit(true)


func close() -> void:
	if not visible:
		return
	hide()
	toggled.emit(false)


## Take the panel down and keep it down. Called when the run is won: the victory
## panel owns the screen from then on, and a skill tree openable behind it would
## also unfreeze the game on the way out.
func set_unavailable() -> void:
	_available = false
	close()


## Redraw from the hero's own report of his tree.
##
## Rebuilt outright rather than patched in place. Redraws happen when a point is
## earned or spent — rare, and never per-frame — and a rebuild cannot leave a card
## showing a rank that was refunded or a refusal that has since been met. The
## patched version would be faster and would have state to get wrong.
func set_catalogue(points: int, catalogue: Array) -> void:
	if not is_node_ready():
		return
	_points_label.text = "%d skill point%s to spend" % [points, "" if points == 1 else "s"]
	_points_label.modulate = AFFORDABLE_COLOR if points > 0 else OPEN_COLOR
	for row in _rows.get_children():
		row.queue_free()
		# Freed at the end of the frame, so a rebuild in the same frame would
		# otherwise stack the new rows under the old ones.
		_rows.remove_child(row)
	for depth in _depths(catalogue):
		_rows.add_child(_build_row(depth, catalogue))


## The prerequisite depths present in [param catalogue], shallowest first. Read
## off the data rather than assumed to be 0..n: a tree whose middle tier is empty
## should draw as two rows, not three with a gap.
func _depths(catalogue: Array) -> Array[int]:
	var depths: Array[int] = []
	for entry in catalogue:
		var depth := int(entry.get("depth", 0))
		if not depths.has(depth):
			depths.append(depth)
	depths.sort()
	return depths


func _build_row(depth: int, catalogue: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 12)
	for entry in catalogue:
		if int(entry.get("depth", 0)) == depth:
			row.add_child(_build_card(entry))
	return row


## One node: what it is, what it has bought, and a button that asks for the next
## rank. Every string in here arrives ready to print.
func _build_card(entry: Dictionary) -> Control:
	var rank := int(entry.get("rank", 0))
	var max_rank := int(entry.get("max_rank", 0))
	var refusal := String(entry.get("refusal", ""))
	var maxed := rank >= max_rank

	var card := PanelContainer.new()
	# A floor on the height, not a fixed one. Cards hold a wrapping description and
	# an effect line that is empty until something is bought, so left to themselves
	# they come out at three different heights in one row and the buttons sit at
	# three different places. The spacer below pins the button to the bottom of
	# whatever height the row settles on.
	card.custom_minimum_size = Vector2(228, 140)

	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 2)
	card.add_child(body)

	var heading := Label.new()
	heading.text = "%s   %d/%d" % [entry.get("name", "?"), rank, max_rank]
	heading.add_theme_font_size_override(&"font_size", 16)
	# Three states worth telling apart at a glance, and the colours are the ones
	# the skill line already uses for two of them: gold means a point would be
	# taken right now, green means there is nothing left to buy here, grey means
	# locked or unaffordable and the button says which.
	if maxed:
		heading.modulate = MAXED_COLOR
	elif refusal.is_empty():
		heading.modulate = AFFORDABLE_COLOR
	else:
		heading.modulate = LOCKED_COLOR if rank == 0 else OPEN_COLOR
	body.add_child(heading)

	var description := Label.new()
	description.text = String(entry.get("description", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override(&"font_size", 12)
	description.modulate = LOCKED_COLOR
	body.add_child(description)

	var bought := Label.new()
	# Empty at rank 0, which is what describe() reports and the right answer: a
	# node nothing has been spent on has bought nothing to list.
	bought.text = String(entry.get("effect", ""))
	bought.visible = not bought.text.is_empty()
	bought.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bought.add_theme_font_size_override(&"font_size", 12)
	bought.modulate = OPEN_COLOR
	body.add_child(bought)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)

	body.add_child(_build_button(entry, refusal, maxed))
	return card


func _build_button(entry: Dictionary, refusal: String, maxed: bool) -> Button:
	var button := Button.new()
	button.disabled = not refusal.is_empty()
	if maxed:
		button.text = "Maxed"
	elif refusal.is_empty():
		button.text = "Buy — %d pt" % int(entry.get("cost", 0))
	else:
		button.text = refusal
	# The next rank's effect, on the control that would buy it. describe() reports
	# what a rank *has* bought, so the catalogue asks it for rank + 1 — a button
	# advertising the current rank would read blank on everything unbought.
	var next_effect := String(entry.get("next_effect", ""))
	button.tooltip_text = next_effect if not next_effect.is_empty() else refusal
	button.add_theme_font_size_override(&"font_size", 12)
	var id: StringName = entry.get("id", &"")
	button.pressed.connect(func() -> void: rank_up_requested.emit(id))
	return button
