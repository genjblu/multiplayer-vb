extends CanvasLayer

@onready var health_bar: ProgressBar = %HealthBar if has_node("%HealthBar") else null
@onready var ammo_label: Label = %AmmoLabel if has_node("%AmmoLabel") else null
@onready var disconnect_label: Label = get_node("../DisconnectLabel") if has_node("../DisconnectLabel") else null
@onready var crosshair: Control = %Crosshair if has_node("%Crosshair") else null
@onready var touch_overlay: Control = $TouchOverlay if has_node("TouchOverlay") else null
@onready var fps_label: Label = $TouchOverlay/HUDContainer/FPSLabel

var player: CharacterBody3D
var current_spread: float = 6.0
var hit_flash_timer: float = 0.0

var viewmodel: ViewmodelRenderer

var scoreboard: Scoreboard
var kill_feed: KillFeed

var pause_menu: Control
var settings_menu: Control
var audio_slider: HSlider
var is_paused: bool = false
var ping_label: Label
var weapon_button: Button

# --- Элементы настроек (поля класса, чтобы лямбды не работали с копиями) ---
var chk_fullscreen: CheckBox
var chk_vsync: CheckBox
var option_msaa: OptionButton
var chk_glow: CheckBox
var slider_scale: HSlider
var chk_fxaa: CheckBox
var chk_ssao: CheckBox
var chk_ssr: CheckBox
var chk_fps: CheckBox
var btn_potato: Button
var option_fps: OptionButton

# --- Режим картошки ---
var is_potato_mode: bool = false
var saved_settings: Dictionary = {}

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
	if _is_mobile():
		if has_node("TouchOverlay/JumpButton"): $TouchOverlay/JumpButton.show()
		if has_node("TouchOverlay/FireButton"): $TouchOverlay/FireButton.show()
		if has_node("TouchOverlay/JoystickBase"): $TouchOverlay/JoystickBase.show()
	else:
		if has_node("TouchOverlay/JumpButton"): $TouchOverlay/JumpButton.hide()
		if has_node("TouchOverlay/FireButton"): $TouchOverlay/FireButton.hide()
		if has_node("TouchOverlay/JoystickBase"): $TouchOverlay/JoystickBase.hide()

	_build_pause_menu()
	_build_hud_elements()

	scoreboard = Scoreboard.new()
	add_child(scoreboard)
	kill_feed = KillFeed.new()
	add_child(kill_feed)
	#if weapon_root_node:
		#viewmodel = ViewmodelRenderer.new()
		#add_child(viewmodel)
		#move_child(viewmodel, 0)  # рисовать под HUD
		#viewmodel.setup(weapon_root_node)
	#else:
		#push_warning("ViewmodelRenderer: узел оружия не найден, проверь путь")

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"] or ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse")

# Environment может лежать в WorldEnvironment, а не в камере
func _get_env() -> Environment:
	var cam = get_viewport().get_camera_3d()
	if cam and cam.environment:
		return cam.environment
	var we = get_tree().root.find_child("WorldEnvironment", true, false)
	if we is WorldEnvironment:
		return we.environment
	return null

func _build_hud_elements() -> void:
	var hud_container = $TouchOverlay/HUDContainer if has_node("TouchOverlay/HUDContainer") else self
	var is_mobile = _is_mobile()

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
	btn_menu.pressed.connect(_toggle_pause)
	btn_vbox.add_child(btn_menu)

	# Кнопка Таблица (закрепить скорборд)
	var btn_score = Button.new()
	btn_score.text = "Таблица"
	btn_score.toggle_mode = true
	btn_score.custom_minimum_size = Vector2(200, 42)
	btn_score.toggled.connect(func(pressed):
		if scoreboard:
			scoreboard.pinned = pressed
	)
	btn_vbox.add_child(btn_score)

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
		GameStats.reset_stats()
		get_tree().paused = false
		var net_manager = get_node_or_null("/root/NetworkManager")
		if net_manager:
			net_manager.disconnect_peer()
		else:
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

	chk_fullscreen = CheckBox.new()
	chk_fullscreen.text = "Полноэкранный режим"
	chk_fullscreen.button_pressed = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	chk_fullscreen.toggled.connect(func(pressed):
		if pressed:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	)
	vbox.add_child(chk_fullscreen)

	chk_vsync = CheckBox.new()
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

	option_msaa = OptionButton.new()
	option_msaa.add_item("Отключено", Viewport.MSAA_DISABLED)
	option_msaa.add_item("2x MSAA", Viewport.MSAA_2X)
	option_msaa.add_item("4x MSAA", Viewport.MSAA_4X)
	option_msaa.add_item("8x MSAA", Viewport.MSAA_8X)
	option_msaa.selected = option_msaa.get_item_index(get_viewport().msaa_3d)
	option_msaa.item_selected.connect(func(index):
		get_viewport().msaa_3d = option_msaa.get_item_id(index)
	)
	vbox.add_child(option_msaa)

	# Glow / Bloom
	chk_glow = CheckBox.new()
	chk_glow.text = "Свечение (Bloom / Glow)"
	var env_init = _get_env()
	chk_glow.button_pressed = env_init.glow_enabled if env_init else true
	chk_glow.toggled.connect(func(pressed):
		var env = _get_env()
		if env:
			env.glow_enabled = pressed
	)
	vbox.add_child(chk_glow)

	# Resolution Scale
	var lbl_scale = Label.new()
	lbl_scale.text = "Масштаб разрешения (Resolution Scale)"
	vbox.add_child(lbl_scale)

	slider_scale = HSlider.new()
	slider_scale.min_value = 0.35
	slider_scale.max_value = 1.0
	slider_scale.step = 0.05
	slider_scale.value = get_viewport().scaling_3d_scale
	slider_scale.value_changed.connect(func(val):
		get_viewport().scaling_3d_scale = val
	)
	vbox.add_child(slider_scale)

	# FXAA
	chk_fxaa = CheckBox.new()
	chk_fxaa.text = "FXAA сглаживание"
	chk_fxaa.button_pressed = (get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA)
	chk_fxaa.toggled.connect(func(pressed):
		if pressed:
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		else:
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	)
	vbox.add_child(chk_fxaa)

	# SSAO
	chk_ssao = CheckBox.new()
	chk_ssao.text = "Затенение окружения (SSAO)"
	chk_ssao.button_pressed = env_init.ssao_enabled if env_init else false
	chk_ssao.toggled.connect(func(pressed):
		var env = _get_env()
		if env:
			env.ssao_enabled = pressed
	)
	vbox.add_child(chk_ssao)

	# SSR
	chk_ssr = CheckBox.new()
	chk_ssr.text = "Отражения в пространстве экрана (SSR)"
	chk_ssr.button_pressed = env_init.ssr_enabled if env_init else false
	chk_ssr.toggled.connect(func(pressed):
		var env = _get_env()
		if env:
			env.ssr_enabled = pressed
	)
	vbox.add_child(chk_ssr)
	
	chk_fps = CheckBox.new()
	chk_fps.text = "Показать счётчик FPS"
	chk_fps.toggled.connect(func(pressed):
		if pressed:
			fps_label.visible = true
		else:
			fps_label.visible = false
	)
	vbox.add_child(chk_fps)
		
	if OS.has_feature("mobile"):
		chk_ssao.hide()
		chk_ssr.hide()
	
	# Potato Graphics Preset Toggle
	btn_potato = Button.new()
	btn_potato.text = "🥔 Режим Ультра-Картошка: Выкл"
	btn_potato.pressed.connect(_toggle_potato_mode)
	vbox.add_child(btn_potato)

	vbox.add_child(HSeparator.new())

	option_fps = OptionButton.new()
	option_fps.add_item("Без ограничений (0)", 0)
	option_fps.add_item("30 FPS", 30)
	option_fps.add_item("60 FPS", 60)
	option_fps.add_item("120 FPS", 120)
	option_fps.add_item("144 FPS", 144)
	_sync_fps_option()
	option_fps.item_selected.connect(func(index):
		Engine.max_fps = option_fps.get_item_id(index)
	)
	vbox.add_child(option_fps)

	vbox.add_child(HSeparator.new())

	var btn_back = Button.new()
	btn_back.text = "Назад"
	btn_back.pressed.connect(func():
		settings_menu.hide()
		settings_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)
	vbox.add_child(btn_back)

	add_child(settings_menu)

func _sync_fps_option() -> void:
	if not option_fps:
		return
	for i in range(option_fps.item_count):
		if option_fps.get_item_id(i) == Engine.max_fps:
			option_fps.selected = i
			return
	option_fps.selected = -1

# ---------------------------------------------------------------------------
# Режим Ультра-Картошка
# ---------------------------------------------------------------------------
func _toggle_potato_mode() -> void:
	is_potato_mode = !is_potato_mode
	var vp = get_viewport()
	var cam = vp.get_camera_3d()
	var env = _get_env()

	if is_potato_mode:
		# Запоминаем текущие настройки, чтобы вернуть именно их
		saved_settings = {
			"vsync": DisplayServer.window_get_vsync_mode(),
			"msaa": vp.msaa_3d,
			"aa": vp.screen_space_aa,
			"scale": vp.scaling_3d_scale,
			"fps": Engine.max_fps,
			"far": cam.far if cam else 4000.0,
		}
		if env:
			saved_settings["glow"] = env.glow_enabled
			saved_settings["ssao"] = env.ssao_enabled
			saved_settings["ssr"] = env.ssr_enabled
			saved_settings["vfog"] = env.volumetric_fog_enabled
			saved_settings["fog"] = env.fog_enabled
			saved_settings["sdfgi"] = env.sdfgi_enabled
			saved_settings["tonemap"] = env.tonemap_mode

		btn_potato.text = "🥔 Режим Ультра-Картошка: Вкл"

		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.scaling_3d_scale = 0.35
		Engine.max_fps = 60

		if cam:
			cam.far = 100.0
		if env:
			env.glow_enabled = false
			env.ssao_enabled = false
			env.ssr_enabled = false
			env.volumetric_fog_enabled = false
			env.fog_enabled = false
			env.sdfgi_enabled = false
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

		for node in get_tree().get_nodes_in_group("directional_lights"):
			if node is DirectionalLight3D:
				node.shadow_enabled = false

		print("Ultra-Potato mode ON | env=", env, " vsync=", DisplayServer.window_get_vsync_mode())
	else:
		btn_potato.text = "🥔 Режим Ультра-Картошка: Выкл"

		DisplayServer.window_set_vsync_mode(saved_settings.get("vsync", DisplayServer.VSYNC_ENABLED))
		vp.msaa_3d = saved_settings.get("msaa", Viewport.MSAA_2X)
		vp.screen_space_aa = saved_settings.get("aa", Viewport.SCREEN_SPACE_AA_FXAA)
		vp.scaling_3d_scale = saved_settings.get("scale", 1.0)
		Engine.max_fps = saved_settings.get("fps", 0)

		if cam:
			cam.far = saved_settings.get("far", 4000.0)
		if env and saved_settings.has("glow"):
			env.glow_enabled = saved_settings["glow"]
			env.ssao_enabled = saved_settings["ssao"]
			env.ssr_enabled = saved_settings["ssr"]
			env.volumetric_fog_enabled = saved_settings["vfog"]
			env.fog_enabled = saved_settings["fog"]
			env.sdfgi_enabled = saved_settings["sdfgi"]
			env.tonemap_mode = saved_settings["tonemap"]

		for node in get_tree().get_nodes_in_group("directional_lights"):
			if node is DirectionalLight3D:
				node.shadow_enabled = true

		print("Normal graphics mode restored")

	_sync_settings_ui()

# Приводит элементы интерфейса в соответствие с реальными настройками
func _sync_settings_ui() -> void:
	var vp = get_viewport()
	var env = _get_env()

	if chk_vsync:
		chk_vsync.set_pressed_no_signal(DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)
	if option_msaa:
		option_msaa.selected = option_msaa.get_item_index(vp.msaa_3d)
	if slider_scale:
		slider_scale.set_value_no_signal(vp.scaling_3d_scale)
	if chk_fxaa:
		chk_fxaa.set_pressed_no_signal(vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA)
	if env:
		if chk_glow: chk_glow.set_pressed_no_signal(env.glow_enabled)
		if chk_ssao: chk_ssao.set_pressed_no_signal(env.ssao_enabled)
		if chk_ssr: chk_ssr.set_pressed_no_signal(env.ssr_enabled)
	_sync_fps_option()

# ---------------------------------------------------------------------------

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
