class_name MenuCamera
extends Camera3D

@export var orbit_center: Vector3 = Vector3(0.0, 2.2, 0.0)
@export var base_speed: float = 0.18 # Радианы в секунду при speed = 1.0

var current_angle: float = 0.8
var current_dist: float = 27.0
var current_height: float = 15.0
var target_dist: float = 27.0
var target_height: float = 15.0
var target_center: Vector3 = Vector3(0.0, 2.2, 0.0)

var is_dragging: bool = false
var drag_touch_index: int = -1
var last_pointer_pos: Vector2 = Vector2.ZERO
var user_interaction_timer: float = 0.0

# Режим слежения за ботами (Action mode)
var target_bot: MenuRobot = null
var bot_switch_timer: float = 0.0

func _ready() -> void:
	current_dist = GameSettings.menu_camera_distance
	target_dist = current_dist
	current_height = GameSettings.menu_camera_height
	target_height = current_height
	_update_camera_transform(1.0)

func _process(delta: float) -> void:
	var mode: int = GameSettings.menu_camera_mode
	var speed_mult: float = GameSettings.menu_camera_speed

	if user_interaction_timer > 0.0:
		user_interaction_timer -= delta
	else:
		if mode == 0: # Обычная орбита
			current_angle += base_speed * speed_mult * delta
			target_center = target_center.lerp(orbit_center, delta * 3.0)
		elif mode == 1: # Экшен (слежение за активным ботом)
			_process_action_mode(delta, speed_mult)
		elif mode == 2: # Статичный ракурс
			target_center = target_center.lerp(orbit_center, delta * 3.0)

	# Плавная интерполяция высоты и дистанции
	current_dist = lerpf(current_dist, target_dist, delta * 6.0)
	current_height = lerpf(current_height, target_height, delta * 6.0)

	_update_camera_transform(delta)

func _process_action_mode(delta: float, speed_mult: float) -> void:
	bot_switch_timer -= delta
	if not is_instance_valid(target_bot) or target_bot.is_dead or bot_switch_timer <= 0.0:
		_pick_next_action_bot()
		bot_switch_timer = randf_range(5.0, 8.0)

	if is_instance_valid(target_bot) and not target_bot.is_dead:
		target_center = target_center.lerp(target_bot.global_position + Vector3(0, 1.2, 0), delta * 2.5)
		current_angle += (base_speed * 0.5 * speed_mult) * delta
	else:
		target_center = target_center.lerp(orbit_center, delta * 2.5)
		current_angle += base_speed * speed_mult * delta

func _pick_next_action_bot() -> void:
	var bots := get_tree().get_nodes_in_group("menu_robots")
	var alive_bots: Array[MenuRobot] = []
	for b in bots:
		if b is MenuRobot and not b.is_dead:
			alive_bots.append(b)
	if alive_bots.size() > 0:
		target_bot = alive_bots.pick_random()

func _update_camera_transform(delta: float) -> void:
	var cam_pos := target_center + Vector3(
		sin(current_angle) * current_dist,
		current_height,
		cos(current_angle) * current_dist
	)
	global_position = global_position.lerp(cam_pos, clampf(delta * 12.0, 0.0, 1.0)) if delta < 0.5 else cam_pos
	look_at(target_center, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	# Мышь
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				is_dragging = true
				last_pointer_pos = mb.position
				user_interaction_timer = 4.0
			else:
				is_dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_dist = clampf(target_dist - 1.8, 10.0, 48.0)
			GameSettings.menu_camera_distance = target_dist
			user_interaction_timer = 4.0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_dist = clampf(target_dist + 1.8, 10.0, 48.0)
			GameSettings.menu_camera_distance = target_dist
			user_interaction_timer = 4.0

	elif event is InputEventMouseMotion and is_dragging:
		var mm := event as InputEventMouseMotion
		var rot_factor: float = 0.005
		current_angle -= mm.relative.x * rot_factor
		target_height = clampf(target_height + mm.relative.y * 0.04, 3.0, 28.0)
		GameSettings.menu_camera_height = target_height
		user_interaction_timer = 4.0

	# Сенсорный ввод на мобильных устройствах
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if drag_touch_index == -1:
				drag_touch_index = st.index
				last_pointer_pos = st.position
				user_interaction_timer = 4.0
		else:
			if st.index == drag_touch_index:
				drag_touch_index = -1

	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == drag_touch_index:
			current_angle -= sd.relative.x * 0.006
			target_height = clampf(target_height + sd.relative.y * 0.04, 3.0, 28.0)
			GameSettings.menu_camera_height = target_height
			user_interaction_timer = 4.0
