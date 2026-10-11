extends Control

@export var radius: float = 100.0
## Необязательно: путь к узлу-ползунку, если он называется не "Knob"
@export var knob_path: NodePath

var touch_index: int = -1
var knob: Control
var player: Node

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	player = _find_player()
	knob = _find_knob()
	if knob == null:
		knob = _create_knob()
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# size ещё может быть нулевым в момент _ready, поэтому откладываем
	_reset_knob.call_deferred()

func _find_player() -> Node:
	var n: Node = get_parent()
	while n:
		if n.has_method("touch_action"):
			return n
		n = n.get_parent()
	return null

func _find_knob() -> Control:
	if not knob_path.is_empty():
		var by_path := get_node_or_null(knob_path) as Control
		if by_path:
			return by_path
	var by_name := get_node_or_null("Knob") as Control
	if by_name:
		return by_name
	for child in get_children():
		if child is Control:
			return child
	return null

func _create_knob() -> Control:
	var k := Panel.new()
	k.name = "Knob"
	k.custom_minimum_size = Vector2(60, 60)
	k.size = Vector2(60, 60)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.5)
	style.set_corner_radius_all(30)
	k.add_theme_stylebox_override("panel", style)
	add_child(k)
	return k

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Чужие копии игрока не должны реагировать на касания
	if player == null or not player.is_multiplayer_authority():
		return

	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1 and get_global_rect().has_point(event.position):
			touch_index = event.index
			_update(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == touch_index:
			touch_index = -1
			player.touch_move = Vector2.ZERO
			_reset_knob()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == touch_index:
		_update(event.position)
		get_viewport().set_input_as_handled()

func _update(pos: Vector2) -> void:
	var center: Vector2 = global_position + size / 2.0
	var v: Vector2 = (pos - center).limit_length(radius)
	knob.position = size / 2.0 - knob.size / 2.0 + v
	player.touch_move = v / radius

func _reset_knob() -> void:
	if knob == null:
		return
	knob.position = size / 2.0 - knob.size / 2.0
