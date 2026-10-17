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
var crosshair_view: CrosshairView

var viewmodel: ViewmodelRenderer

var scoreboard: Scoreboard
var kill_feed: KillFeed

var pause_menu: Control
var settings_menu: Control
var audio_slider: HSlider
var is_paused: bool = false
var debug_label: Label
var weapon_button: Button

# Переменные для сбора статистики FPS
var _fps_samples: Array[float] = []
var _fps_timer: float = 0.0
var _min_fps: int = 999
var _max_fps: int = 0
var _avg_fps: int = 0

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
var option_aspect: OptionButton
var option_res: OptionButton
var current_res_list: Array[Vector2i] = []

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
	if crosshair:
		crosshair.visible = false
	crosshair_view = CrosshairView.new()
	crosshair_view.player = player
	add_child(crosshair_view)
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

	# Debug-панель (Top Right): FPS, Avg, Min/Max, Ping, Loss
	debug_label = Label.new()
	debug_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	debug_label.offset_left = -260
	debug_label.offset_top = 10
	debug_label.offset_right = -15
	debug_label.offset_bottom = 120
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.text = "DEBUG INFO"
	debug_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 0.9))
	debug_label.add_theme_font_size_override("font_size", 14)
	hud_container.add_child(debug_label)
	debug_label.visible = false

	# Мобильные кнопки опущены ниже, чтобы не мешать Debug-панели (offset_top = 135)
	var btn_vbox = VBoxContainer.new()
	btn_vbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	btn_vbox.offset_left = -220
	btn_vbox.offset_top = 135
	btn_vbox.offset_right = -20
	btn_vbox.offset_bottom = 350
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
	if crosshair_view:
		crosshair_view.visible = not is_paused
	if crosshair:
		crosshair.visible = false
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
		LanDiscovery.stop_broadcast()
		BulletDecals.clear_all()
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

	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(520, 520)
	center.add_child(main_vbox)

	var title = Label.new()
	title.text = "НАСТРОЙКИ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	main_vbox.add_child(title)

	var tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(500, 420)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tabs)

	# --- ВКЛАДКА 1: УПРАВЛЕНИЕ ---
	var scroll_input = ScrollContainer.new()
	scroll_input.name = "Управление"
	tabs.add_child(scroll_input)

	var vbox_input = VBoxContainer.new()
	vbox_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_input.add_child(vbox_input)

	var lbl_sens = Label.new()
	lbl_sens.text = "Чувствительность мыши"
	vbox_input.add_child(lbl_sens)

	var sens_slider = HSlider.new()
	sens_slider.min_value = 0.0005
	sens_slider.max_value = 0.01
	sens_slider.step = 0.0002
	sens_slider.value = player.mouse_sensitivity if player else 0.003
	sens_slider.value_changed.connect(func(val):
		if player: player.mouse_sensitivity = val
	)
	vbox_input.add_child(sens_slider)

	var lbl_ads_sens = Label.new()
	lbl_ads_sens.text = "Множитель чувствительности в прицеле (ADS)"
	vbox_input.add_child(lbl_ads_sens)

	var ads_slider = HSlider.new()
	ads_slider.min_value = 0.1
	ads_slider.max_value = 1.5
	ads_slider.step = 0.05
	ads_slider.value = player.ads_mouse_multiplier if player and "ads_mouse_multiplier" in player else 0.6
	ads_slider.value_changed.connect(func(val):
		if player and "ads_mouse_multiplier" in player:
			player.ads_mouse_multiplier = val
	)
	vbox_input.add_child(ads_slider)

	vbox_input.add_child(HSeparator.new())
	var lbl_rebind = Label.new()
	lbl_rebind.text = "Переназначение клавиш (нажми кнопку, затем нужную клавишу):"
	vbox_input.add_child(lbl_rebind)

	var rebind_actions = [
		{"action": "move_forward", "label": "Вперёд"},
		{"action": "move_back", "label": "Назад"},
		{"action": "move_left", "label": "Влево"},
		{"action": "move_right", "label": "Вправо"},
		{"action": "ui_accept", "label": "Прыжок"},
		{"action": "crouch", "label": "Приседание"},
		{"action": "sprint", "label": "Спринт"},
		{"action": "reload", "label": "Перезарядка"},
		{"action": "fire", "label": "Огонь"},
		{"action": "ads", "label": "Прицел"}
	]

	for item in rebind_actions:
		var act_name = item["action"]
		var row = HBoxContainer.new()
		var action_label = Label.new()
		action_label.text = item["label"]
		action_label.custom_minimum_size = Vector2(180, 0)
		row.add_child(action_label)

		var btn_key = Button.new()
		btn_key.custom_minimum_size = Vector2(160, 32)
		btn_key.text = _get_action_key_name(act_name)
		btn_key.pressed.connect(_start_key_rebind.bind(act_name, btn_key))
		row.add_child(btn_key)
		vbox_input.add_child(row)

	# --- ВКЛАДКА 2: ГРАФИКА ---
	var scroll_video = ScrollContainer.new()
	scroll_video.name = "Графика"
	tabs.add_child(scroll_video)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_video.add_child(vbox)

	chk_fullscreen = CheckBox.new()
	chk_fullscreen.text = "Полноэкранный режим"
	chk_fullscreen.button_pressed = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	chk_fullscreen.toggled.connect(func(pressed):
		if pressed:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if option_res and option_res.selected >= 0 and option_res.selected < current_res_list.size():
			_apply_game_resolution(current_res_list[option_res.selected])
	)
	vbox.add_child(chk_fullscreen)

	# Выбор соотношения сторон
	var lbl_aspect = Label.new()
	lbl_aspect.text = "Соотношение сторон:"
	vbox.add_child(lbl_aspect)

	option_aspect = OptionButton.new()
	option_aspect.add_item("Автоматически (По экрану)", 0)
	option_aspect.add_item("16:9 (Широкоэкранный)", 1)
	option_aspect.add_item("16:10", 2)
	option_aspect.add_item("4:3 (Вплоть до 640x480)", 3)
	option_aspect.add_item("21:9 (Ультраширокий)", 4)
	vbox.add_child(option_aspect)

	# Выбор разрешения экрана
	var lbl_res = Label.new()
	lbl_res.text = "Разрешение экрана:"
	vbox.add_child(lbl_res)

	option_res = OptionButton.new()
	vbox.add_child(option_res)

	option_aspect.item_selected.connect(func(idx):
		_populate_resolutions(idx)
	)
	option_res.item_selected.connect(func(idx):
		if idx >= 0 and idx < current_res_list.size():
			_apply_game_resolution(current_res_list[idx])
	)

	_populate_resolutions(0)

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

	chk_ssao = CheckBox.new()
	chk_ssao.text = "Затенение окружения (SSAO)"
	chk_ssao.button_pressed = env_init.ssao_enabled if env_init else false
	chk_ssao.toggled.connect(func(pressed):
		var env = _get_env()
		if env:
			env.ssao_enabled = pressed
	)
	vbox.add_child(chk_ssao)

	chk_ssr = CheckBox.new()
	chk_ssr.text = "Отражения в пространстве экрана (SSR)"
	chk_ssr.button_pressed = env_init.ssr_enabled if env_init else false
	chk_ssr.toggled.connect(func(pressed):
		var env = _get_env()
		if env:
			env.ssr_enabled = pressed
	)
	vbox.add_child(chk_ssr)

	if OS.has_feature("mobile"):
		chk_ssao.hide()
		chk_ssr.hide()

	btn_potato = Button.new()
	btn_potato.text = "🥔 Режим Ультра-Картошка: Выкл"
	btn_potato.pressed.connect(_toggle_potato_mode)
	vbox.add_child(btn_potato)

	var lbl_limit_fps = Label.new()
	lbl_limit_fps.text = "Лимит кадров (FPS Limit):"
	vbox.add_child(lbl_limit_fps)

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

	# --- ВКЛАДКА 3: АУДИО ---
	var scroll_audio = ScrollContainer.new()
	scroll_audio.name = "Аудио"
	tabs.add_child(scroll_audio)

	var vbox_audio = VBoxContainer.new()
	vbox_audio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_audio.add_child(vbox_audio)

	var lbl_audio = Label.new()
	lbl_audio.text = "Общая громкость:"
	vbox_audio.add_child(lbl_audio)

	audio_slider = HSlider.new()
	audio_slider.min_value = 0.0
	audio_slider.max_value = 1.0
	audio_slider.step = 0.05
	audio_slider.value = 1.0
	audio_slider.value_changed.connect(func(val):
		AudioServer.set_bus_volume_db(0, linear_to_db(val))
	)
	vbox_audio.add_child(audio_slider)

	main_vbox.add_child(HSeparator.new())

	var btn_back = Button.new()
	btn_back.text = "Назад"
	btn_back.custom_minimum_size = Vector2(0, 36)
	btn_back.pressed.connect(func():
		settings_menu.hide()
		settings_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)
	main_vbox.add_child(btn_back)
	
	# --- ВКЛАДКА 4: РАСШИРЕНИЯ ---
	var scroll_ext = ScrollContainer.new()
	scroll_ext.name = "Расширения"
	tabs.add_child(scroll_ext)

	var vbox_ext = VBoxContainer.new()
	vbox_ext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_ext.add_child(vbox_ext)

	var chk_debug = CheckBox.new()
	chk_debug.text = "Панель отладки (Debug Info: FPS, Ping, Loss)"
	chk_debug.button_pressed = debug_label.visible if debug_label else false
	chk_debug.toggled.connect(func(pressed):
		if debug_label:
			debug_label.visible = pressed
	)
	vbox_ext.add_child(chk_debug)

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

	# Обновление FPS и сети в Debug панели
	_fps_timer += delta
	var current_fps_val = Engine.get_frames_per_second()
	_fps_samples.append(float(current_fps_val))

	if _fps_timer >= 0.5:
		_fps_timer = 0.0
		if not _fps_samples.is_empty():
			var sum_fps: float = 0.0
			_min_fps = 9999
			_max_fps = 0
			for val in _fps_samples:
				sum_fps += val
				if val < _min_fps: _min_fps = int(val)
				if val > _max_fps: _max_fps = int(val)
			_avg_fps = int(sum_fps / _fps_samples.size())
			_fps_samples.clear()

	if debug_label:
		var ping_ms = 0
		var packet_loss_pct = 0.0
		var peer = multiplayer.multiplayer_peer
		if peer is ENetMultiplayerPeer:
			if multiplayer.is_server():
				ping_ms = 0
				packet_loss_pct = 0.0
			else:
				var enet_peer = peer as ENetMultiplayerPeer
				if enet_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
					var p = enet_peer.get_peer(1)
					if p:
						ping_ms = int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
						# В ENet статистика PEER_PACKET_LOSS нормализуется шкалой от 0 до 65536
						var raw_loss = p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)
						packet_loss_pct = clampf((float(raw_loss) / 65536.0) * 100.0, 0.0, 100.0)

		var min_display = _min_fps if _min_fps != 9999 else current_fps_val
		debug_label.text = "FPS: %d (Avg: %d | Min: %d | Max: %d)\nPing: %d ms | Loss: %.1f%%" % [
			current_fps_val, _avg_fps, min_display, _max_fps, ping_ms, packet_loss_pct
		]

	var target_spread = 6.0
	if player.get("is_ads"):
		target_spread = 2.0
	elif player.get("is_sprinting"):
		target_spread = 18.0
	elif player.velocity.length() > 0.1:
		target_spread = 12.0

	current_spread = lerp(current_spread, target_spread, delta * 12.0)
	if crosshair_view:
		crosshair_view.hit_amount = clampf(hit_flash_timer / 0.15, 0.0, 1.0)
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

func _populate_resolutions(aspect_mode: int) -> void:
	if not option_res:
		return
	option_res.clear()
	current_res_list.clear()

	var presets = {
		1: [ # 16:9
			Vector2i(2560, 1440), Vector2i(1920, 1080), Vector2i(1600, 900),
			Vector2i(1366, 768), Vector2i(1280, 720), Vector2i(960, 540), Vector2i(640, 360)
		],
		2: [ # 16:10
			Vector2i(1920, 1200), Vector2i(1680, 1050), Vector2i(1440, 900),
			Vector2i(1280, 800), Vector2i(960, 600), Vector2i(640, 400)
		],
		3: [ # 4:3
			Vector2i(1600, 1200), Vector2i(1400, 1050), Vector2i(1280, 960),
			Vector2i(1024, 768), Vector2i(800, 600), Vector2i(640, 480)
		],
		4: [ # 21:9
			Vector2i(3440, 1440), Vector2i(2560, 1080), Vector2i(1720, 720)
		]
	}

	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var screen_ratio: float = float(screen_size.x) / maxf(float(screen_size.y), 1.0)

	if aspect_mode == 0:
		# Автоматический подбор по физическому экрану игрока
		var matched_key: int = 0
		if absf(screen_ratio - (16.0 / 9.0)) < 0.08:
			matched_key = 1
		elif absf(screen_ratio - (16.0 / 10.0)) < 0.08:
			matched_key = 2
		elif absf(screen_ratio - (4.0 / 3.0)) < 0.08:
			matched_key = 3
		elif absf(screen_ratio - (21.0 / 9.0)) < 0.15:
			matched_key = 4

		if matched_key != 0:
			for r in presets[matched_key]:
				if r.x <= screen_size.x and r.y <= screen_size.y:
					current_res_list.append(r)
			if not current_res_list.has(screen_size):
				current_res_list.insert(0, screen_size)
		else:
			# Нестандартный экран: строим список от родного разрешения вниз до ~480p
			for scale_step in [1.0, 0.85, 0.75, 0.66, 0.5, 0.35]:
				var w: int = int(round(screen_size.x * scale_step))
				var h: int = int(round(screen_size.y * scale_step))
				if w >= 640 and h >= 360:
					var cand := Vector2i(w, h)
					if not current_res_list.has(cand):
						current_res_list.append(cand)
			if not current_res_list.has(Vector2i(640, 480)):
				current_res_list.append(Vector2i(640, 480))
	else:
		for r in presets.get(aspect_mode, []):
			current_res_list.append(r)

	var win_size: Vector2i = DisplayServer.window_get_size()
	var selected_idx: int = 0
	for i in range(current_res_list.size()):
		var r: Vector2i = current_res_list[i]
		option_res.add_item("%d x %d" % [r.x, r.y], i)
		if abs(win_size.x - r.x) < 40 and abs(win_size.y - r.y) < 40:
			selected_idx = i

	option_res.selected = selected_idx

func _apply_game_resolution(target_res: Vector2i) -> void:
	var root_win: Window = get_tree().root
	var is_full: bool = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	# Переводим режим масштабирования в viewport, чтобы менялось разрешение ВСЕЙ игры (и 3D, и UI),
	# но при родном разрешении экрана картинка оставалась пиксель-в-пиксель чёткой
	root_win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root_win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root_win.content_scale_size = target_res

	if not is_full:
		DisplayServer.window_set_size(target_res)
		var screen_center: Vector2i = DisplayServer.screen_get_position() + DisplayServer.screen_get_size() / 2
		DisplayServer.window_set_position(screen_center - target_res / 2)

	if slider_scale:
		slider_scale.set_value_no_signal(get_viewport().scaling_3d_scale)

var _rebinding_action: String = ""
var _rebinding_button: Button = null

func _get_action_key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "Не назначено"
	var events = InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode)
		elif ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: return "ЛКМ"
				MOUSE_BUTTON_RIGHT: return "ПКМ"
				MOUSE_BUTTON_MIDDLE: return "СКМ"
				_: return "Мышь %d" % ev.button_index
	return "Не назначено"

func _start_key_rebind(action: String, button: Button) -> void:
	_rebinding_action = action
	_rebinding_button = button
	button.text = "[Нажмите клавишу...]"

func _unhandled_key_input(event: InputEvent) -> void:
	if _rebinding_action == "" or _rebinding_button == null:
		return
	if event is InputEventKey and event.pressed:
		InputMap.action_erase_events(_rebinding_action)
		InputMap.action_add_event(_rebinding_action, event)
		_rebinding_button.text = _get_action_key_name(_rebinding_action)
		_rebinding_action = ""
		_rebinding_button = null
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		InputMap.action_erase_events(_rebinding_action)
		InputMap.action_add_event(_rebinding_action, event)
		_rebinding_button.text = _get_action_key_name(_rebinding_action)
		_rebinding_action = ""
		_rebinding_button = null
		get_viewport().set_input_as_handled()
