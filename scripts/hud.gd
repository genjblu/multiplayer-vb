extends CanvasLayer

@onready var health_bar: ProgressBar = %HealthBar if has_node("%HealthBar") else null
@onready var ammo_label: Label = %AmmoLabel if has_node("%AmmoLabel") else null
@onready var disconnect_label: Label = get_node("../DisconnectLabel") if has_node("../DisconnectLabel") else null
@onready var crosshair: Control = %Crosshair if has_node("%Crosshair") else null
@onready var touch_overlay: Control = $TouchOverlay if has_node("TouchOverlay") else null

var player: CharacterBody3D
var current_spread: float = 6.0
var hit_flash_timer: float = 0.0

var pause_menu: Control
var settings_menu: Control
var audio_slider: HSlider
var is_paused: bool = false
var ping_label: Label
var weapon_button: Button

func _ready() -> void:
	player = owner if owner is CharacterBody3D else get_parent()
	
	if not player or not player.is_multiplayer_authority():
		queue_free()
		return

	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal("ammo_changed"):
		player.ammo_changed.connect(_on_ammo_changed)
	if player.has_signal("hit_target"):
		player.hit_target.connect(_on_hit_target)
	if player.has_signal("weapon_changed"):
		player.weapon_changed.connect(_on_weapon_changed)

	var net_manager = get_node_or_null("/root/NetworkManager")
	if net_manager:
		net_manager.server_disconnected.connect(_on_server_disconnected_ui)

	_on_health_changed(player.health)
	_on_ammo_changed(player.current_ammo, player.reserve_ammo)

	# Показываем мобильный интерфейс
	if OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"] or ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse"):
		if has_node("TouchOverlay/JumpButton"): $TouchOverlay/JumpButton.show()
		if has_node("TouchOverlay/FireButton"): $TouchOverlay/FireButton.show()
		if has_node("TouchOverlay/JoystickBase"): $TouchOverlay/JoystickBase.show()
	else:
		if has_node("TouchOverlay/JumpButton"): $TouchOverlay/JumpButton.hide()
		if has_node("TouchOverlay/FireButton"): $TouchOverlay/FireButton.hide()
		if has_node("TouchOverlay/JoystickBase"): $TouchOverlay/JoystickBase.hide()

	_build_pause_menu()
	_build_hud_elements()

func _build_hud_elements() -> void:
	var hud_container = $TouchOverlay/HUDContainer if has_node("TouchOverlay/HUDContainer") else self
	var is_mobile = OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"] or ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse")

	# Ping label (Top Right) - visible on all platforms
	ping_label = Label.new()
	ping_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ping_label.offset_left = -200
	ping_label.offset_top = 20
	ping_label.offset_right = -20
	ping_label.offset_bottom = 50
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ping_label.text = "Пинг: 0 мс"
	ping_label.add_theme_color_override("font_color", Color(0, 1, 0, 1))
	ping_label.add_theme_font_size_override("font_size", 20)
	hud_container.add_child(ping_label)

	# Action buttons container (Right side, below ping) - MOBILE ONLY
	var btn_vbox = VBoxContainer.new()
	btn_vbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	btn_vbox.offset_left = -220
	btn_vbox.offset_top = 65
	btn_vbox.offset_right = -20
	btn_vbox.offset_bottom = 220
	btn_vbox.visible = is_mobile
	hud_container.add_child(btn_vbox)

	weapon_button = Button.new()
	weapon_button.text = "Оружие: Автомат"
	weapon_button.custom_minimum_size = Vector2(200, 42)
	weapon_button.pressed.connect(func():
		if player and player.has_method("cycle_weapon"):
			player.cycle_weapon()
	)
	btn_vbox.add_child(weapon_button)

	var btn_reload = Button.new()
	btn_reload.text = "Перезарядка"
	btn_reload.custom_minimum_size = Vector2(200, 42)
	btn_reload.pressed.connect(func():
		if player and player.has_method("reload"):
			player.reload()
	)
	btn_vbox.add_child(btn_reload)

	var btn_ads = Button.new()
	btn_ads.text = "Прицел"
	btn_ads.toggle_mode = true
	btn_ads.custom_minimum_size = Vector2(200, 42)
	btn_ads.toggled.connect(func(toggled):
		if player:
			player.touch_ads = toggled
	)
	btn_vbox.add_child(btn_ads)

	# Кнопка Меню (Пауза) для Android (не видна на ПК)
	var btn_menu = Button.new()
	btn_menu.text = "Меню / Пауза"
	btn_menu.custom_minimum_size = Vector2(200, 42)
	btn_menu.pressed.connect(func():
		_toggle_pause()
	)
	btn_vbox.add_child(btn_menu)

func _input(event: InputEvent) -> void:
	if not player or not player.is_multiplayer_authority():
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()

func _toggle_pause() -> void:
	is_paused = !is_paused
	if pause_menu:
		pause_menu.visible = is_paused
		pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP if is_paused else Control.MOUSE_FILTER_IGNORE
	if is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_tree().paused = false
		if settings_menu:
			settings_menu.hide()
			settings_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_pause_menu() -> void:
	pause_menu = Control.new()
	pause_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	pause_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_menu.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 200)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var btn_resume = Button.new()
	btn_resume.text = "Продолжить"
	btn_resume.pressed.connect(_toggle_pause)
	vbox.add_child(btn_resume)

	var btn_settings = Button.new()
	btn_settings.text = "Настройки"
	btn_settings.pressed.connect(func():
		if settings_menu:
			settings_menu.show()
			settings_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	)
	vbox.add_child(btn_settings)

	var btn_quit = Button.new()
	btn_quit.text = "Выход в меню"
	btn_quit.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vbox.add_child(btn_quit)

	add_child(pause_menu)
	_build_settings_menu()

func _build_settings_menu() -> void:
	settings_menu = Control.new()
	settings_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	settings_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_menu.visible = false
	settings_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.08, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_menu.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_menu.add_child(center)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450, 450)
	center.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 500)
	scroll.add_child(vbox)

	var title = Label.new()
	title.text = "НАСТРОЙКИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Audio section
	var lbl_audio = Label.new()
	lbl_audio.text = "Аудио (Громкость)"
	vbox.add_child(lbl_audio)

	audio_slider = HSlider.new()
	audio_slider.min_value = 0.0
	audio_slider.max_value = 1.0
	audio_slider.step = 0.05
	audio_slider.value = 1.0
	audio_slider.value_changed.connect(func(val):
		AudioServer.set_bus_volume_db(0, linear_to_db(val))
	)
	vbox.add_child(audio_slider)

	vbox.add_child(HSeparator.new())

	# Video & Advanced Graphics section
	var lbl_video = Label.new()
	lbl_video.text = "Видео и Продвинутая Графика"
	vbox.add_child(lbl_video)

	var chk_fullscreen = CheckBox.new()
	chk_fullscreen.text = "Полноэкранный режим"
	chk_fullscreen.button_pressed = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	chk_fullscreen.toggled.connect(func(pressed):
		if pressed:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	)
	vbox.add_child(chk_fullscreen)

	var chk_vsync = CheckBox.new()
	chk_vsync.text = "Вертикальная синхронизация (VSync)"
	chk_vsync.button_pressed = (DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)
	chk_vsync.toggled.connect(func(pressed):
		if pressed:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		else:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	)
	vbox.add_child(chk_vsync)

	# MSAA (Anti-aliasing)
	var lbl_msaa = Label.new()
	lbl_msaa.text = "Сглаживание (MSAA)"
	vbox.add_child(lbl_msaa)

	var option_msaa = OptionButton.new()
	option_msaa.add_item("Отключено", Viewport.MSAA_DISABLED)
	option_msaa.add_item("2x MSAA", Viewport.MSAA_2X)
	option_msaa.add_item("4x MSAA", Viewport.MSAA_4X)
	option_msaa.add_item("8x MSAA", Viewport.MSAA_8X)
	option_msaa.selected = get_viewport().msaa_3d
	option_msaa.item_selected.connect(func(index):
		get_viewport().msaa_3d = index
	)
	vbox.add_child(option_msaa)

	# Glow / Bloom
	var chk_glow = CheckBox.new()
	chk_glow.text = "Свечение (Bloom / Glow)"
	chk_glow.button_pressed = true
	chk_glow.toggled.connect(func(pressed):
		var env = get_viewport().get_camera_3d()
		if env and env.environment:
			env.environment.glow_enabled = pressed
	)
	vbox.add_child(chk_glow)

	# Resolution / Scaling Scale
	var lbl_scale = Label.new()
	lbl_scale.text = "Масштаб разрешения (Resolution Scale)"
	vbox.add_child(lbl_scale)

	var slider_scale = HSlider.new()
	slider_scale.min_value = 0.5
	slider_scale.max_value = 1.0
	slider_scale.step = 0.05
	slider_scale.value = get_viewport().scaling_3d_scale
	slider_scale.value_changed.connect(func(val):
		get_viewport().scaling_3d_scale = val
	)
	vbox.add_child(slider_scale)

	vbox.add_child(HSeparator.new())

	var btn_back = Button.new()
	btn_back.text = "Назад"
	btn_back.pressed.connect(func():
		settings_menu.hide()
		settings_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)
	vbox.add_child(btn_back)

	add_child(settings_menu)

func _process(delta: float) -> void:
	if not player:
		return

	# Update ping
	if ping_label:
		var ping_ms = 0
		var peer = multiplayer.multiplayer_peer
		if peer is ENetMultiplayerPeer:
			if multiplayer.is_server():
				ping_ms = 0
			else:
				var enet_peer = peer as ENetMultiplayerPeer
				if enet_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
					var p = enet_peer.get_peer(1)
					if p:
						ping_ms = int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		ping_label.text = "Пинг: %d мс" % ping_ms

	var target_spread = 6.0
	if player.get("is_ads"):
		target_spread = 2.0
	elif player.get("is_sprinting"):
		target_spread = 18.0
	elif player.velocity.length() > 0.1:
		target_spread = 12.0

	current_spread = lerp(current_spread, target_spread, delta * 12.0)
	if crosshair:
		crosshair.custom_minimum_size = Vector2(current_spread, current_spread)
		if hit_flash_timer > 0.0:
			hit_flash_timer -= delta
			crosshair.color = Color(1, 0, 0, 1)
		else:
			crosshair.color = Color(1, 1, 1, 0.8)

func _on_hit_target() -> void:
	hit_flash_timer = 0.15

func _on_health_changed(new_health: int) -> void:
	if health_bar:
		health_bar.value = new_health

func _on_ammo_changed(current: int, reserve: int) -> void:
	if ammo_label:
		ammo_label.text = "Патроны: %d / %d" % [current, reserve]

func _on_weapon_changed(weapon_name: String) -> void:
	if weapon_button:
		weapon_button.text = "Оружие: " + weapon_name

func _on_server_disconnected_ui() -> void:
	if disconnect_label:
		disconnect_label.show()
		await get_tree().create_timer(3.0).timeout
		disconnect_label.hide()
