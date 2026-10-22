class_name VirtualSteeringWheel
extends Control

## Максимальный угол поворота руля в радианах (1.5 * PI = ~270 градусов в каждую сторону)
@export var max_angle: float = 2.5
## Скорость возврата руля в центр при отпускании (радиан в секунду)
@export var return_speed: float = 8.0
## Путь к TextureRect или узлу, который визуально вращается
@export var wheel_node_path: NodePath

var touch_index: int = -1
var last_angle: float = 0.0
var current_rotation: float = 0.0
var steering_value: float = 0.0 # от -1.0 (влево) до 1.0 (вправо)

var wheel_node: Control = null
var vehicle_target: Node = null

signal steering_changed(val: float)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_setup_nodes")

func _setup_nodes() -> void:
	if not wheel_node_path.is_empty():
		wheel_node = get_node_or_null(wheel_node_path) as Control
	if wheel_node == null:
		wheel_node = get_node_or_null("WheelVisual") as Control
	if wheel_node == null:
		wheel_node = self

	if wheel_node:
		wheel_node.pivot_offset = wheel_node.size * 0.5
		wheel_node.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	# Автоматически находим машину, если vehicle_target еще не привязан
	if vehicle_target == null:
		var arena = get_tree().current_scene
		if arena and "local_car" in arena and arena.local_car:
			vehicle_target = arena.local_car

	if touch_index == -1 and absf(current_rotation) > 0.001:
		current_rotation = move_toward(current_rotation, 0.0, return_speed * delta)
		_apply_rotation()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			if _is_point_inside(event.position):
				touch_index = event.index
				last_angle = _get_touch_angle(event.position)
				get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == touch_index:
			touch_index = -1
			get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag and event.index == touch_index:
		var new_angle: float = _get_touch_angle(event.position)
		var delta_ang: float = wrapf(new_angle - last_angle, -PI, PI)
		last_angle = new_angle
		current_rotation = clampf(current_rotation + delta_ang, -max_angle, max_angle)
		_apply_rotation()
		get_viewport().set_input_as_handled()

	# Поддержка мыши для тестов в редакторе / на ПК
	elif OS.is_debug_build() or OS.has_feature("editor"):
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed and touch_index == -1 and _is_point_inside(event.position):
					touch_index = 9999
					last_angle = _get_touch_angle(event.position)
				elif not event.pressed and touch_index == 9999:
					touch_index = -1
		elif event is InputEventMouseMotion and touch_index == 9999:
			var new_angle: float = _get_touch_angle(event.position)
			var delta_ang: float = wrapf(new_angle - last_angle, -PI, PI)
			last_angle = new_angle
			current_rotation = clampf(current_rotation + delta_ang, -max_angle, max_angle)
			_apply_rotation()

func _is_point_inside(global_pos: Vector2) -> bool:
	var rect := get_global_rect()
	var center := rect.position + rect.size * 0.5
	var radius := minf(rect.size.x, rect.size.y) * 0.5 * 1.5 # увеличенная зона для удобного захвата пальцем
	return global_pos.distance_to(center) <= radius

func _get_touch_angle(global_pos: Vector2) -> float:
	var rect := get_global_rect()
	var center := rect.position + rect.size * 0.5
	return (global_pos - center).angle()

func _apply_rotation() -> void:
	if wheel_node:
		wheel_node.pivot_offset = wheel_node.size * 0.5
		wheel_node.rotation = current_rotation

	steering_value = clampf(current_rotation / max_angle, -1.0, 1.0)
	steering_changed.emit(steering_value)

	if vehicle_target and "touch_steering" in vehicle_target:
		vehicle_target.touch_steering = steering_value

func reset_wheel() -> void:
	touch_index = -1
	current_rotation = 0.0
	_apply_rotation()
