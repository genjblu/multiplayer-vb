class_name HighwayArena
extends Node3D

const CombatCarClass = preload("res://scripts/combat_car.gd")
const VirtualSteeringWheelClass = preload("res://scripts/virtual_steering_wheel.gd")
const ChunkScript = preload("res://scripts/highway_chunk.gd")

@export var car_scene: PackedScene = preload("res://scenes/vehicles/combat_car.tscn")
@export var player_scene: PackedScene = preload("res://scenes/player.tscn")

var match_seed: int = 12345
var active_chunks: Dictionary = {} # index -> HighwayChunk
var current_leading_chunk: int = 0
var current_trailing_chunk: int = 0

# Машины и игроки
# peer_id -> CombatCar
var player_cars: Dictionary = {}
# team_id -> CombatCar
var team_cars: Dictionary = {}

var is_match_ended: bool = false
var victory_canvas: CanvasLayer = null

# UI транспорта
var vehicle_hud_layer: CanvasLayer = null
var hud_speed_label: Label = null
var hud_hp_bar: ProgressBar = null
var hud_nitro_bar: ProgressBar = null
const PauseMenuClass = preload("res://scripts/pause_menu.gd")

var local_car: VehicleBody3D = null

# Мобильные элементы управления и HUD
var mobile_wheel: Control = null
var gas_btn: TextureButton = null
var brake_btn: TextureButton = null
var cam_btn: TextureButton = null
var fire_btn: TextureButton = null
var hud_dash_panel: Control = null
var pause_menu = null

func _ready() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		match_seed = randi()
		_sync_match_seed.rpc(match_seed)

	# Инициализация первых чанков шоссе (от -1 до 4)
	for i in range(-1, 5):
		_spawn_chunk(i)

	current_leading_chunk = 4
	current_trailing_chunk = -1

	# Сетевые слушатели
	var net_mgr = get_node_or_null("/root/NetworkManager")
	if net_mgr:
		net_mgr.player_disconnected.connect(_on_player_disconnected)

	# Создаем HUD до спавна участников, чтобы элементы управления уже существовали
	_build_vehicle_hud()

	var has_peer := multiplayer.has_multiplayer_peer()
	var is_server := has_peer and multiplayer.is_server()

	if not has_peer:
		_spawn_solo_game()
	elif is_server:
		_notify_ready_to_server()
	else:
		_notify_ready_to_server.rpc_id(1)

@rpc("authority", "call_local", "reliable")
func _sync_match_seed(s: int) -> void:
	match_seed = s

@rpc("any_peer", "call_local", "reliable")
func _notify_ready_to_server() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()

	_spawn_combat_participant(peer_id)

func _spawn_solo_game() -> void:
	# Спавним солдата для корректной работы оружия и вида
	var p_node := player_scene.instantiate()
	p_node.name = "1"
	add_child(p_node)

	# Одиночный тестовый заезд
	var car := car_scene.instantiate() as CombatCarClass
	car.name = "Car_1"
	car.position = Vector3(0, 1.2, 0)
	add_child(car)
	car.driver_peer_id = 1
	player_cars[1] = car
	local_car = car

	car.assign_player_to_seat(1, 0, p_node)
	_attach_local_hud(car)

func _spawn_combat_participant(peer_id: int) -> void:
	var net_manager = get_node_or_null("/root/NetworkManager")
	var mode: String = net_manager.current_mode if net_manager else "ffa"
	var stats = get_node_or_null("/root/GameStats")
	var team_id: int = stats.get_player_team(peer_id) if stats else 0
	var col: Color = stats.get_player_color(peer_id) if stats else Color(0.95, 0.45, 0.1)

	# 1. Спавним игрока (солдата)
	var p_node: Node3D = null
	if not has_node(str(peer_id)):
		p_node = player_scene.instantiate()
		p_node.name = str(peer_id)
		p_node.set_multiplayer_authority(peer_id)
		add_child(p_node, true)
	else:
		p_node = get_node(str(peer_id)) as Node3D

	# 2. Определяем машину для игрока
	var car: CombatCarClass = null

	if mode == "ffa" or mode == "highway_fury":
		# Каждый игрок получает свою отдельную боевую машину
		if not player_cars.has(peer_id):
			car = car_scene.instantiate() as CombatCarClass
			var slot_idx: int = player_cars.size()
			var lane_x: float = [-6.0, 0.0, 6.0][slot_idx % 3]
			var start_z: float = -float(slot_idx / 3) * 12.0
			car.name = "Car_%d" % peer_id
			car.position = Vector3(lane_x, 1.2, start_z)
			car.car_color = col
			car.driver_peer_id = peer_id
			add_child(car, true)
			car.set_multiplayer_authority(peer_id)
			player_cars[peer_id] = car
		else:
			car = player_cars[peer_id]

		car.assign_player_to_seat(peer_id, 0, p_node)

	else:
		# Командный режим: одна машина на команду
		if not team_cars.has(team_id):
			car = car_scene.instantiate() as CombatCarClass
			var team_slot: int = team_id - 1
			var lane_x: float = -5.0 + float(team_slot) * 10.0
			car.name = "TeamCar_%d" % team_id
			car.position = Vector3(lane_x, 1.2, 0)
			car.team_id = team_id
			car.car_color = col
			add_child(car, true)
			team_cars[team_id] = car
		else:
			car = team_cars[team_id]

		# Находим свободное место в машине (0 = водитель, 1..3 = стрелки)
		var seat_idx: int = -1
		for s in range(4):
			if car.passengers[s] == 0:
				seat_idx = s
				break
		if seat_idx == -1:
			seat_idx = 1 # запасной

		car.assign_player_to_seat(peer_id, seat_idx, p_node)
		player_cars[peer_id] = car

	# Рассылаем клиентам данные о новой машине и распределении мест
	_sync_vehicle_data.rpc(car.name, car.position, car.driver_peer_id, car.passengers, car.car_color)

@rpc("authority", "call_local", "reliable")
func _sync_vehicle_data(car_name: String, pos: Vector3, driver_id: int, seat_passengers: Array, c_col: Color) -> void:
	var car := get_node_or_null(car_name) as CombatCarClass
	if not car:
		car = car_scene.instantiate() as CombatCarClass
		car.name = car_name
		car.position = pos
		add_child(car)

	car.car_color = c_col
	car.driver_peer_id = driver_id
	car.set_multiplayer_authority(driver_id)
	car._update_car_color()

	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

	for s_idx in range(seat_passengers.size()):
		var pid: int = int(seat_passengers[s_idx])
		if pid > 0:
			car.passengers[s_idx] = pid
			var p_node := get_node_or_null(str(pid)) as Node3D
			if p_node:
				car.assign_player_to_seat(pid, s_idx, p_node)

			if pid == my_id:
				local_car = car
				_attach_local_hud(car)

func _physics_process(delta: float) -> void:
	_check_procedural_highway()
	_check_fall_off()
	if is_inside_tree() and multiplayer and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not is_match_ended:
		_check_battle_royale_win()

func _check_procedural_highway() -> void:
	# Ищем самую дальнюю машину впереди (наименьший Z, так как едем в -Z)
	var min_z: float = 0.0
	var max_z: float = 0.0
	var found_any := false

	for child in get_children():
		if child is CombatCarClass and not child.is_destroyed:
			var z_val: float = (child as Node3D).global_position.z
			if not found_any or z_val < min_z:
				min_z = z_val
			if not found_any or z_val > max_z:
				max_z = z_val
			found_any = true

	if not found_any:
		return

	# Номер самого переднего чанка
	var target_lead_chunk: int = int(absf(min_z) / ChunkScript.CHUNK_LENGTH) + 3
	while current_leading_chunk < target_lead_chunk:
		current_leading_chunk += 1
		_spawn_chunk(current_leading_chunk)

	# Очистка чанков позади замыкающей машины (> 150м позади)
	var target_trail_chunk: int = int(absf(max_z) / ChunkScript.CHUNK_LENGTH) - 2
	if target_trail_chunk > current_trailing_chunk:
		for i in range(current_trailing_chunk, target_trail_chunk):
			_despawn_chunk(i)
		current_trailing_chunk = target_trail_chunk

func _spawn_chunk(idx: int) -> void:
	if active_chunks.has(idx):
		return
	var chunk := ChunkScript.new()
	chunk.name = "Chunk_%d" % idx
	add_child(chunk)
	chunk.setup_chunk(idx, match_seed)
	active_chunks[idx] = chunk

func _despawn_chunk(idx: int) -> void:
	if active_chunks.has(idx):
		var chunk: Node = active_chunks[idx]
		active_chunks.erase(idx)
		if is_instance_valid(chunk):
			chunk.queue_free()

func _check_fall_off() -> void:
	for child in get_children():
		if child is CombatCarClass and not child.is_destroyed:
			if child.global_position.y < -15.0:
				child.destroy_car(0, "Пропасть")
		elif child is CharacterBody3D and child.name.is_valid_int():
			if child.global_position.y < -15.0 and child.has_method("die"):
				child.die()

func _check_battle_royale_win() -> void:
	var total_cars := 0
	var alive_cars: Array[CombatCarClass] = []

	for child in get_children():
		if child is CombatCarClass:
			total_cars += 1
			if not child.is_destroyed:
				alive_cars.append(child)

	if total_cars < 2:
		return # Ждем хотя бы 2 участников для победы

	if alive_cars.size() == 1:
		is_match_ended = true
		var winner_car: CombatCarClass = alive_cars[0]
		var winner_name := "Победитель"
		var stats = get_node_or_null("/root/GameStats")
		if stats and stats.players.has(winner_car.driver_peer_id):
			winner_name = stats.players[winner_car.driver_peer_id]["name"]
		_announce_victory.rpc(winner_name, winner_car.car_color)

@rpc("authority", "call_local", "reliable")
func _announce_victory(winner_name: String, col: Color) -> void:
	if victory_canvas and is_instance_valid(victory_canvas):
		return

	victory_canvas = CanvasLayer.new()
	victory_canvas.layer = 120
	add_child(victory_canvas)

	var panel := PanelContainer.new()
	panel.theme = UITheme.build()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(480, 200)
	panel.offset_left = -240
	panel.offset_top = -100
	panel.offset_right = 240
	panel.offset_bottom = 100
	victory_canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "🏆 ПОБЕДА! 🏆"
	title.theme_type_variation = "HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(1.0, 0.85, 0.1)
	vbox.add_child(title)

	var winner_lbl := Label.new()
	winner_lbl.text = winner_name + " выжил на Дороге Ярости!"
	winner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_lbl.modulate = col
	vbox.add_child(winner_lbl)

	# Таймер возврата в меню
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_callback(func():
		var net_disconnect = get_node_or_null("/root/NetworkManager")
		if net_disconnect:
			net_disconnect.disconnect_peer()
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)

func _build_vehicle_hud() -> void:
	vehicle_hud_layer = CanvasLayer.new()
	vehicle_hud_layer.layer = 90
	add_child(vehicle_hud_layer)

	var root := Control.new()
	root.name = "VehicleHUD"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vehicle_hud_layer.add_child(root)

	# 1. Приборная панель (Спидометр + ХП + Нитро) по центру снизу
	var dash_panel := PanelContainer.new()
	dash_panel.theme = UITheme.build()
	dash_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dash_panel.offset_left = -160
	dash_panel.offset_top = -115
	dash_panel.offset_right = 160
	dash_panel.offset_bottom = -15
	dash_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dash_panel)

	var dash_vbox := VBoxContainer.new()
	dash_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dash_vbox.add_theme_constant_override("separation", 4)
	dash_panel.add_child(dash_vbox)

	hud_speed_label = Label.new()
	hud_speed_label.text = "0 KM/H"
	hud_speed_label.theme_type_variation = "HeadingLabel"
	hud_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_speed_label.modulate = Color(0.2, 0.85, 1.0)
	dash_vbox.add_child(hud_speed_label)

	# HP бар машины
	var hp_row := HBoxContainer.new()
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dash_vbox.add_child(hp_row)
	var hp_icon := Label.new()
	hp_icon.text = "🚗 HP:"
	hp_row.add_child(hp_icon)

	hud_hp_bar = ProgressBar.new()
	hud_hp_bar.min_value = 0
	hud_hp_bar.max_value = 400
	hud_hp_bar.value = 400
	hud_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_hp_bar.custom_minimum_size = Vector2(0, 16)
	hud_hp_bar.show_percentage = false
	var style_hp := StyleBoxFlat.new()
	style_hp.bg_color = Color(0.15, 0.85, 0.25)
	style_hp.set_corner_radius_all(4)
	hud_hp_bar.add_theme_stylebox_override("fill", style_hp)
	hp_row.add_child(hud_hp_bar)

	# Nitro бар
	var nitro_row := HBoxContainer.new()
	nitro_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dash_vbox.add_child(nitro_row)
	var nitro_icon := Label.new()
	nitro_icon.text = "⚡ БУСТ:"
	nitro_row.add_child(nitro_icon)

	hud_nitro_bar = ProgressBar.new()
	hud_nitro_bar.min_value = 0
	hud_nitro_bar.max_value = 100
	hud_nitro_bar.value = 100
	hud_nitro_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_nitro_bar.custom_minimum_size = Vector2(0, 14)
	hud_nitro_bar.show_percentage = false
	var style_nitro := StyleBoxFlat.new()
	style_nitro.bg_color = Color(0.1, 0.75, 1.0)
	style_nitro.set_corner_radius_all(4)
	hud_nitro_bar.add_theme_stylebox_override("fill", style_nitro)
	nitro_row.add_child(hud_nitro_bar)

	hud_dash_panel = dash_panel

	# 2. Мобильные сенсорные кнопки (только для мобильных ОС Android/iOS)
	var is_mobile := (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or OS.get_name() in ["Android", "iOS"]) and not (OS.get_name() in ["Windows", "Linux", "macOS"])
	if is_mobile:
		_build_mobile_driving_controls(root)

		# Кнопка меню (паузы) в верхнем левом углу ТОЛЬКО на мобильных устройствах
		var pause_btn := Button.new()
		pause_btn.name = "PauseButton"
		pause_btn.text = "⏸ Меню"
		pause_btn.theme = UITheme.build()
		pause_btn.custom_minimum_size = Vector2(105, 42)
		pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		pause_btn.offset_left = 20
		pause_btn.offset_top = 20
		pause_btn.offset_right = 125
		pause_btn.offset_bottom = 62
		pause_btn.pressed.connect(func(): if pause_menu: pause_menu.toggle_pause())
		root.add_child(pause_btn)

		# Переключатель вида камеры в верхнем правом углу ТОЛЬКО на мобильных устройствах
		cam_btn = TextureButton.new()
		cam_btn.name = "CamToggleBtn"
		cam_btn.texture_normal = load("res://gui/cam_toggle.svg")
		cam_btn.ignore_texture_size = true
		cam_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		cam_btn.custom_minimum_size = Vector2(50, 50)
		cam_btn.size = Vector2(50, 50)
		cam_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		cam_btn.offset_left = -70
		cam_btn.offset_top = 20
		cam_btn.offset_right = -20
		cam_btn.offset_bottom = 70
		cam_btn.pressed.connect(func(): if local_car: local_car.toggle_camera_mode())
		root.add_child(cam_btn)

	# Универсальное меню паузы и настроек
	pause_menu = PauseMenuClass.new()
	add_child(pause_menu)
	pause_menu.add_action_button("📷 Сменить вид камеры (C / V)", func():
		if local_car:
			local_car.toggle_camera_mode()
	)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C or event.keycode == KEY_V:
			if local_car:
				local_car.toggle_camera_mode()
				get_viewport().set_input_as_handled()

func _setup_mobile_steering(root: Control) -> void:
	var use_buttons: bool = (GameSettings.vehicle_touch_steering == 1)
	if not use_buttons:
		mobile_wheel = VirtualSteeringWheelClass.new()
		mobile_wheel.name = "VirtualWheel"
		mobile_wheel.custom_minimum_size = Vector2(190, 190)
		mobile_wheel.size = Vector2(190, 190)
		mobile_wheel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		mobile_wheel.offset_left = 35
		mobile_wheel.offset_top = -225
		mobile_wheel.offset_right = 225
		mobile_wheel.offset_bottom = -35
		root.add_child(mobile_wheel)

		var wheel_tex := TextureRect.new()
		wheel_tex.name = "WheelVisual"
		wheel_tex.texture = load("res://gui/steering_wheel.svg")
		wheel_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wheel_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		wheel_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wheel_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mobile_wheel.add_child(wheel_tex)
		mobile_wheel.wheel_node = wheel_tex
		if local_car:
			mobile_wheel.vehicle_target = local_car
	else:
		var btn_left := Button.new()
		btn_left.name = "BtnLeft"
		btn_left.text = "◀"
		btn_left.add_theme_font_size_override("font_size", 28)
		btn_left.custom_minimum_size = Vector2(85, 85)
		btn_left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		btn_left.offset_left = 30
		btn_left.offset_top = -135
		btn_left.offset_right = 115
		btn_left.offset_bottom = -50
		btn_left.button_down.connect(func(): if local_car: local_car.touch_steering = -1.0)
		btn_left.button_up.connect(func(): if local_car: local_car.touch_steering = 0.0)
		root.add_child(btn_left)

		var btn_right := Button.new()
		btn_right.name = "BtnRight"
		btn_right.text = "▶"
		btn_right.add_theme_font_size_override("font_size", 28)
		btn_right.custom_minimum_size = Vector2(85, 85)
		btn_right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		btn_right.offset_left = 135
		btn_right.offset_top = -135
		btn_right.offset_right = 220
		btn_right.offset_bottom = -50
		btn_right.button_down.connect(func(): if local_car: local_car.touch_steering = 1.0)
		btn_right.button_up.connect(func(): if local_car: local_car.touch_steering = 0.0)
		root.add_child(btn_right)

func _build_mobile_driving_controls(root: Control) -> void:
	# 1. Поворот (руль или кнопки) слева
	_setup_mobile_steering(root)

	# 2. Педаль газа (справа внизу)
	gas_btn = _create_touch_pedal("res://gui/gas_pedal.svg", Vector2(-115, -175), Vector2(85, 140), root)
	gas_btn.button_down.connect(func(): if local_car: local_car.touch_gas = 1.0)
	gas_btn.button_up.connect(func(): if local_car: local_car.touch_gas = 0.0)

	# 3. Педаль тормоза / заднего хода (левее газа)
	brake_btn = _create_touch_pedal("res://gui/brake_pedal.svg", Vector2(-225, -160), Vector2(95, 110), root)
	brake_btn.button_down.connect(func(): if local_car: local_car.touch_brake = 1.0)
	brake_btn.button_up.connect(func(): if local_car: local_car.touch_brake = 0.0)

	# 4. Кнопка стрельбы из автопушек (над газом)
	fire_btn = _create_touch_pedal("res://gui/shoot.svg", Vector2(-115, -285), Vector2(85, 85), root)
	fire_btn.button_down.connect(func():
		if local_car: local_car.touch_fire_active = true
	)
	fire_btn.button_up.connect(func():
		if local_car: local_car.touch_fire_active = false
	)

	# 5. Кнопка нитро-ускорения (Буст, над тормозом)
	var nitro_btn = _create_touch_pedal("res://gui/gas_pedal.svg", Vector2(-215, -270), Vector2(75, 75), root)
	nitro_btn.modulate = Color(0.2, 0.85, 1.0)
	var nitro_lbl := Label.new()
	nitro_lbl.text = "⚡"
	nitro_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nitro_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nitro_lbl.add_theme_font_size_override("font_size", 28)
	nitro_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nitro_btn.add_child(nitro_lbl)
	nitro_btn.button_down.connect(func():
		if local_car: local_car.touch_nitro = true
	)
	nitro_btn.button_up.connect(func():
		if local_car: local_car.touch_nitro = false
	)

func _create_touch_pedal(icon_path: String, offset_from_br: Vector2, btn_size: Vector2, parent: Control) -> TextureButton:
	var btn := TextureButton.new()
	btn.texture_normal = load(icon_path)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = btn_size
	btn.size = btn_size
	btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.offset_left = offset_from_br.x
	btn.offset_top = offset_from_br.y
	btn.offset_right = offset_from_br.x + btn_size.x
	btn.offset_bottom = offset_from_br.y + btn_size.y
	parent.add_child(btn)
	return btn

func _attach_local_hud(car: CombatCarClass) -> void:
	if not car:
		return
	if mobile_wheel:
		mobile_wheel.vehicle_target = car

	# Скрываем сенсорный оверлей пешего игрока
	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var p_node := get_node_or_null(str(my_id))
	if p_node:
		var p_touch = p_node.get_node_or_null("%TouchUI")
		if p_touch:
			p_touch.visible = false

	car.health_changed.connect(func(cur: int, max_val: int):
		if hud_hp_bar:
			hud_hp_bar.value = cur
	)
	car.nitro_changed.connect(func(cur: float, max_val: float):
		if hud_nitro_bar:
			hud_nitro_bar.value = cur
	)

func _process(delta: float) -> void:
	if local_car and is_instance_valid(local_car):
		if hud_speed_label:
			var spd_kmh := int(local_car.linear_velocity.length() * 3.6)
			hud_speed_label.text = "%d KM/H" % spd_kmh
		if hud_dash_panel:
			# В виде от первого лица (кокпит) скрываем 2D панель, чтобы не загораживать руль и 3D приборы
			hud_dash_panel.visible = (local_car.camera_mode == 0)

func _on_player_disconnected(peer_id: int) -> void:
	var p = get_node_or_null(str(peer_id))
	if p:
		p.queue_free()
	if player_cars.has(peer_id):
		var car: CombatCarClass = player_cars[peer_id]
		player_cars.erase(peer_id)
		if is_instance_valid(car):
			car.remove_player(peer_id)
